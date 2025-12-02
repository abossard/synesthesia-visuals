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
    import aubio
    AUBIO_AVAILABLE = True
except ImportError as e:
    AUBIO_AVAILABLE = False
    logger.warning(f"Aubio not available - beat/tempo/pitch detection disabled: {e}")
    logger.info("Install aubio with: pip install aubio")

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
    
    # BPM estimation
    bpm_history_size: int = 16  # Number of beat intervals to track
    bpm_min: float = 60.0
    bpm_max: float = 180.0
    
    # Build-up/drop detection
    energy_window_sec: float = 2.0  # Window for trend analysis
    buildup_threshold: float = 0.3  # Energy increase rate
    drop_threshold: float = 0.5     # Energy jump after low period


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
        
        # Audio I/O state
        self.audio_queue = queue.Queue(maxsize=64)
        self.stream: Optional[sd.InputStream] = None
        self.last_audio_time = time.monotonic()
        
        # Analysis state
        self.hann_window = np.hanning(config.fft_size).astype(np.float32)
        self.freqs = np.fft.rfftfreq(config.fft_size, 1.0 / config.sample_rate)
        self.prev_magnitude = np.zeros(config.fft_size // 2 + 1, dtype=np.float32)
        
        # Smoothed features
        self.smoothed_bands = [0.0] * len(config.bands)
        self.smoothed_rms = 0.0
        
        # Beat/BPM tracking
        self.beat_times = deque(maxlen=config.bpm_history_size)
        self.last_beat_time = 0.0
        
        # Build-up/drop detection
        frames_per_window = int(config.energy_window_sec * config.sample_rate / config.block_size)
        self.energy_history = deque(maxlen=frames_per_window)
        
        # Aubio objects (if available)
        self.onset = None
        self.tempo = None
        self.pitch = None
        
        if AUBIO_AVAILABLE:
            try:
                self.onset = aubio.onset("default", config.fft_size, config.block_size, config.sample_rate)
                self.tempo = aubio.tempo("default", config.fft_size, config.block_size, config.sample_rate)
                self.pitch = aubio.pitch("yin", config.fft_size, config.block_size, config.sample_rate)
                self.pitch.set_unit("Hz")
                self.pitch.set_silence(-40)
                logger.info("Aubio initialized for beat/tempo/pitch detection")
            except Exception as e:
                logger.warning(f"Aubio initialization failed: {e}")
        else:
            logger.warning("Aubio not available - beat/tempo/pitch detection disabled")
        
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
        
        try:
            self.stream = sd.InputStream(
                samplerate=self.config.sample_rate,
                blocksize=self.config.block_size,
                channels=self.config.channels,
                dtype='float32',
                device=device_idx,
                callback=self._audio_callback,
            )
            self.stream.start()
            
            # Log device info
            if device_idx is not None:
                dev = sd.query_devices(device_idx)
                logger.info(f"Audio stream started: {dev['name']} @ {self.config.sample_rate}Hz")
            else:
                logger.info(f"Audio stream started: system default @ {self.config.sample_rate}Hz")
            
            self.error_count = 0
            
        except Exception as e:
            logger.error(f"Failed to start audio stream: {e}")
            self.error_count += 1
            raise
    
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
        
        # Smooth and compress bands
        for i, raw_val in enumerate(raw_bands):
            self.smoothed_bands[i] = smooth_value(
                self.smoothed_bands[i],
                compress_value(raw_val, self.config.compression_k),
                self.config.smoothing_factor
            )
        
        # Overall RMS
        rms = calculate_rms(mono)
        self.smoothed_rms = smooth_value(
            self.smoothed_rms,
            compress_value(rms * 10, self.config.compression_k),
            self.config.smoothing_factor
        )
        
        # Spectral features
        centroid = calculate_spectral_centroid(magnitude, self.freqs)
        centroid_norm = centroid / (self.config.sample_rate / 2.0)
        
        flux = calculate_spectral_flux(magnitude, self.prev_magnitude)
        self.prev_magnitude = magnitude.copy()
        
        # Track energy for build-up/drop detection
        total_energy = sum(raw_bands)
        self.energy_history.append(total_energy)
        
        # --- Aubio features (if available) ---
        
        is_onset = False
        bpm = 0.0
        tempo_conf = 0.0
        pitch_hz = 0.0
        pitch_conf = 0.0
        
        if self.onset and self.tempo and self.pitch:
            try:
                # Onset detection
                is_onset = bool(self.onset(mono))
                
                # Track beat times for custom BPM estimation
                if is_onset:
                    current_time = time.monotonic()
                    if self.last_beat_time > 0:
                        interval = current_time - self.last_beat_time
                        self.beat_times.append(interval)
                    self.last_beat_time = current_time
                
                # Aubio tempo
                tempo_result = self.tempo(mono)
                if tempo_result:
                    tempo_conf = float(tempo_result)
                bpm = float(self.tempo.get_bpm())
                
                # Pitch detection
                pitch_hz = float(self.pitch(mono)[0])
                pitch_conf = float(self.pitch.get_confidence())
                
                if pitch_conf < 0.6:
                    pitch_hz = 0.0
                    
            except Exception as e:
                logger.error(f"Aubio processing error: {e}")
        
        # Custom BPM estimation from beat intervals
        custom_bpm, bpm_confidence = estimate_bpm_from_intervals(
            list(self.beat_times),
            self.config.bpm_min,
            self.config.bpm_max
        )
        
        # Use custom BPM if available, otherwise use aubio BPM
        if custom_bpm > 0:
            bpm = custom_bpm
        
        # Build-up/drop detection
        window_frames = len(self.energy_history)
        is_buildup, is_drop, energy_trend = detect_buildup_drop(
            self.energy_history,
            window_frames,
            self.config.buildup_threshold,
            self.config.drop_threshold
        )
        
        # Downsample spectrum for OSC
        spectrum_down = downsample_spectrum(magnitude, self.config.spectrum_bins)
        
        # --- Store latest features for UI ---
        beat_int = 1 if is_onset else 0
        self.latest_features = {
            'beat': beat_int,
            'bpm': float(bpm),
            'bpm_confidence': float(bpm_confidence),
            'buildup': is_buildup,
            'drop': is_drop,
            'pitch_hz': float(pitch_hz),
            'pitch_conf': float(pitch_conf),
        }
        
        # --- Send OSC messages (always, when analyzer is active) ---
        
        if self.osc_callback:
            try:
                # Levels (per-band + overall RMS)
                self.osc_callback('/audio/levels', self.smoothed_bands + [self.smoothed_rms])
                
                # Spectrum
                self.osc_callback('/audio/spectrum', spectrum_down.tolist())
                
                # Beat
                self.osc_callback('/audio/beat', [beat_int, float(flux)])
                
                # BPM
                self.osc_callback('/audio/bpm', [float(bpm), float(bpm_confidence)])
                
                # Pitch
                self.osc_callback('/audio/pitch', [float(pitch_hz), float(pitch_conf)])
                
                # Structure (build-up/drop)
                buildup_int = 1 if is_buildup else 0
                drop_int = 1 if is_drop else 0
                self.osc_callback('/audio/structure', [
                    buildup_int, drop_int, float(energy_trend), float(centroid_norm)
                ])
                
            except Exception as e:
                logger.error(f"OSC send error: {e}")
        
        self.frames_processed += 1
    
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
    aubio_time_us: float = 0.0
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
    - Per-component timing (FFT, band extraction, aubio, OSC)
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
        self.aubio_times: List[float] = []
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
        self.aubio_times.clear()
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
            self.analyzer.energy_history.append(total_energy)
            
            # Measure Aubio (if available)
            aubio_time = 0.0
            is_onset = False
            bpm = 0.0
            tempo_conf = 0.0
            pitch_hz = 0.0
            pitch_conf = 0.0
            
            if self.analyzer.onset and self.analyzer.tempo and self.analyzer.pitch:
                aubio_start = time.perf_counter()
                try:
                    is_onset = bool(self.analyzer.onset(mono))
                    
                    if is_onset:
                        current_time = time.monotonic()
                        if self.analyzer.last_beat_time > 0:
                            interval = current_time - self.analyzer.last_beat_time
                            self.analyzer.beat_times.append(interval)
                        self.analyzer.last_beat_time = current_time
                    
                    tempo_result = self.analyzer.tempo(mono)
                    if tempo_result:
                        tempo_conf = float(tempo_result)
                    bpm = float(self.analyzer.tempo.get_bpm())
                    
                    pitch_hz = float(self.analyzer.pitch(mono)[0])
                    pitch_conf = float(self.analyzer.pitch.get_confidence())
                    
                    if pitch_conf < 0.6:
                        pitch_hz = 0.0
                        
                    aubio_time = (time.perf_counter() - aubio_start) * 1_000_000
                except Exception:
                    pass
                
                self.aubio_times.append(aubio_time)
            
            # BPM estimation
            custom_bpm, bpm_confidence = estimate_bpm_from_intervals(
                list(self.analyzer.beat_times),
                self.analyzer.config.bpm_min,
                self.analyzer.config.bpm_max
            )
            if custom_bpm > 0:
                bpm = custom_bpm
            
            # Build-up/drop detection
            window_frames = len(self.analyzer.energy_history)
            is_buildup, is_drop, energy_trend = detect_buildup_drop(
                self.analyzer.energy_history,
                window_frames,
                self.analyzer.config.buildup_threshold,
                self.analyzer.config.drop_threshold
            )
            
            spectrum_down = downsample_spectrum(magnitude, self.analyzer.config.spectrum_bins)
            
            # Store latest features
            beat_int = 1 if is_onset else 0
            self.analyzer.latest_features = {
                'beat': beat_int,
                'bpm': float(bpm),
                'bpm_confidence': float(bpm_confidence),
                'buildup': is_buildup,
                'drop': is_drop,
                'pitch_hz': float(pitch_hz),
                'pitch_conf': float(pitch_conf),
            }
            
            # Measure OSC send time
            osc_time = 0.0
            if self.analyzer.osc_callback:
                osc_start = time.perf_counter()
                try:
                    self.analyzer.osc_callback('/audio/levels', self.analyzer.smoothed_bands + [self.analyzer.smoothed_rms])
                    self.analyzer.osc_callback('/audio/spectrum', spectrum_down.tolist())
                    self.analyzer.osc_callback('/audio/beat', [beat_int, float(flux)])
                    self.analyzer.osc_callback('/audio/bpm', [float(bpm), float(bpm_confidence)])
                    self.analyzer.osc_callback('/audio/pitch', [float(pitch_hz), float(pitch_conf)])
                    
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
            aubio_time_us=np.mean(self.aubio_times) if self.aubio_times else 0,
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
