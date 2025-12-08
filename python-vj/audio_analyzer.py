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

import argparse
import sys
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

# Try to import sounddevice (needs PortAudio library)
try:
    import sounddevice as sd
    SOUNDDEVICE_AVAILABLE = True
except (ImportError, OSError):
    SOUNDDEVICE_AVAILABLE = False
    sd = None

# Essentia is mandatory for this analyzer
import essentia.standard as es
ESSENTIA_AVAILABLE = True

try:
    from pythonosc import udp_client
    OSC_AVAILABLE = True
except ImportError:
    udp_client = None
    OSC_AVAILABLE = False

logger = logging.getLogger('audio_analyzer')

# Log library availability after logger is initialized
if not SOUNDDEVICE_AVAILABLE:
    logger.warning("sounddevice not available - audio input disabled")
    logger.info("Install PortAudio library and sounddevice with: pip install sounddevice")


# =============================================================================
# CONFIGURATION - Immutable settings
# =============================================================================

@dataclass(frozen=True)
class AudioConfig:
    """Audio analysis configuration (immutable)."""
    sample_rate: int = 44100
    block_size: int = 1024  # Align with Essentia rhythm tutorial (frameSize)
    fft_size: int = 1024    # Align with Essentia rhythm tutorial (frameSize)
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
    
    # EDM-specific features (EMA smoothing coefficients)
    ema_energy: float = 0.2  # Fast response for energy (0.8 * prev + 0.2 * new)
    ema_brightness: float = 0.3  # Medium response for brightness
    ema_bands: float = 0.2  # Fast response for bass/mid/high bands
    
    # Running normalization window
    norm_window_sec: float = 10.0  # Sliding window for running max normalization

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
    
    # Filter outliers (only if there's variance)
    mean_interval = np.mean(intervals)
    std_interval = np.std(intervals)
    
    if std_interval > 0:
        # Filter out outliers beyond 2 standard deviations
        filtered = [i for i in intervals if abs(i - mean_interval) < 2 * std_interval]
    else:
        # All intervals are identical - use all of them
        filtered = intervals
    
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
        if not SOUNDDEVICE_AVAILABLE or sd is None:
            return []
        
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
        if not SOUNDDEVICE_AVAILABLE or sd is None:
            return None
        
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
        if not SOUNDDEVICE_AVAILABLE or sd is None:
            logger.error("Cannot set device: sounddevice not available")
            return
        
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
        self.stream: Optional[Any] = None  # sd.InputStream when available
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
        self.flux_smooth = 0.0
        
        # Build-up/drop detection
        frames_per_window = int(config.energy_window_sec * config.sample_rate / config.block_size)
        self.energy_history = deque(maxlen=frames_per_window)
        
        # Essentia objects (if available)
        self.onset_hfc = None
        self.onset_complex = None
        self.onset_flux = None
        self.pitch_yin = None
        self.centroid_algo = None
        self.rolloff_algo = None
        self.flux_algo = None
        self.energy_algo = None
        self.onset_rate = None
        
        # EDM-specific Essentia algorithms
        self.rhythm_extractor = None
        self.beats_loudness = None
        self.flatness_algo = None
        self.spread_algo = None
        self.loudness_algo = None
        
        # Essentia is required; initialize algorithms
        if not ESSENTIA_AVAILABLE:
            raise RuntimeError("Essentia is required for audio analysis")
        try:
            if config.enable_bpm:
                self.rhythm_extractor = es.RhythmExtractor2013(
                    method='multifeature',
                    minTempo=int(config.bpm_min),
                    maxTempo=int(config.bpm_max),
                )
                logger.info("Using RhythmExtractor2013 (multifeature) for beat/BPM tracking")
                self.onset_hfc = es.OnsetDetection(method='hfc')
                self.onset_complex = es.OnsetDetection(method='complex')
                self.onset_flux = es.OnsetDetection(method='flux')
            if config.enable_pitch:
                self.pitch_yin = es.PitchYin(
                    frameSize=config.fft_size,
                    sampleRate=config.sample_rate,
                    minFrequency=20,
                    maxFrequency=2000,
                    tolerance=0.15
                )
            self.centroid_algo = es.Centroid()
            self.rolloff_algo = es.RollOff()
            self.flux_algo = es.Flux()
            self.flatness_algo = es.Flatness()
            self.spread_algo = es.CentralMoments()
            self.energy_algo = es.Energy()
            self.loudness_algo = es.Loudness()
            logger.info("Essentia initialized (multifeature rhythm, spectral, pitch)")
        except Exception as e:
            raise RuntimeError(f"Essentia initialization failed: {e}")
        
        # Control flags
        self.running = False
        self.error_count = 0
        
        # Statistics
        self.frames_processed = 0
        self.last_stats_time = time.monotonic()
        
        # EDM feature state with EMA smoothing
        self.energy_smooth = 0.0
        self.brightness_smooth = 0.0  # Normalized centroid with EMA
        self.noisiness_smooth = 0.0  # Spectral flatness with EMA
        self.bass_band_smooth = 0.0
        self.mid_band_smooth = 0.0
        self.high_band_smooth = 0.0
        
        # Running normalization (sliding window max)
        norm_frames = int(config.norm_window_sec * config.sample_rate / config.block_size)
        self.energy_history = deque(maxlen=norm_frames)
        self.brightness_history = deque(maxlen=norm_frames)
        self.bass_history = deque(maxlen=norm_frames)
        self.mid_history = deque(maxlen=norm_frames)
        self.high_history = deque(maxlen=norm_frames)
        
        # Beat energy tracking (per-beat loudness)
        self.beat_energy_global = 0.0
        self.beat_energy_low = 0.0
        self.beat_energy_high = 0.0
        self.last_beat_frame = 0
        
        # Dynamic complexity (variance of loudness)
        self.loudness_history = deque(maxlen=60)  # 1 second at 60fps
        self.dynamic_complexity = 0.0
        
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
        self.rhythm_buffer = deque(maxlen=int(self.config.sample_rate * 12))
        self.last_rhythm_refresh = 0.0
        self.last_rhythm_beat_time = 0.0
        self.rhythm_bpm = 0.0
        self.rhythm_confidence = 0.0
        self.rhythm_min_buffer_sec = 8.0  # follow Essentia examples (multi-second context)
        self.rhythm_refresh_sec = 0.5
        self.rhythm_cached_beats: List[float] = []
    
    def _audio_callback(self, indata: np.ndarray, frames: int, 
                       time_info: dict, status: Any):
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
        if not SOUNDDEVICE_AVAILABLE or sd is None:
            raise RuntimeError("Cannot start audio stream: sounddevice not available")
        
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
                    dev_raw = sd.query_devices(device_idx)
                    dev_dict = dev_raw if isinstance(dev_raw, dict) else {}
                    dev_name = str(dev_dict.get('name', 'unknown'))
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

        # Accumulate audio for beat tracker (sliding window ~12s)
        try:
            self.rhythm_buffer.extend(mono.tolist())
        except Exception:
            pass
        
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
        
        # Calculate spectral rolloff (85% of energy cutoff point)
        rolloff_hz = 0.0
        if self.rolloff_algo:
            try:
                rolloff_hz = float(self.rolloff_algo(magnitude))
            except Exception:
                pass
        
        flux = calculate_spectral_flux(magnitude, self.prev_magnitude)

        # Use Essentia for flux if available
        if self.flux_algo:
            try:
                essentia_flux = float(self.flux_algo(magnitude, self.prev_magnitude))
                flux = essentia_flux
            except Exception:
                pass  # Fall back to numpy calculation

        # Smooth and gate flux to reduce visual jitter
        alpha_flux = 0.15
        self.flux_smooth = (1 - alpha_flux) * self.flux_smooth + alpha_flux * flux
        flux_for_send = self.flux_smooth if self.flux_smooth >= 0.02 else 0.0
        
        self.prev_magnitude = magnitude.copy()
        
        # --- EDM-specific features ---
        
        # Spectral flatness (noisiness: 0=tonal, 1=noise-like)
        flatness = 0.0
        if self.flatness_algo:
            try:
                flatness = float(self.flatness_algo(magnitude))
            except Exception:
                # Fallback: geometric mean / arithmetic mean
                geo_mean = np.exp(np.mean(np.log(magnitude + 1e-10)))
                arith_mean = np.mean(magnitude)
                flatness = geo_mean / (arith_mean + 1e-10) if arith_mean > 0 else 0.0
        
        # Energy with Essentia Loudness if available
        energy_raw = calculate_rms(mono)
        if self.loudness_algo:
            try:
                loudness = float(self.loudness_algo(mono))
                # Loudness is in LUFS, normalize to 0-1 range (assuming -60 to 0 LUFS)
                energy_raw = max(0.0, (loudness + 60) / 60.0)
            except Exception:
                pass
        
        # EMA smoothing for continuous features (as per user spec)
        alpha_energy = self.config.ema_energy
        alpha_brightness = self.config.ema_brightness
        alpha_bands = self.config.ema_bands
        
        self.energy_smooth = (1 - alpha_energy) * self.energy_smooth + alpha_energy * energy_raw
        self.brightness_smooth = (1 - alpha_brightness) * self.brightness_smooth + alpha_brightness * centroid_norm
        self.noisiness_smooth = (1 - alpha_brightness) * self.noisiness_smooth + alpha_brightness * flatness
        
        # Band indices for multi-band detection
        BASS_BAND_INDEX = 1  # 60-250 Hz
        MID_BAND_INDICES = [2, 3, 4]  # 250-500, 500-2000, 2000-4000 Hz
        HIGH_BAND_INDICES = [5, 6]  # 4000-6000, 6000-20000 Hz
        
        # Calculate bass/mid/high band energies
        bass_energy = self.smoothed_bands[BASS_BAND_INDEX] if len(self.smoothed_bands) > BASS_BAND_INDEX else 0.0
        mid_energy = sum([self.smoothed_bands[i] for i in MID_BAND_INDICES if i < len(self.smoothed_bands)]) / len(MID_BAND_INDICES)
        high_energy = sum([self.smoothed_bands[i] for i in HIGH_BAND_INDICES if i < len(self.smoothed_bands)]) / len(HIGH_BAND_INDICES)
        
        # EMA smoothing for band energies
        self.bass_band_smooth = (1 - alpha_bands) * self.bass_band_smooth + alpha_bands * bass_energy
        self.mid_band_smooth = (1 - alpha_bands) * self.mid_band_smooth + alpha_bands * mid_energy
        self.high_band_smooth = (1 - alpha_bands) * self.high_band_smooth + alpha_bands * high_energy
        
        # Running max normalization (sliding window)
        self.energy_history.append(energy_raw)
        self.brightness_history.append(centroid_norm)
        self.bass_history.append(bass_energy)
        self.mid_history.append(mid_energy)
        self.high_history.append(high_energy)
        
        # Normalize using running max
        energy_max = max(self.energy_history) if self.energy_history else 1.0
        brightness_max = max(self.brightness_history) if self.brightness_history else 1.0
        bass_max = max(self.bass_history) if self.bass_history else 1.0
        mid_max = max(self.mid_history) if self.mid_history else 1.0
        high_max = max(self.high_history) if self.high_history else 1.0
        
        # Clamp to [0, 1]
        energy_norm = np.clip(self.energy_smooth / (energy_max + 1e-9), 0, 1)
        brightness_norm = np.clip(self.brightness_smooth / (brightness_max + 1e-9), 0, 1)
        bass_norm = np.clip(self.bass_band_smooth / (bass_max + 1e-9), 0, 1)
        mid_norm = np.clip(self.mid_band_smooth / (mid_max + 1e-9), 0, 1)
        high_norm = np.clip(self.high_band_smooth / (high_max + 1e-9), 0, 1)
        
        # Dynamic complexity (variance of loudness over short window)
        self.loudness_history.append(energy_raw)
        if len(self.loudness_history) > 10:
            self.dynamic_complexity = float(np.var(list(self.loudness_history)))
        
        # Track energy for build-up/drop detection
        total_energy = sum(raw_bands)
        if self.config.enable_structure:
            if not hasattr(self, 'structure_energy_history'):
                self.structure_energy_history = deque(
                    maxlen=int(self.config.energy_window_sec * self.config.sample_rate / self.config.block_size)
                )
            self.structure_energy_history.append(total_energy)
        
        # --- Essentia rhythm (tutorial-aligned: run on multi-second buffer) ---
        
        is_onset = False
        bpm = self.rhythm_bpm
        pitch_hz = 0.0
        pitch_conf = 0.0
        bpm_confidence = self.rhythm_confidence
        frame_duration = len(mono) / self.config.sample_rate

        if self.rhythm_extractor and self.config.enable_bpm:
            now = time.monotonic()
            buffer_arr = np.fromiter(self.rhythm_buffer, dtype=np.float32)
            buffer_duration = len(buffer_arr) / self.config.sample_rate if len(buffer_arr) > 0 else 0.0

            if buffer_duration >= self.rhythm_min_buffer_sec and (now - self.last_rhythm_refresh) >= self.rhythm_refresh_sec:
                try:
                    bpm_out, beat_times, beat_conf, _, _ = self.rhythm_extractor(buffer_arr)
                    self.rhythm_bpm = float(bpm_out)
                    self.rhythm_confidence = float(beat_conf)
                    self.rhythm_cached_beats = list(beat_times)
                    self.last_rhythm_refresh = now
                except Exception as e:
                    logger.error(f"Rhythm extractor error: {e}")

            # Convert cached beat times (seconds from start of buffer) into absolute wall-clock
            if self.rhythm_cached_beats:
                recent_abs = [now - (buffer_duration - bt) for bt in self.rhythm_cached_beats if bt <= buffer_duration]
                if recent_abs:
                    latest = max(recent_abs)
                    if latest - self.last_rhythm_beat_time > frame_duration * 0.5:
                        is_onset = True
                        self.last_rhythm_beat_time = latest

            bpm = self.rhythm_bpm
            bpm_confidence = self.rhythm_confidence
        
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
        
        # BPM already derived from rhythm extractor; no interval fallback
        
        # Beat energy tracking (BeatsLoudness equivalent)
        # Capture energy at beat moments for global + low/high bands
        if is_onset:
            self.beat_energy_global = energy_raw
            self.beat_energy_low = bass_energy
            self.beat_energy_high = high_energy
            self.last_beat_frame = self.frames_processed
        else:
            # Decay beat energy between beats
            frames_since_beat = self.frames_processed - self.last_beat_frame
            if frames_since_beat > 0:
                # Decay over ~0.5 seconds
                decay_rate = 0.9
                self.beat_energy_global *= decay_rate
                self.beat_energy_low *= decay_rate
                self.beat_energy_high *= decay_rate
        
        # Build-up/drop detection
        if self.config.enable_structure and hasattr(self, 'structure_energy_history') and self.structure_energy_history:
            window_frames = len(self.structure_energy_history)
            is_buildup, is_drop, energy_trend = detect_buildup_drop(
                self.structure_energy_history,
                window_frames,
                self.config.buildup_threshold,
                self.config.drop_threshold
            )
        else:
            is_buildup = False
            is_drop = False
            energy_trend = 0.0
        
        # Multi-band beat pulses (bass, mid, high)
        # These decay over time and spike on band-specific onsets
        if not hasattr(self, 'bassHitPulse'):
            self.bassHitPulse = 0.0
            self.midHitPulse = 0.0
            self.highHitPulse = 0.0
            self.bass_avg = 0.0
            self.mid_avg = 0.0
            self.high_avg = 0.0
        
        # Simple adaptive thresholding for each band
        decay = 0.88
        alpha = 0.1
        sensitivity = 1.5
        overall_gate = max(self.smoothed_rms, 0.0)
        
        # Band indices for multi-band detection
        # Based on config.band_names: sub_bass, bass, low_mid, mid, high_mid, presence, air
        BASS_BAND_INDEX = 1  # 60-250 Hz
        MID_BAND_INDICES = [2, 3, 4]  # 250-500, 500-2000, 2000-4000 Hz
        HIGH_BAND_INDICES = [5, 6]  # 4000-6000, 6000-20000 Hz
        
        # Average bands for multi-band detection
        bass_energy = self.smoothed_bands[BASS_BAND_INDEX] if len(self.smoothed_bands) > BASS_BAND_INDEX else 0.0
        mid_energy = sum([self.smoothed_bands[i] for i in MID_BAND_INDICES if i < len(self.smoothed_bands)]) / len(MID_BAND_INDICES)
        high_energy = sum([self.smoothed_bands[i] for i in HIGH_BAND_INDICES if i < len(self.smoothed_bands)]) / len(HIGH_BAND_INDICES)
        
        # Update running averages
        self.bass_avg = self.bass_avg * (1 - alpha) + bass_energy * alpha
        self.mid_avg = self.mid_avg * (1 - alpha) + mid_energy * alpha
        self.high_avg = self.high_avg * (1 - alpha) + high_energy * alpha
        
        # Detect hits (guard against noise floor)
        bass_thresh = max(self.bass_avg * sensitivity, 0.12)
        mid_thresh = max(self.mid_avg * sensitivity, 0.10)
        high_thresh = max(self.high_avg * sensitivity, 0.08)

        bass_hit = overall_gate > 0.03 and bass_energy > bass_thresh
        mid_hit = overall_gate > 0.03 and mid_energy > mid_thresh
        high_hit = overall_gate > 0.03 and high_energy > high_thresh
        
        # Update pulses
        if bass_hit:
            self.bassHitPulse = 1.0
        else:
            self.bassHitPulse *= decay
            
        if mid_hit:
            self.midHitPulse = 1.0
        else:
            self.midHitPulse *= decay
            
        if high_hit:
            self.highHitPulse = 1.0
        else:
            self.highHitPulse *= decay
        
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
                # /audio/levels: [sub_bass, bass, low_mid, mid, high_mid, presence, air, overall_rms]
                # Matches Processing AudioAnalysisOSC format
                self.osc_callback('/audio/levels', self.smoothed_bands + [self.smoothed_rms])
                
                # /audio/spectrum: 32 bins for detailed visualization
                if spectrum_down:
                    self.osc_callback('/audio/spectrum', spectrum_down)
                
                # /audio/beat: [is_onset, spectral_flux]
                if self.config.enable_bpm:
                    self.osc_callback('/audio/beat', [
                        1 if is_onset else 0,
                        float(flux_for_send)
                    ])
                
                # /audio/bpm: [bpm, confidence]
                if self.config.enable_bpm:
                    self.osc_callback('/audio/bpm', [float(bpm), float(bpm_confidence)])
                
                # /audio/pitch: [frequency_hz, confidence]
                if self.config.enable_pitch:
                    self.osc_callback('/audio/pitch', [float(pitch_hz), float(pitch_conf)])
                
                # /audio/spectral: [centroid_norm, rolloff_hz, flux]
                # Additional spectral features
                self.osc_callback('/audio/spectral', [
                    float(centroid_norm), float(rolloff_hz), float(flux_for_send)
                ])
                
                # /audio/structure: [is_buildup, is_drop, energy_trend, brightness]
                if self.config.enable_structure:
                    buildup_int = 1 if is_buildup else 0
                    drop_int = 1 if is_drop else 0
                    self.osc_callback('/audio/structure', [
                        buildup_int, drop_int, float(energy_trend), float(centroid_norm)
                    ])
                
                # === EDM-specific features (10-15 globals, normalized 0-1) ===
                
                # Single-value features for easy mapping in VJ software
                self.osc_callback('/beat', [1.0 if is_onset else 0.0])  # Beat impulse
                self.osc_callback('/bpm', [float(bpm)])  # Current BPM
                self.osc_callback('/beat_conf', [float(bpm_confidence)])  # Beat confidence
                
                # Energy features with EMA smoothing
                self.osc_callback('/energy', [float(energy_raw)])  # Short-term energy/RMS
                self.osc_callback('/energy_smooth', [float(energy_norm)])  # EMA-smoothed, normalized
                
                # Beat energy (BeatsLoudness equivalent)
                self.osc_callback('/beat_energy', [float(self.beat_energy_global)])  # Global beat loudness
                self.osc_callback('/beat_energy_low', [float(self.beat_energy_low)])  # Low-band beat loudness
                self.osc_callback('/beat_energy_high', [float(self.beat_energy_high)])  # High-band beat loudness
                
                # Spectral features (normalized)
                self.osc_callback('/brightness', [float(brightness_norm)])  # Normalized centroid (0=dark, 1=bright)
                self.osc_callback('/noisiness', [float(self.noisiness_smooth)])  # Spectral flatness (0=tonal, 1=noise)
                
                # Band energies (EMA-smoothed and normalized)
                self.osc_callback('/bass_band', [float(bass_norm)])  # Low band energy
                self.osc_callback('/mid_band', [float(mid_norm)])  # Mid band energy
                self.osc_callback('/high_band', [float(high_norm)])  # High band energy
                
                # Optional: Dynamic complexity
                self.osc_callback('/dynamic_complexity', [float(self.dynamic_complexity)])  # Loudness variance
                
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
        if self.is_alive():
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
            
            # Measure Essentia rhythm (assumed available)
            essentia_time = 0.0
            is_onset = False
            bpm = self.analyzer.rhythm_bpm
            pitch_hz = 0.0
            pitch_conf = 0.0
            config = self.analyzer.config
            if self.analyzer.rhythm_extractor and config.enable_bpm:
                essentia_start = time.perf_counter()
                try:
                    buffer_arr = np.fromiter(self.analyzer.rhythm_buffer, dtype=np.float32)
                    buffer_duration = len(buffer_arr) / self.analyzer.config.sample_rate if len(buffer_arr) > 0 else 0.0
                    if buffer_duration >= self.analyzer.rhythm_min_buffer_sec:
                        bpm_out, beat_times, beat_conf, _, _ = self.analyzer.rhythm_extractor(buffer_arr)
                        self.analyzer.rhythm_bpm = float(bpm_out)
                        self.analyzer.rhythm_confidence = float(beat_conf)
                        self.analyzer.rhythm_cached_beats = list(beat_times)
                        bpm = self.analyzer.rhythm_bpm
                        if beat_times:
                            # Treat latest beat within the last frame as onset for timing benchmark
                            latest_rel = beat_times[-1]
                            if buffer_duration - latest_rel <= (config.block_size / config.sample_rate):
                                is_onset = True
                    essentia_time = (time.perf_counter() - essentia_start) * 1_000_000
                except Exception:
                    pass
                self.essentia_times.append(essentia_time)

            if self.analyzer.pitch_yin and config.enable_pitch:
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

            bpm_confidence = self.analyzer.rhythm_confidence if config.enable_bpm else 0.0
            
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
            
            fft_time_us=float(np.mean(self.fft_times)) if self.fft_times else 0.0,
            band_extraction_time_us=float(np.mean(self.band_times)) if self.band_times else 0.0,
            essentia_time_us=float(np.mean(self.essentia_times)) if self.essentia_times else 0.0,
            osc_send_time_us=float(np.mean(self.osc_times)) if self.osc_times else 0.0,
            total_processing_time_us=float(np.mean(self.frame_latencies) * 1000) if self.frame_latencies else 0.0,
            
            min_latency_ms=min(latencies_sorted) if latencies_sorted else 0,
            max_latency_ms=max(latencies_sorted) if latencies_sorted else 0,
            avg_latency_ms=float(np.mean(latencies_sorted)) if latencies_sorted else 0.0,
            p95_latency_ms=latencies_sorted[p95_idx] if p95_idx < len(latencies_sorted) else 0,
            p99_latency_ms=latencies_sorted[p99_idx] if p99_idx < len(latencies_sorted) else 0,
            
            queue_drops=self.queue_drops,
            max_queue_size=max(self.queue_sizes) if self.queue_sizes else 0,
        )
        
        logger.info(f"Benchmark complete: {results.avg_fps:.1f} fps, {results.avg_latency_ms:.2f}ms avg latency")
        
        return results


# =============================================================================
# CLI UTILITIES
# =============================================================================


def _build_config_from_args(args: argparse.Namespace) -> AudioConfig:
    log_level = getattr(logging, args.log_level.upper(), logging.INFO)
    return AudioConfig(
        sample_rate=args.sample_rate,
        block_size=args.block_size,
        fft_size=args.fft_size,
        channels=args.channels,
        osc_host=args.osc_host,
        osc_port=args.osc_port,
        enable_essentia=not args.disable_essentia,
        enable_pitch=not args.disable_pitch,
        enable_bpm=not args.disable_bpm,
        enable_structure=not args.disable_structure,
        enable_spectrum=not args.disable_spectrum,
        enable_logging=True,
        log_level=log_level,
    )


def _create_osc_callback(host: str, port: int) -> Callable[[str, List], None]:
    if not OSC_AVAILABLE:
        raise RuntimeError("python-osc not installed. Install with: pip install python-osc")
    if udp_client is None:
        raise RuntimeError("python-osc import failed")
    client = udp_client.SimpleUDPClient(host, port)

    def _send(addr: str, payload: List):
        client.send_message(addr, payload)

    return _send


def _log_callback(addr: str, payload: List):
    logger.info("%s %s", addr, payload)


def _list_devices(device_manager: DeviceManager) -> int:
    devices = device_manager.list_devices()
    if not devices:
        print("No input devices found or sounddevice unavailable.")
        return 1
    for idx, dev in enumerate(devices):
        name = dev.get('name', 'unknown')
        channels = dev.get('channels', 0)
        rate = dev.get('sample_rate', 0)
        print(f"[{idx}] {name} - {channels}ch @ {rate}Hz")
    return 0


def _run_live(args: argparse.Namespace) -> int:
    if not SOUNDDEVICE_AVAILABLE:
        logger.error("sounddevice is required for live mode. Install PortAudio + sounddevice.")
        return 1

    config = _build_config_from_args(args)
    device_manager = DeviceManager()
    device_manager.config.auto_select_blackhole = not args.no_blackhole
    if args.device_index is not None:
        device_manager.config.device_index = args.device_index

    osc_callback: Optional[Callable[[str, List], None]] = None
    if not args.log_only:
        try:
            osc_callback = _create_osc_callback(config.osc_host, config.osc_port)
        except Exception as exc:
            logger.error("OSC setup failed: %s", exc)
            return 1
    else:
        osc_callback = _log_callback

    analyzer = AudioAnalyzer(config, device_manager, osc_callback=osc_callback)
    analyzer.start()

    try:
        end_time = time.monotonic() + args.duration if args.duration else None
        while analyzer.is_alive():
            if end_time and time.monotonic() > end_time:
                break
            time.sleep(0.25)
    except KeyboardInterrupt:
        logger.info("Stopping (Ctrl+C pressed)...")
    
    if args.benchmark_secs and analyzer.running:
        tester = LatencyTester(analyzer)
        results = tester.run_benchmark(duration_sec=args.benchmark_secs)
        print(json.dumps(results.to_dict(), indent=2))

    analyzer.stop()

    return 0


def _generate_tone_block(freq: float, block_size: int, channels: int, sample_rate: int, frame_idx: int) -> np.ndarray:
    t = (np.arange(block_size, dtype=np.float32) + frame_idx * block_size) / float(sample_rate)
    mono = 0.5 * np.sin(2 * np.pi * freq * t)
    return np.repeat(mono[:, None], channels, axis=1)


def _run_dry_run(args: argparse.Namespace) -> int:
    config = _build_config_from_args(args)
    device_manager = DeviceManager()

    osc_callback: Optional[Callable[[str, List], None]] = None
    if not args.log_only:
        try:
            osc_callback = _create_osc_callback(config.osc_host, config.osc_port)
        except Exception as exc:
            logger.error("OSC setup failed: %s", exc)
            return 1
    else:
        osc_callback = _log_callback

    analyzer = AudioAnalyzer(config, device_manager, osc_callback=osc_callback)
    analyzer.running = True

    frame_interval = config.block_size / float(config.sample_rate)
    end_time = time.monotonic() + args.duration if args.duration else None
    frame_idx = 0

    try:
        while True:
            if end_time and time.monotonic() > end_time:
                break
            block = _generate_tone_block(args.frequency, config.block_size, config.channels, config.sample_rate, frame_idx)
            analyzer._process_frame(block)
            frame_idx += 1
            time.sleep(frame_interval)
    except KeyboardInterrupt:
        logger.info("Stopping dry-run (Ctrl+C pressed)...")
    finally:
        analyzer.running = False

    return 0


def _parse_args(argv: Optional[List[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Standalone audio analyzer CLI")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR"], help="Logging level")

    subparsers = parser.add_subparsers(dest="command", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--sample-rate", type=int, default=44100)
    common.add_argument("--block-size", type=int, default=512)
    common.add_argument("--fft-size", type=int, default=512)
    common.add_argument("--channels", type=int, default=2)
    common.add_argument("--osc-host", default="127.0.0.1")
    common.add_argument("--osc-port", type=int, default=9000)
    common.add_argument("--disable-essentia", action="store_true")
    common.add_argument("--disable-pitch", action="store_true")
    common.add_argument("--disable-bpm", action="store_true")
    common.add_argument("--disable-structure", action="store_true")
    common.add_argument("--disable-spectrum", action="store_true")
    common.add_argument("--log-only", action="store_true", help="Log features instead of sending OSC")

    run_parser = subparsers.add_parser("run", parents=[common], help="Run live analyzer with audio input")
    run_parser.add_argument("--duration", type=float, default=0.0, help="Stop after N seconds (0=run until Ctrl+C)")
    run_parser.add_argument("--device-index", type=int, default=None, help="sounddevice input index to use")
    run_parser.add_argument("--no-blackhole", action="store_true", help="Disable BlackHole auto-selection")
    run_parser.add_argument("--benchmark-secs", type=float, default=0.0, help="Optional latency benchmark duration")

    dry_parser = subparsers.add_parser("dry-run", parents=[common], help="Feed synthetic audio without a device")
    dry_parser.add_argument("--duration", type=float, default=10.0, help="Run for N seconds (0=until Ctrl+C)")
    dry_parser.add_argument("--frequency", type=float, default=220.0, help="Test tone frequency")

    subparsers.add_parser("list-devices", help="List available input devices")

    return parser.parse_args(argv)


def main(argv: Optional[List[str]] = None) -> int:
    args = _parse_args(argv)
    logging.basicConfig(level=getattr(logging, args.log_level.upper(), logging.INFO), format="%(asctime)s %(levelname)s %(message)s")

    if args.command == "list-devices":
        return _list_devices(DeviceManager())
    if args.command == "run":
        return _run_live(args)
    if args.command == "dry-run":
        return _run_dry_run(args)
    logger.error("Unknown command: %s", args.command)
    return 1


if __name__ == "__main__":
    sys.exit(main())
