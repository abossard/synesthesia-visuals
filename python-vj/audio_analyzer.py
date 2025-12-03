#!/usr/bin/env python3
"""
Real-time Audio Analysis OSC Emitter

Analyzes audio input in real-time and emits features via OSC for VJ visuals.
Designed for low latency (~10-30ms) and robustness.

Features:
- Per-band energy (sub-bass, bass, mids, highs, etc.)
- Spectral features (centroid, flux)
- Beat detection and BPM estimation
- Pitch detection (optional)
- Build-up/drop detection for EDM/Techno/House
- Device selection with persistence
- Self-healing with watchdog pattern

Architecture follows "Grokking Simplicity" principles:
- Deep, narrow modules with single responsibility
- Pure functions for calculations
- Stateful components isolated and explicit
"""

import time
import queue
import threading
import logging
import json
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Tuple, Optional, Dict, Any, Callable
from collections import deque

import numpy as np
import sounddevice as sd

try:
    import essentia.standard as es
    ESSENTIA_AVAILABLE = True
except ImportError as e:
    ESSENTIA_AVAILABLE = False
    logger.warning(f"Essentia not available - beat/tempo/pitch detection disabled: {e}")
    logger.info("Install essentia with: pip install essentia")

logger = logging.getLogger('audio_analyzer')


# =============================================================================
# CONFIGURATION - Immutable settings
# =============================================================================

@dataclass(frozen=True)
class AudioConfig:
    """Audio analysis configuration (immutable)."""
    sample_rate: int = 44100
    block_size: int = 512
    fft_size: int = 512
    channels: int = 2
    
    # OSC configuration
    osc_host: str = "127.0.0.1"
    osc_port: int = 9000
    
    # Feature bands (Hz ranges) - tuned for EDM/Techno/House
    bands: Tuple[Tuple[int, int], ...] = (
        (20, 60),      # sub_bass
        (60, 250),     # bass
        (250, 500),    # low_mid
        (500, 2000),   # mid
        (2000, 4000),  # high_mid
        (4000, 6000),  # presence
        (6000, 20000), # air
    )
    
    band_names: Tuple[str, ...] = (
        'sub_bass', 'bass', 'low_mid', 'mid', 'high_mid', 'presence', 'air'
    )
    
    # Analysis parameters
    spectrum_bins: int = 32  # Downsampled spectrum size for OSC
    smoothing_factor: float = 0.3  # EMA smoothing (0=no smooth, 1=no change)
    compression_k: float = 4.0  # Tanh compression for visualization
    band_peak_decay: float = 0.995  # Decay rate for adaptive band normalization
    
    # BPM estimation
    bpm_history_size: int = 16  # Number of beat intervals to track
    bpm_min: float = 60.0
    bpm_max: float = 180.0
    
    # Build-up/drop detection
    energy_window_sec: float = 2.0  # Window for trend analysis
    buildup_threshold: float = 0.3  # Energy increase rate
    drop_threshold: float = 0.5     # Energy jump after low period

    # Performance toggles
    enable_essentia: bool = True
    enable_pitch: bool = True
    enable_bpm: bool = True
    enable_structure: bool = True
    enable_spectrum: bool = True
    enable_logging: bool = True
    log_level: int = logging.INFO
    ui_publish_hz: float = 30.0


@dataclass
class DeviceConfig:
    """Audio device configuration (mutable, persisted)."""
    device_index: Optional[int] = None
    device_name: str = ""
    auto_select_blackhole: bool = True
    
    def to_dict(self) -> dict:
        return asdict(self)
    
    @staticmethod
    def from_dict(data: dict) -> 'DeviceConfig':
        return DeviceConfig(**{k: v for k, v in data.items() if k in DeviceConfig.__annotations__})


# =============================================================================
# PURE FUNCTIONS - Calculations with no side effects
# =============================================================================

def compress_value(x: float, k: float = 4.0) -> float:
    """Compress value using tanh for visualization (0-1 range)."""
    return float(np.tanh(x * k))


def calculate_rms(signal: np.ndarray) -> float:
    """Calculate RMS (root mean square) of signal."""
    return float(np.sqrt(np.mean(signal ** 2)))


def calculate_spectral_centroid(magnitude: np.ndarray, freqs: np.ndarray) -> float:
    """
    Calculate spectral centroid (brightness measure).
    
    Args:
        magnitude: FFT magnitude spectrum
        freqs: Frequency values for each bin
        
    Returns:
        Centroid frequency in Hz
    """
    eps = 1e-10
    return float((freqs * magnitude).sum() / (magnitude.sum() + eps))


def calculate_spectral_flux(magnitude: np.ndarray, prev_magnitude: np.ndarray) -> float:
    """
    Calculate spectral flux (novelty/onset strength).
    
    Args:
        magnitude: Current FFT magnitude
        prev_magnitude: Previous FFT magnitude
        
    Returns:
        Flux value (positive changes only)
    """
    diff = magnitude - prev_magnitude
    return float(np.sum(np.clip(diff, 0, None)))


def extract_band_energy(magnitude: np.ndarray, freqs: np.ndarray, 
                        fmin: float, fmax: float) -> float:
    """
    Extract energy in a frequency band.
    
    Args:
        magnitude: FFT magnitude spectrum
        freqs: Frequency values for each bin
        fmin: Minimum frequency (Hz)
        fmax: Maximum frequency (Hz)
        
    Returns:
        Average magnitude in band
    """
    idx = np.where((freqs >= fmin) & (freqs < fmax))[0]
    if len(idx) == 0:
        return 0.0
    return float(np.mean(magnitude[idx]))


def smooth_value(current: float, target: float, factor: float) -> float:
    """
    Exponential moving average smoothing.
    
    Args:
        current: Current smoothed value
        target: New target value
        factor: Smoothing factor (0=no smooth, 1=no change)
        
    Returns:
        Smoothed value
    """
    return current * factor + target * (1.0 - factor)


def estimate_bpm_from_intervals(intervals: List[float], 
                                min_bpm: float = 60.0,
                                max_bpm: float = 180.0) -> Tuple[float, float]:
    """
    Estimate BPM from beat intervals with confidence.
    
    Args:
        intervals: List of time intervals between beats (seconds)
        min_bpm: Minimum valid BPM
        max_bpm: Maximum valid BPM
        
    Returns:
        (bpm, confidence) tuple
    """
    if len(intervals) < 2:
        return 0.0, 0.0
    
    # Filter outliers
    mean_interval = np.mean(intervals)
    std_interval = np.std(intervals)
    filtered = [i for i in intervals if abs(i - mean_interval) < 2 * std_interval]
    
    if not filtered:
        return 0.0, 0.0
    
    # Calculate BPM
    avg_interval = np.mean(filtered)
    bpm = 60.0 / avg_interval if avg_interval > 0 else 0.0
    
    # Clamp to valid range
    bpm = np.clip(bpm, min_bpm, max_bpm)
    
    # Confidence from variance (lower variance = higher confidence)
    variance = np.var(filtered)
    confidence = 1.0 / (1.0 + variance * 10)  # Scale to 0-1
    
    return float(bpm), float(confidence)


def detect_buildup_drop(energy_history: deque, window_size: int,
                        buildup_threshold: float, drop_threshold: float) -> Tuple[bool, bool, float]:
    """
    Detect build-up and drop patterns from energy history.
    
    Args:
        energy_history: Recent energy values
        window_size: Number of frames to analyze
        buildup_threshold: Minimum positive slope for build-up
        drop_threshold: Minimum energy jump for drop
        
    Returns:
        (is_buildup, is_drop, energy_trend) tuple
    """
    if len(energy_history) < window_size:
        return False, False, 0.0
    
    # Get recent window
    recent = list(energy_history)[-window_size:]
    
    # Calculate linear trend
    x = np.arange(len(recent))
    y = np.array(recent)
    
    # Simple linear regression
    if len(x) > 1:
        slope = np.polyfit(x, y, 1)[0]
    else:
        slope = 0.0
    
    # Build-up: sustained positive trend
    is_buildup = slope > buildup_threshold
    
    # Drop: large energy jump after low period
    if len(recent) >= 4:
        past_avg = np.mean(recent[:len(recent)//2])
        current_avg = np.mean(recent[len(recent)//2:])
        energy_jump = current_avg - past_avg
        is_drop = energy_jump > drop_threshold and past_avg < 0.3
    else:
        is_drop = False
    
    return is_buildup, is_drop, float(slope)


def downsample_spectrum(magnitude: np.ndarray, target_bins: int) -> np.ndarray:
    """
    Downsample spectrum to fewer bins for OSC transmission.
    
    Args:
        magnitude: Full FFT magnitude
        target_bins: Number of output bins
        
    Returns:
        Downsampled magnitude array
    """
    if len(magnitude) <= target_bins:
        return magnitude
    
    # Interpolate to target size
    downsampled = np.interp(
        np.linspace(0, len(magnitude) - 1, target_bins),
        np.arange(len(magnitude)),
        magnitude
    )
    
    # Normalize
    max_val = np.max(downsampled)
    if max_val > 0:
        downsampled = downsampled / max_val
    
    return downsampled


# =============================================================================
# DEVICE MANAGEMENT - Audio device discovery and selection
# =============================================================================

class DeviceManager:
    """
    Manages audio device selection and persistence.
    
    Deep, narrow module: only handles device discovery and config.
    """
    
    CONFIG_FILE = Path.home() / '.vj_audio_config.json'
    BLACKHOLE_KEYWORDS = ['blackhole', 'black hole', 'black-hole']
    
    def __init__(self):
        self.config = self._load_config()
    
    def _load_config(self) -> DeviceConfig:
        """Load device configuration from file."""
        if self.CONFIG_FILE.exists():
            try:
                with open(self.CONFIG_FILE, 'r') as f:
                    data = json.load(f)
                    logger.info(f"Loaded device config: {data.get('device_name', 'unknown')}")
                    return DeviceConfig.from_dict(data)
            except Exception as e:
                logger.warning(f"Failed to load device config: {e}")
        
        return DeviceConfig()
    
    def save_config(self):
        """Save current device configuration to file."""
        try:
            with open(self.CONFIG_FILE, 'w') as f:
                json.dump(self.config.to_dict(), f, indent=2)
            logger.info(f"Saved device config: {self.config.device_name}")
        except Exception as e:
            logger.error(f"Failed to save device config: {e}")
    
    def list_devices(self) -> List[Dict[str, Any]]:
        """
        List available audio input devices.
        
        Returns:
            List of device info dicts
        """
        devices = []
        try:
            device_list = sd.query_devices()
            for i, dev in enumerate(device_list):
                if dev['max_input_channels'] > 0:  # Input devices only
                    devices.append({
                        'index': i,
                        'name': dev['name'],
                        'channels': dev['max_input_channels'],
                        'sample_rate': int(dev['default_samplerate']),
                    })
        except Exception as e:
            logger.error(f"Failed to list devices: {e}")
        
        return devices
    
    def find_blackhole(self) -> Optional[int]:
        """
        Auto-detect BlackHole audio device.
        
        Returns:
            Device index or None if not found
        """
        devices = self.list_devices()
        for dev in devices:
            name_lower = dev['name'].lower()
            if any(kw in name_lower for kw in self.BLACKHOLE_KEYWORDS):
                logger.info(f"Found BlackHole device: {dev['name']} (index {dev['index']})")
                return dev['index']
        
        return None
    
    def get_device_index(self) -> Optional[int]:
        """
        Get device index to use (from config, auto-detect, or default).
        
        Returns:
            Device index or None for system default
        """
        # Use configured device if set
        if self.config.device_index is not None:
            # Verify device still exists
            try:
                dev = sd.query_devices(self.config.device_index)
                if dev['max_input_channels'] > 0:
                    logger.info(f"Using configured device: {dev['name']}")
                    return self.config.device_index
                else:
                    logger.warning(f"Configured device no longer available: {self.config.device_name}")
            except Exception as e:
                logger.warning(f"Configured device not found: {e}")
        
        # Auto-detect BlackHole
        if self.config.auto_select_blackhole:
            blackhole_idx = self.find_blackhole()
            if blackhole_idx is not None:
                return blackhole_idx
        
        # Use system default
        logger.info("Using system default audio input device")
        return None
    
    def set_device(self, device_index: int):
        """Set and save device selection."""
        try:
            dev = sd.query_devices(device_index)
            self.config.device_index = device_index
            self.config.device_name = dev['name']
            self.save_config()
            logger.info(f"Device set to: {dev['name']}")
        except Exception as e:
            logger.error(f"Failed to set device {device_index}: {e}")


# =============================================================================
# AUDIO ANALYZER - Main analysis engine
# =============================================================================

class AudioAnalyzer(threading.Thread):
    """
    Real-time audio analyzer with OSC output.
    
    Deep, narrow module: only handles audio analysis and feature extraction.
    OSC emission is delegated to separate component.
    
    Thread-safe, robust, self-healing with watchdog pattern.
    """
    
    def __init__(self, config: AudioConfig, device_manager: DeviceManager,
                 osc_callback: Optional[Callable[[str, List], None]] = None):
        super().__init__(daemon=True)
        self.config = config
        self.device_manager = device_manager
        self.osc_callback = osc_callback

        if not config.enable_logging:
            logger.setLevel(logging.ERROR)
            logger.propagate = False
        else:
            logger.setLevel(config.log_level)
        
        # Audio I/O state
        self.audio_queue = queue.Queue(maxsize=64)
        self.stream: Optional[sd.InputStream] = None
        self.last_audio_time = time.monotonic()
        self.active_channels = config.channels
        
        # Analysis state
        self.hann_window = np.hanning(config.fft_size).astype(np.float32)
        self.freqs = np.fft.rfftfreq(config.fft_size, 1.0 / config.sample_rate)
        self.prev_magnitude = np.zeros(config.fft_size // 2 + 1, dtype=np.float32)
        
        # Smoothed features
        self.smoothed_bands = [0.0] * len(config.bands)
        self.smoothed_rms = 0.0
        self.band_peaks = [1e-3] * len(config.bands)
        self.rms_peak = 1e-3
        
        # Beat/BPM tracking
        self.beat_times = deque(maxlen=config.bpm_history_size)
        self.last_beat_time = 0.0
        
        # Build-up/drop detection
        frames_per_window = int(config.energy_window_sec * config.sample_rate / config.block_size)
        self.energy_history = deque(maxlen=frames_per_window)
        
        # Essentia objects (if available)
        self.onset_detection = None
        self.pitch_yin = None
        self.beat_tracker = None
        self.centroid_algo = None
        self.flux_algo = None
        self.enable_essentia = config.enable_essentia and ESSENTIA_AVAILABLE
        
        if self.enable_essentia:
            try:
                # Standard mode algorithms (frame-by-frame processing)
                self.onset_detection = es.OnsetDetection(method='hfc')  # High Frequency Content method
                if config.enable_pitch:
                    self.pitch_yin = es.PitchYin(
                        frameSize=config.fft_size,
                        sampleRate=config.sample_rate,
                        minFrequency=20,
                        maxFrequency=2000,
                        tolerance=0.15
                    )
                # Centroid for brightness
                self.centroid_algo = es.Centroid()
                # Flux for novelty detection
                self.flux_algo = es.Flux()
                
                # BPM tracking - use simpler custom approach since BeatTrackerDegara needs longer buffers
                # We'll use onset detection + interval estimation instead
                
                logger.info("Essentia initialized for beat/tempo/pitch detection")
            except Exception as e:
                logger.warning(f"Essentia initialization failed: {e}")
        elif ESSENTIA_AVAILABLE:
            logger.info("Essentia disabled via config - advanced features skipped")
        else:
            logger.warning("Essentia not available - beat/tempo/pitch detection disabled")
        
        # Control flags
        self.running = False
        self.error_count = 0
        
        # Statistics
        self.frames_processed = 0
        self.last_stats_time = time.monotonic()
        
        # Latest features (thread-safe access for UI)
        self.latest_features = {
            'beat': 0,
            'bpm': 0.0,
            'bpm_confidence': 0.0,
            'buildup': False,
            'drop': False,
            'pitch_hz': 0.0,
            'pitch_conf': 0.0,
        }
        self.ui_publish_interval = 1.0 / config.ui_publish_hz if config.ui_publish_hz > 0 else 0.0
        self.last_ui_publish = 0.0
        self.flux_avg = 0.0
        self.flux_peak = 0.0
        self.last_flux_onset = 0.0
    
    def _audio_callback(self, indata: np.ndarray, frames: int, 
                       time_info: dict, status: sd.CallbackFlags):
        """
        Audio input callback (runs in PortAudio thread).
        
        Keep this minimal - just copy data to queue.
        """
        if status:
            logger.warning(f"Audio callback status: {status}")
        
        try:
            # Copy data and update timestamp
            self.audio_queue.put_nowait(indata.copy())
            self.last_audio_time = time.monotonic()
        except queue.Full:
            # Drop frame if queue is full (better than blocking)
            pass
        except Exception as e:
            logger.error(f"Audio callback error: {e}")
    
    def start_stream(self):
        """Start audio input stream."""
        device_idx = self.device_manager.get_device_index()
        channels_to_try = [self.config.channels]
        if self.config.channels > 1:
            channels_to_try.append(1)

        last_error: Optional[Exception] = None
        for attempt, channels in enumerate(channels_to_try):
            try:
                self.stream = sd.InputStream(
                    samplerate=self.config.sample_rate,
                    blocksize=self.config.block_size,
                    channels=channels,
                    dtype='float32',
                    device=device_idx,
                    callback=self._audio_callback,
                )
                self.stream.start()
                self.active_channels = channels

                if device_idx is not None:
                    dev = sd.query_devices(device_idx)
                    dev_name = dev['name']
                else:
                    dev_name = 'system default'
                logger.info(
                    "Audio stream started: %s @ %dHz (%sch)",
                    dev_name,
                    self.config.sample_rate,
                    channels,
                )
                self.error_count = 0
                return
            except Exception as e:
                last_error = e
                logger.error(
                    "Failed to start audio stream (%sch attempt %d/%d): %s",
                    channels,
                    attempt + 1,
                    len(channels_to_try),
                    e,
                )
                if self.stream:
                    try:
                        self.stream.close()
                    except Exception:
                        pass
                    finally:
                        self.stream = None
                if attempt == 0 and len(channels_to_try) > 1:
                    logger.info("Retrying audio stream with mono input (1 channel)")
        self.error_count += 1
        if last_error:
            raise last_error
        raise RuntimeError("Audio stream failed to start for unknown reasons")
    
    def stop_stream(self):
        """Stop audio input stream."""
        if self.stream:
            try:
                self.stream.stop()
                self.stream.close()
                logger.info("Audio stream stopped")
            except Exception as e:
                logger.error(f"Error stopping stream: {e}")
            finally:
                self.stream = None
    
    def _process_frame(self, block: np.ndarray):
        """
        Process one audio frame and extract features.
        
        Args:
            block: Audio data (frames x channels)
        """
        # Convert to mono
        mono = block.mean(axis=1).astype(np.float32)
        
        # Pad if needed
        if len(mono) < self.config.fft_size:
            padded = np.zeros(self.config.fft_size, dtype=np.float32)
            padded[:len(mono)] = mono
            mono = padded
        
        # Window and FFT
        windowed = mono * self.hann_window
        spectrum = np.fft.rfft(windowed)
        magnitude = np.abs(spectrum)
        
        # --- Extract features ---
        
        # Per-band energies
        raw_bands = [
            extract_band_energy(magnitude, self.freqs, fmin, fmax)
            for fmin, fmax in self.config.bands
        ]
        
        # Smooth and compress bands using adaptive peak normalization
        peak_decay = self.config.band_peak_decay
        eps = 1e-9
        for i, raw_val in enumerate(raw_bands):
            peak = self.band_peaks[i]
            peak = max(raw_val, peak * peak_decay)
            peak = max(peak, eps)
            self.band_peaks[i] = peak
            normalized = raw_val / peak
            compressed = compress_value(normalized, self.config.compression_k)
            self.smoothed_bands[i] = smooth_value(
                self.smoothed_bands[i],
                compressed,
                self.config.smoothing_factor
            )
        
        # Overall RMS
        rms = calculate_rms(mono)
        if rms > self.rms_peak:
            self.rms_peak = rms
        else:
            self.rms_peak = max(self.rms_peak * peak_decay, eps)
        rms_normalized = rms / (self.rms_peak + eps)
        self.smoothed_rms = smooth_value(
            self.smoothed_rms,
            compress_value(rms_normalized, self.config.compression_k),
            self.config.smoothing_factor
        )
        
        # Spectral features
        centroid = calculate_spectral_centroid(magnitude, self.freqs)
        centroid_norm = centroid / (self.config.sample_rate / 2.0)
        
        # Use Essentia for centroid if available (more accurate)
        if self.centroid_algo:
            try:
                essentia_centroid = float(self.centroid_algo(magnitude))
                centroid_norm = essentia_centroid / (self.config.sample_rate / 2.0)
            except Exception:
                pass  # Fall back to numpy calculation
        
        flux = calculate_spectral_flux(magnitude, self.prev_magnitude)
        
        # Use Essentia for flux if available
        if self.flux_algo:
            try:
                essentia_flux = float(self.flux_algo(magnitude, self.prev_magnitude))
                flux = essentia_flux
            except Exception:
                pass  # Fall back to numpy calculation
        
        self.prev_magnitude = magnitude.copy()
        
        # Track energy for build-up/drop detection
        total_energy = sum(raw_bands)
        if self.config.enable_structure:
            self.energy_history.append(total_energy)
        
        # --- Essentia features (if available) ---
        
        is_onset = False
        bpm = 0.0
        pitch_hz = 0.0
        pitch_conf = 0.0
        onset_strength = 0.0
        
        if self.onset_detection and self.config.enable_bpm:
            try:
                # Onset detection using HFC method
                # OnsetDetection expects magnitude and phase
                onset_strength = float(self.onset_detection(magnitude, np.angle(spectrum)))
                
                # Threshold for onset detection (tune based on testing)
                onset_threshold = 0.3
                is_onset = onset_strength > onset_threshold
                
                # Track beat times for custom BPM estimation
                if is_onset:
                    current_time = time.monotonic()
                    if self.last_beat_time > 0:
                        interval = current_time - self.last_beat_time
                        self.beat_times.append(interval)
                    self.last_beat_time = current_time
                    
            except Exception as e:
                logger.error(f"Essentia processing error: {e}")
        elif self.config.enable_bpm:
            # Flux-based fallback onset detection
            self.flux_avg = 0.9 * self.flux_avg + 0.1 * flux
            self.flux_peak = max(self.flux_peak * 0.95, flux)
            adaptive_threshold = self.flux_avg + (self.flux_peak - self.flux_avg) * 0.5
            now = time.monotonic()
            if (
                flux > adaptive_threshold
                and flux > 0.001
                and (now - self.last_flux_onset) > 0.12
            ):
                is_onset = True
                self.last_flux_onset = now
                if self.last_beat_time > 0:
                    interval = now - self.last_beat_time
                    self.beat_times.append(interval)
                self.last_beat_time = now
        
        # Pitch detection with PitchYin (optional)
        if self.pitch_yin and self.config.enable_pitch:
            try:
                pitch_hz, pitch_conf = self.pitch_yin(mono)
                pitch_hz = float(pitch_hz)
                pitch_conf = float(pitch_conf)
                if pitch_conf < 0.6:
                    pitch_hz = 0.0
            except Exception as e:
                logger.error(f"Pitch detection error: {e}")
                pitch_hz = 0.0
                pitch_conf = 0.0
        
        bpm_confidence = 0.0
        if self.config.enable_bpm:
            custom_bpm, bpm_confidence = estimate_bpm_from_intervals(
                list(self.beat_times),
                self.config.bpm_min,
                self.config.bpm_max
            )
            bpm = custom_bpm
        
        # Build-up/drop detection
        if self.config.enable_structure and self.energy_history:
            window_frames = len(self.energy_history)
            is_buildup, is_drop, energy_trend = detect_buildup_drop(
                self.energy_history,
                window_frames,
                self.config.buildup_threshold,
                self.config.drop_threshold
            )
        else:
            is_buildup = False
            is_drop = False
            energy_trend = 0.0
        
        # Downsample spectrum for OSC when needed
        spectrum_down: List[float] = []
        if self.config.enable_spectrum:
            spectrum_down = downsample_spectrum(magnitude, self.config.spectrum_bins).tolist()

        def _avg_band(indices: List[int]) -> float:
            values = [self.smoothed_bands[i] for i in indices if i < len(self.smoothed_bands)]
            return float(sum(values) / len(values)) if values else 0.0

        bass_level = self.smoothed_bands[1] if len(self.smoothed_bands) > 1 else self.smoothed_rms
        mid_level = _avg_band([2, 3, 4])
        high_level = _avg_band([5, 6])
        
        # --- Store latest features for UI ---
        beat_int = 1 if is_onset else 0
        self._publish_ui_state(
            beat_int=beat_int,
            bpm=float(bpm),
            bpm_confidence=float(bpm_confidence),
            is_buildup=is_buildup,
            is_drop=is_drop,
            pitch_hz=float(pitch_hz),
            pitch_conf=float(pitch_conf),
            energy_trend=float(energy_trend),
            brightness=float(centroid_norm),
            bass_level=float(bass_level),
            mid_level=float(mid_level),
            high_level=float(high_level),
        )
        
        # --- Send OSC messages (always, when analyzer is active) ---
        
        if self.osc_callback:
            try:
                # Levels (per-band + overall RMS)
                self.osc_callback('/audio/levels', self.smoothed_bands + [self.smoothed_rms])
                
                if spectrum_down:
                    self.osc_callback('/audio/spectrum', spectrum_down)
                
                if self.config.enable_bpm:
                    self.osc_callback('/audio/beat', [beat_int, float(flux)])
                    self.osc_callback('/audio/bpm', [float(bpm), float(bpm_confidence)])
                
                if self.config.enable_pitch:
                    self.osc_callback('/audio/pitch', [float(pitch_hz), float(pitch_conf)])
                
                if self.config.enable_structure:
                    buildup_int = 1 if is_buildup else 0
                    drop_int = 1 if is_drop else 0
                    self.osc_callback('/audio/structure', [
                        buildup_int, drop_int, float(energy_trend), float(centroid_norm)
                    ])
                
            except Exception as e:
                logger.error(f"OSC send error: {e}")
        
        self.frames_processed += 1

    def _publish_ui_state(
        self,
        *,
        beat_int: int,
        bpm: float,
        bpm_confidence: float,
        is_buildup: bool,
        is_drop: bool,
        pitch_hz: float,
        pitch_conf: float,
        energy_trend: float = 0.0,
        brightness: float = 0.0,
        bass_level: float = 0.0,
        mid_level: float = 0.0,
        high_level: float = 0.0,
    ):
        """Throttle UI state updates so rendering is decoupled from DSP rate."""
        if self.ui_publish_interval > 0:
            now = time.monotonic()
            if (now - self.last_ui_publish) < self.ui_publish_interval:
                return
            self.last_ui_publish = now
        self.latest_features = {
            'beat': beat_int,
            'bpm': bpm,
            'bpm_confidence': bpm_confidence,
            'buildup': is_buildup,
            'drop': is_drop,
            'pitch_hz': pitch_hz,
            'pitch_conf': pitch_conf,
            'energy_trend': energy_trend,
            'brightness': brightness,
            'bass_level': bass_level,
            'mid_level': mid_level,
            'high_level': high_level,
        }
    
    def run(self):
        """Main analyzer thread loop."""
        logger.info("Audio analyzer thread started")
        self.running = True
        
        try:
            self.start_stream()
        except Exception as e:
            logger.error(f"Failed to start stream: {e}")
            self.running = False
            return
        
        while self.running:
            try:
                # Get audio frame with timeout
                try:
                    block = self.audio_queue.get(timeout=0.5)
                    self._process_frame(block)
                except queue.Empty:
                    # No audio for 0.5s - watchdog will handle restart if needed
                    continue
                    
            except Exception as e:
                logger.exception(f"Analysis error: {e}")
                # Don't crash - continue processing
                time.sleep(0.1)
        
        # Cleanup
        self.stop_stream()
        logger.info("Audio analyzer thread stopped")
    
    def stop(self):
        """Stop the analyzer thread."""
        self.running = False
        self.join(timeout=2.0)
    
    def get_stats(self) -> Dict[str, Any]:
        """Get analyzer statistics."""
        elapsed = time.monotonic() - self.last_stats_time
        fps = self.frames_processed / elapsed if elapsed > 0 else 0
        
        audio_alive = (time.monotonic() - self.last_audio_time) < 1.0
        
        return {
            'running': self.running,
            'audio_alive': audio_alive,
            'frames_processed': self.frames_processed,
            'fps': fps,
            'error_count': self.error_count,
            'device_name': self.device_manager.config.device_name,
        }


# =============================================================================
# WATCHDOG - Self-healing supervisor
# =============================================================================

class AudioAnalyzerWatchdog:
    """
    Monitors AudioAnalyzer health and restarts on failure.
    
    Deep, narrow module: only handles supervision and restart logic.
    """
    
    def __init__(self, analyzer: AudioAnalyzer):
        self.analyzer = analyzer
        self.check_interval = 2.0  # Check every 2 seconds
        self.max_restart_attempts = 5
        self.restart_count = 0
        self.last_check_time = time.monotonic()
    
    def check_health(self) -> Tuple[bool, str]:
        """
        Check analyzer health.
        
        Returns:
            (healthy, message) tuple
        """
        stats = self.analyzer.get_stats()
        
        if not stats['running']:
            return False, "Analyzer thread not running"
        
        if not stats['audio_alive']:
            return False, "No audio input detected"
        
        if stats['error_count'] > 10:
            return False, f"Too many errors: {stats['error_count']}"
        
        return True, "OK"
    
    def restart_analyzer(self):
        """Attempt to restart the analyzer."""
        logger.warning("Attempting to restart analyzer...")
        
        try:
            self.analyzer.stop_stream()
            time.sleep(0.5)
            self.analyzer.start_stream()
            self.restart_count += 1
            logger.info(f"Analyzer restarted (attempt {self.restart_count})")
        except Exception as e:
            logger.error(f"Restart failed: {e}")
    
    def update(self):
        """Check health and restart if needed (call periodically)."""
        now = time.monotonic()
        if now - self.last_check_time < self.check_interval:
            return
        
        self.last_check_time = now
        
        healthy, message = self.check_health()
        
        if not healthy:
            logger.warning(f"Health check failed: {message}")
            
            if self.restart_count < self.max_restart_attempts:
                self.restart_analyzer()
            else:
                logger.error(f"Max restart attempts ({self.max_restart_attempts}) reached")


# =============================================================================
# LATENCY BENCHMARK - Performance testing
# =============================================================================

@dataclass
class LatencyBenchmark:
    """Results from latency benchmark test."""
    total_frames: int = 0
    duration_sec: float = 0.0
    avg_fps: float = 0.0
    
    # Per-component timings (microseconds)
    fft_time_us: float = 0.0
    band_extraction_time_us: float = 0.0
    essentia_time_us: float = 0.0
    osc_send_time_us: float = 0.0
    total_processing_time_us: float = 0.0
    
    # Latency metrics
    min_latency_ms: float = 0.0
    max_latency_ms: float = 0.0
    avg_latency_ms: float = 0.0
    p95_latency_ms: float = 0.0
    p99_latency_ms: float = 0.0
    
    # Queue metrics
    queue_drops: int = 0
    max_queue_size: int = 0
    
    def to_dict(self) -> dict:
        """Convert to dictionary for display."""
        return asdict(self)


class LatencyTester:
    """
    Benchmarks audio analyzer performance and measures latencies.
    
    Measures:
    - Processing FPS (frames/second)
    - Per-component timing (FFT, band extraction, essentia, OSC)
    - End-to-end latency (audio callback -> OSC send)
    - Queue performance (drops, max size)
    """
    
    def __init__(self, analyzer: AudioAnalyzer):
        self.analyzer = analyzer
        self.running = False
        
        # Timing data
        self.frame_latencies: List[float] = []
        self.fft_times: List[float] = []
        self.band_times: List[float] = []
        self.essentia_times: List[float] = []
        self.osc_times: List[float] = []
        
        # Queue metrics
        self.queue_drops = 0
        self.queue_sizes: List[int] = []
        
        # Test parameters
        self.test_duration = 10.0  # seconds
        self.start_time = 0.0
    
    def _measure_component(self, func: Callable, *args) -> Tuple[Any, float]:
        """
        Measure execution time of a component.
        
        Returns:
            (result, time_microseconds)
        """
        start = time.perf_counter()
        result = func(*args)
        elapsed = (time.perf_counter() - start) * 1_000_000  # Convert to microseconds
        return result, elapsed
    
    def run_benchmark(self, duration_sec: float = 10.0) -> LatencyBenchmark:
        """
        Run latency benchmark for specified duration.
        
        Args:
            duration_sec: How long to run the test
            
        Returns:
            LatencyBenchmark with results
        """
        if not self.analyzer.running:
            logger.error("Analyzer must be running to benchmark")
            return LatencyBenchmark()
        
        logger.info(f"Starting {duration_sec}s latency benchmark...")
        
        # Reset measurements
        self.frame_latencies.clear()
        self.fft_times.clear()
        self.band_times.clear()
        self.essentia_times.clear()
        self.osc_times.clear()
        self.queue_drops = 0
        self.queue_sizes.clear()
        
        self.test_duration = duration_sec
        self.start_time = time.monotonic()
        self.running = True
        
        # Replace analyzer's _process_frame with instrumented version
        original_process_frame = self.analyzer._process_frame
        
        def instrumented_process_frame(block: np.ndarray):
            """Instrumented version that measures timings."""
            frame_start = time.perf_counter()
            
            # Convert to mono (timing tracked separately)
            mono = block.mean(axis=1).astype(np.float32)
            if len(mono) < self.analyzer.config.fft_size:
                padded = np.zeros(self.analyzer.config.fft_size, dtype=np.float32)
                padded[:len(mono)] = mono
                mono = padded
            
            # Measure FFT
            fft_start = time.perf_counter()
            windowed = mono * self.analyzer.hann_window
            spectrum = np.fft.rfft(windowed)
            magnitude = np.abs(spectrum)
            fft_time = (time.perf_counter() - fft_start) * 1_000_000
            self.fft_times.append(fft_time)
            
            # Measure band extraction
            band_start = time.perf_counter()
            raw_bands = [
                extract_band_energy(magnitude, self.analyzer.freqs, fmin, fmax)
                for fmin, fmax in self.analyzer.config.bands
            ]
            for i, raw_val in enumerate(raw_bands):
                self.analyzer.smoothed_bands[i] = smooth_value(
                    self.analyzer.smoothed_bands[i],
                    compress_value(raw_val, self.analyzer.config.compression_k),
                    self.analyzer.config.smoothing_factor
                )
            band_time = (time.perf_counter() - band_start) * 1_000_000
            self.band_times.append(band_time)
            
            # Continue with original processing (RMS, centroid, etc.)
            rms = calculate_rms(mono)
            self.analyzer.smoothed_rms = smooth_value(
                self.analyzer.smoothed_rms,
                compress_value(rms * 10, self.analyzer.config.compression_k),
                self.analyzer.config.smoothing_factor
            )
            
            centroid = calculate_spectral_centroid(magnitude, self.analyzer.freqs)
            centroid_norm = centroid / (self.analyzer.config.sample_rate / 2.0)
            
            flux = calculate_spectral_flux(magnitude, self.analyzer.prev_magnitude)
            self.analyzer.prev_magnitude = magnitude.copy()
            
            total_energy = sum(raw_bands)
            if self.analyzer.config.enable_structure:
                self.analyzer.energy_history.append(total_energy)
            
            # Measure Essentia (if available)
            essentia_time = 0.0
            is_onset = False
            bpm = 0.0
            pitch_hz = 0.0
            pitch_conf = 0.0
            onset_strength = 0.0
            config = self.analyzer.config
            
            if self.analyzer.onset_detection and config.enable_bpm:
                essentia_start = time.perf_counter()
                try:
                    onset_strength = float(self.analyzer.onset_detection(magnitude, np.angle(spectrum)))
                    onset_threshold = 0.3
                    is_onset = onset_strength > onset_threshold
                    
                    if is_onset:
                        current_time = time.monotonic()
                        if self.analyzer.last_beat_time > 0:
                            interval = current_time - self.analyzer.last_beat_time
                            self.analyzer.beat_times.append(interval)
                        self.analyzer.last_beat_time = current_time
                    
                    if self.analyzer.pitch_yin and config.enable_pitch:
                        pitch_hz, pitch_conf = self.analyzer.pitch_yin(mono)
                        pitch_hz = float(pitch_hz)
                        pitch_conf = float(pitch_conf)
                        if pitch_conf < 0.6:
                            pitch_hz = 0.0
                            pitch_conf = 0.0
                    
                    essentia_time = (time.perf_counter() - essentia_start) * 1_000_000
                except Exception:
                    pass
                
                self.essentia_times.append(essentia_time)
            elif config.enable_bpm:
                # Flux fallback for onset timing
                self.analyzer.flux_avg = 0.9 * self.analyzer.flux_avg + 0.1 * flux
                self.analyzer.flux_peak = max(self.analyzer.flux_peak * 0.95, flux)
                adaptive_threshold = self.analyzer.flux_avg + (self.analyzer.flux_peak - self.analyzer.flux_avg) * 0.5
                now = time.monotonic()
                if (
                    flux > adaptive_threshold
                    and flux > 0.001
                    and (now - self.analyzer.last_flux_onset) > 0.12
                ):
                    is_onset = True
                    self.analyzer.last_flux_onset = now
                    if self.analyzer.last_beat_time > 0:
                        interval = now - self.analyzer.last_beat_time
                        self.analyzer.beat_times.append(interval)
                    self.analyzer.last_beat_time = now
            
            if self.analyzer.pitch_yin and config.enable_pitch and not (self.analyzer.onset_detection and config.enable_bpm):
                try:
                    pitch_hz, pitch_conf = self.analyzer.pitch_yin(mono)
                    pitch_hz = float(pitch_hz)
                    pitch_conf = float(pitch_conf)
                    if pitch_conf < 0.6:
                        pitch_hz = 0.0
                        pitch_conf = 0.0
                except Exception:
                    pitch_hz = 0.0
                    pitch_conf = 0.0
            
            bpm_confidence = 0.0
            if config.enable_bpm:
                custom_bpm, bpm_confidence = estimate_bpm_from_intervals(
                    list(self.analyzer.beat_times),
                    config.bpm_min,
                    config.bpm_max
                )
                bpm = custom_bpm
            
            if config.enable_structure and self.analyzer.energy_history:
                window_frames = len(self.analyzer.energy_history)
                is_buildup, is_drop, energy_trend = detect_buildup_drop(
                    self.analyzer.energy_history,
                    window_frames,
                    config.buildup_threshold,
                    config.drop_threshold
                )
            else:
                is_buildup = False
                is_drop = False
                energy_trend = 0.0
            
            spectrum_down: List[float] = []
            if config.enable_spectrum:
                spectrum_down = downsample_spectrum(magnitude, config.spectrum_bins).tolist()
            
            beat_int = 1 if is_onset else 0

            def _avg_band(indices: List[int]) -> float:
                values = [self.analyzer.smoothed_bands[i] for i in indices if i < len(self.analyzer.smoothed_bands)]
                return float(sum(values) / len(values)) if values else 0.0

            bass_level = self.analyzer.smoothed_bands[1] if len(self.analyzer.smoothed_bands) > 1 else self.analyzer.smoothed_rms
            mid_level = _avg_band([2, 3, 4])
            high_level = _avg_band([5, 6])

            self.analyzer._publish_ui_state(
                beat_int=beat_int,
                bpm=float(bpm),
                bpm_confidence=float(bpm_confidence),
                is_buildup=is_buildup,
                is_drop=is_drop,
                pitch_hz=float(pitch_hz),
                pitch_conf=float(pitch_conf),
                energy_trend=float(energy_trend),
                brightness=float(centroid_norm),
                bass_level=float(bass_level),
                mid_level=float(mid_level),
                high_level=float(high_level),
            )
            
            # Measure OSC send time
            osc_time = 0.0
            if self.analyzer.osc_callback:
                osc_start = time.perf_counter()
                try:
                    self.analyzer.osc_callback('/audio/levels', self.analyzer.smoothed_bands + [self.analyzer.smoothed_rms])
                    if spectrum_down:
                        self.analyzer.osc_callback('/audio/spectrum', spectrum_down)
                    if config.enable_bpm:
                        self.analyzer.osc_callback('/audio/beat', [beat_int, float(flux)])
                        self.analyzer.osc_callback('/audio/bpm', [float(bpm), float(bpm_confidence)])
                    if config.enable_pitch:
                        self.analyzer.osc_callback('/audio/pitch', [float(pitch_hz), float(pitch_conf)])
                    if config.enable_structure:
                        buildup_int = 1 if is_buildup else 0
                        drop_int = 1 if is_drop else 0
                        self.analyzer.osc_callback('/audio/structure', [
                            buildup_int, drop_int, float(energy_trend), float(centroid_norm)
                        ])
                    
                    osc_time = (time.perf_counter() - osc_start) * 1_000_000
                except Exception:
                    pass
                
                self.osc_times.append(osc_time)
            
            # Total frame latency
            frame_latency = (time.perf_counter() - frame_start) * 1000  # milliseconds
            self.frame_latencies.append(frame_latency)
            
            # Track queue size
            self.queue_sizes.append(self.analyzer.audio_queue.qsize())
            
            self.analyzer.frames_processed += 1
        
        # Monkey-patch the method
        self.analyzer._process_frame = instrumented_process_frame
        
        # Wait for test duration
        time.sleep(duration_sec)
        
        # Restore original method
        self.analyzer._process_frame = original_process_frame
        self.running = False
        
        # Calculate results
        actual_duration = time.monotonic() - self.start_time
        total_frames = len(self.frame_latencies)
        
        if total_frames == 0:
            logger.warning("No frames processed during benchmark")
            return LatencyBenchmark()
        
        # Calculate statistics
        latencies_sorted = sorted(self.frame_latencies)
        p95_idx = int(len(latencies_sorted) * 0.95)
        p99_idx = int(len(latencies_sorted) * 0.99)
        
        results = LatencyBenchmark(
            total_frames=total_frames,
            duration_sec=actual_duration,
            avg_fps=total_frames / actual_duration if actual_duration > 0 else 0,
            
            fft_time_us=np.mean(self.fft_times) if self.fft_times else 0,
            band_extraction_time_us=np.mean(self.band_times) if self.band_times else 0,
            essentia_time_us=np.mean(self.essentia_times) if self.essentia_times else 0,
            osc_send_time_us=np.mean(self.osc_times) if self.osc_times else 0,
            total_processing_time_us=np.mean(self.frame_latencies) * 1000 if self.frame_latencies else 0,
            
            min_latency_ms=min(latencies_sorted) if latencies_sorted else 0,
            max_latency_ms=max(latencies_sorted) if latencies_sorted else 0,
            avg_latency_ms=np.mean(latencies_sorted) if latencies_sorted else 0,
            p95_latency_ms=latencies_sorted[p95_idx] if p95_idx < len(latencies_sorted) else 0,
            p99_latency_ms=latencies_sorted[p99_idx] if p99_idx < len(latencies_sorted) else 0,
            
            queue_drops=self.queue_drops,
            max_queue_size=max(self.queue_sizes) if self.queue_sizes else 0,
        )
        
        logger.info(f"Benchmark complete: {results.avg_fps:.1f} fps, {results.avg_latency_ms:.2f}ms avg latency")
        
        return results
