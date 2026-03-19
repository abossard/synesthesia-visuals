#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["pyaudio", "numpy", "blessed", "aubio", "github-copilot-sdk", "Pillow"]
# ///

"""
TermVJ - Terminal Audio-Reactive VJ Visualizer
High-performance aubio-powered visual synthesizer for the terminal.
"""

import sys
import time
import threading
import asyncio
import argparse
import math
import os
import json
from dataclasses import dataclass, field
from collections import deque
import numpy as np
import pyaudio
import aubio
from blessed import Terminal

from ai_viz import (
    AIVizManager, DebugPanel, SYSTEM_PROMPT,
    extract_code, load_render_fn, take_screenshot,
    HAS_COPILOT, HAS_PIL,
)
from shader_versions import ShaderVersion, ShaderVersionStore

# Constants
RATE = 44100
WIN_S = 1024
HOP_S = 512
CHANNELS = 1
FORMAT = pyaudio.paFloat32
TARGET_FPS = 30
SPECTRUM_BINS = 256
MEL_BANDS = 40
MFCC_COEFFS = 13

# Visualization mode names
MODE_NAMES = [
    "DIAG", "PLASMA", "FIRE", "SPEC", "PARTS", 
    "TUNNEL", "WAVES", "VORONOI", "SCOPE", "KALEID", "FRACTAL"
]

# State persistence path
STATE_FILE = os.path.expanduser("~/.termvj_state.json")
VERSIONS_FILE = os.path.expanduser("~/.termvj_versions.json")


def load_persisted_state() -> dict:
    """Load last mode/palette from disk."""
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_persisted_state(mode: int, palette_idx: int) -> None:
    """Persist current mode and palette to disk."""
    try:
        with open(STATE_FILE, "w") as f:
            json.dump({"mode": mode, "palette_idx": palette_idx}, f)
    except OSError:
        pass


class FeatureAGC:
    """Dual-EMA automatic gain control with output smoothing."""
    
    def __init__(self, n, attack=0.08, release=0.01, floor=1e-4, smooth=0.4):
        self.attack = attack
        self.release = release
        self.floor = floor
        self.smooth = smooth  # output smoothing factor (0=no smooth, 1=frozen)
        self.peak_ema = np.full(n, floor, dtype=np.float64)
        self.avg_ema = np.full(n, floor, dtype=np.float64)
        self.prev_out = np.zeros(n, dtype=np.float64)
    
    def normalize(self, values):
        v = np.abs(np.asarray(values, dtype=np.float64))
        # Update peak tracker (fast attack, slow release)
        rising = v > self.peak_ema
        alpha = np.where(rising, self.attack, self.release * 0.5)
        self.peak_ema = alpha * v + (1 - alpha) * self.peak_ema
        self.peak_ema = np.maximum(self.peak_ema, self.floor)
        # Update average tracker (always slow)
        self.avg_ema = self.release * v + (1 - self.release) * self.avg_ema
        self.avg_ema = np.maximum(self.avg_ema, self.floor)
        # Normalize — cap amplification at 2× average to avoid noise blowup
        scale = np.minimum(self.peak_ema, self.avg_ema * 2)
        raw = np.clip(v / np.maximum(scale, self.floor), 0, 1)
        # Temporal smoothing to prevent frame-to-frame jitter
        smoothed = self.smooth * self.prev_out + (1 - self.smooth) * raw
        self.prev_out = smoothed
        return smoothed


@dataclass
class AudioFeatures:
    """Complete audio feature set with auto-normalization."""
    spectrum: np.ndarray      # 256 log-FFT bins, normalized 0-1
    mel_bands: np.ndarray     # 40 mel bands, normalized 0-1
    mfcc: np.ndarray          # 13 MFCC coefficients
    waveform: np.ndarray      # raw samples
    # Spectral descriptors (all 0-1 normalized)
    centroid: float = 0.0     # brightness
    spread: float = 0.0       # complexity
    rolloff: float = 0.0
    flatness: float = 0.0     # tonality (0) vs noise (1)
    flux: float = 0.0         # spectral change rate
    slope: float = 0.0        # tilt
    kurtosis: float = 0.0     # peakedness
    # Pitch
    pitch_hz: float = 0.0
    pitch_midi: float = 0.0
    pitch_confidence: float = 0.0
    # Rhythm
    beat: bool = False
    onset: bool = False
    onset_strength: float = 0.0
    bpm: float = 0.0
    # Levels
    rms: float = 0.0          # normalized loudness
    is_quiet: bool = True


def cosine_palette(t, a, b, c, d):
    """Inigo Quilez cosine palette: a + b * cos(2π(c*t + d))"""
    t = np.asarray(t, dtype=np.float64)
    if t.ndim == 0:
        t = t.reshape(1)
    return np.clip(a + b * np.cos(2 * np.pi * (c * t[:, np.newaxis] + d)), 0, 1)


# Color palettes (Inigo Quilez style)
PALETTES = {
    "jungle": {
        "a": np.array([0.2, 0.3, 0.1]),
        "b": np.array([0.3, 0.4, 0.2]),
        "c": np.array([1.0, 1.0, 0.5]),
        "d": np.array([0.0, 0.1, 0.2])
    },
    "love": {
        "a": np.array([0.5, 0.2, 0.3]),
        "b": np.array([0.4, 0.3, 0.4]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.0, 0.33, 0.67])
    },
    "neon_party": {
        "a": np.array([0.5, 0.5, 0.5]),
        "b": np.array([0.5, 0.5, 0.5]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.0, 0.33, 0.67])
    },
    "disco": {
        "a": np.array([0.5, 0.5, 0.5]),
        "b": np.array([0.5, 0.5, 0.5]),
        "c": np.array([2.0, 1.0, 0.0]),
        "d": np.array([0.5, 0.2, 0.25])
    },
    "relax": {
        "a": np.array([0.5, 0.5, 0.6]),
        "b": np.array([0.3, 0.4, 0.3]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.6, 0.7, 0.5])
    },
    "ultra_strobe": {
        "a": np.array([0.5, 0.5, 0.5]),
        "b": np.array([0.5, 0.5, 0.5]),
        "c": np.array([10.0, 10.0, 10.0]),
        "d": np.array([0.0, 0.0, 0.0])
    },
    "bw": {
        "a": np.array([0.5, 0.5, 0.5]),
        "b": np.array([0.5, 0.5, 0.5]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.0, 0.0, 0.0])
    },
    "fire": {
        "a": np.array([0.5, 0.3, 0.0]),
        "b": np.array([0.5, 0.5, 0.3]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.0, 0.1, 0.2])
    },
    "ice": {
        "a": np.array([0.0, 0.2, 0.5]),
        "b": np.array([0.3, 0.5, 0.5]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.2, 0.5, 0.6])
    },
    "vapor": {
        "a": np.array([0.3, 0.2, 0.5]),
        "b": np.array([0.5, 0.4, 0.5]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.8, 0.0, 0.5])
    },
    "sunset": {
        "a": np.array([0.5, 0.3, 0.4]),
        "b": np.array([0.5, 0.4, 0.3]),
        "c": np.array([1.0, 1.0, 1.0]),
        "d": np.array([0.0, 0.15, 0.7])
    },
    "aurora": {
        "a": np.array([0.2, 0.4, 0.3]),
        "b": np.array([0.4, 0.5, 0.5]),
        "c": np.array([1.0, 1.0, 1.5]),
        "d": np.array([0.3, 0.5, 0.7])
    }
}

PALETTE_NAMES = list(PALETTES.keys())


def make_palette_lut(palette_name, size=256):
    """Generate 256-entry RGB LUT from palette."""
    p = PALETTES[palette_name]
    t = np.linspace(0, 1, size)
    rgb = cosine_palette(t, p["a"], p["b"], p["c"], p["d"])
    return (rgb * 255).astype(np.uint8)


class AudioEngine:
    """Aubio-powered audio analysis engine."""
    
    def __init__(self, device_index=None):
        self.device_index = device_index
        self.running = False
        self.lock = threading.Lock()
        
        # Current features
        self.features = AudioFeatures(
            spectrum=np.zeros(SPECTRUM_BINS),
            mel_bands=np.zeros(MEL_BANDS),
            mfcc=np.zeros(MFCC_COEFFS),
            waveform=np.zeros(HOP_S)
        )
        
        # AGC normalizers
        self.agc_spectrum = FeatureAGC(SPECTRUM_BINS, smooth=0.5)
        self.agc_mel = FeatureAGC(MEL_BANDS, smooth=0.5)
        self.agc_specdesc = FeatureAGC(7, smooth=0.6)
        self.agc_scalar = FeatureAGC(2, smooth=0.4)
        
        # Aubio objects
        self.pvoc = aubio.pvoc(WIN_S, HOP_S)
        self.filterbank = aubio.filterbank(MEL_BANDS, WIN_S)
        self.filterbank.set_mel_coeffs_slaney(RATE)
        self.mfcc_o = aubio.mfcc(WIN_S, MEL_BANDS, MFCC_COEFFS, RATE)
        
        # Spectral descriptors
        self.sd_centroid = aubio.specdesc("centroid", WIN_S)
        self.sd_spread = aubio.specdesc("spread", WIN_S)
        self.sd_rolloff = aubio.specdesc("rolloff", WIN_S)
        self.sd_flux = aubio.specdesc("specflux", WIN_S)
        self.sd_slope = aubio.specdesc("slope", WIN_S)
        self.sd_kurtosis = aubio.specdesc("kurtosis", WIN_S)
        
        # Temporal features
        self.tempo_o = aubio.tempo("default", WIN_S, HOP_S, RATE)
        self.onset_o = aubio.onset("hfc", WIN_S, HOP_S, RATE)
        self.pitch_o = aubio.pitch("yinfft", WIN_S, HOP_S, RATE)
        self.pitch_o.set_unit("Hz")
        self.pitch_o.set_tolerance(0.8)
        
        self.p = None
        self.stream = None
        
    def start(self):
        """Start audio capture thread."""
        self.running = True
        self.p = pyaudio.PyAudio()
        dev_info = self.p.get_device_info_by_index(self.device_index)
        self._dev_channels = max(1, int(dev_info.get('maxInputChannels', 1)))
        # Some devices report >1 channels but only work with mono at our rate
        # Try native channel count first, fall back to mono
        for ch in [self._dev_channels, 1]:
            try:
                self.stream = self.p.open(
                    format=FORMAT,
                    channels=ch,
                    rate=RATE,
                    input=True,
                    input_device_index=self.device_index,
                    frames_per_buffer=HOP_S,
                    stream_callback=self._audio_callback
                )
                self._dev_channels = ch
                self.stream.start_stream()
                return
            except OSError:
                continue
        raise RuntimeError(f"Cannot open device {self.device_index} for audio input")
        
    def stop(self):
        """Stop audio capture."""
        self.running = False
        if self.stream:
            self.stream.stop_stream()
            self.stream.close()
        if self.p:
            self.p.terminate()
            
    def _audio_callback(self, in_data, frame_count, time_info, status):
        """Process audio frames."""
        samples = np.frombuffer(in_data, dtype=np.float32)
        # Downmix to mono if multi-channel
        if self._dev_channels > 1:
            samples = samples.reshape(-1, self._dev_channels).mean(axis=1)
        
        # Phase vocoder (STFT)
        cvec = self.pvoc(samples)
        
        # Mel bands
        mel_bands = self.filterbank(cvec)
        
        # MFCC
        mfcc_out = self.mfcc_o(cvec)
        
        # Spectral descriptors (take cvec)
        centroid = float(self.sd_centroid(cvec)[0])
        spread = float(self.sd_spread(cvec)[0])
        rolloff = float(self.sd_rolloff(cvec)[0])
        flux = float(self.sd_flux(cvec)[0])
        slope = float(self.sd_slope(cvec)[0])
        kurtosis = float(self.sd_kurtosis(cvec)[0])
        # Spectral flatness computed manually (geomean/mean of magnitudes)
        mags = np.array(cvec.norm[1:], dtype=np.float64)
        mags_safe = np.maximum(mags, 1e-10)
        geo = np.exp(np.mean(np.log(mags_safe)))
        arith = np.mean(mags_safe)
        flatness = float(geo / max(arith, 1e-10))
        
        # Temporal features (take raw samples fvec)
        beat = bool(self.tempo_o(samples)[0])
        bpm = float(self.tempo_o.get_bpm())
        onset = bool(self.onset_o(samples)[0])
        onset_strength = float(self.onset_o.get_descriptor())
        pitch_hz = float(self.pitch_o(samples)[0])
        pitch_conf = float(self.pitch_o.get_confidence())
        
        # Build log-spectrum for visualization
        fft_mag = np.abs(cvec.norm)
        log_bins = np.logspace(np.log10(1), np.log10(WIN_S//2), SPECTRUM_BINS, dtype=int)
        spectrum_raw = np.array([fft_mag[max(0, i-2):min(len(fft_mag), i+3)].mean() 
                                 for i in log_bins])
        
        # RMS
        rms_raw = np.sqrt(np.mean(samples**2))
        
        # Normalize features
        spectrum_norm = self.agc_spectrum.normalize(spectrum_raw)
        mel_norm = self.agc_mel.normalize(mel_bands)
        specdesc_raw = np.array([centroid, spread, rolloff, flatness, flux, slope, kurtosis])
        specdesc_norm = self.agc_specdesc.normalize(specdesc_raw)
        scalar_norm = self.agc_scalar.normalize([rms_raw, onset_strength])
        
        # Pitch to MIDI
        pitch_midi = 69 + 12 * np.log2(max(pitch_hz, 1) / 440.0) if pitch_hz > 0 else 0
        
        # Update shared state
        with self.lock:
            self.features = AudioFeatures(
                spectrum=spectrum_norm,
                mel_bands=mel_norm,
                mfcc=mfcc_out,
                waveform=samples.copy(),
                centroid=specdesc_norm[0],
                spread=specdesc_norm[1],
                rolloff=specdesc_norm[2],
                flatness=specdesc_norm[3],
                flux=specdesc_norm[4],
                slope=specdesc_norm[5],
                kurtosis=specdesc_norm[6],
                pitch_hz=pitch_hz,
                pitch_midi=pitch_midi,
                pitch_confidence=pitch_conf,
                beat=beat,
                onset=onset,
                onset_strength=scalar_norm[1],
                bpm=bpm,
                rms=scalar_norm[0],
                is_quiet=rms_raw < 0.001
            )
        
        return (None, pyaudio.paContinue)
    
    def get_features(self):
        """Thread-safe feature access."""
        with self.lock:
            return self.features


def hz_to_note(hz):
    """Convert Hz to note name."""
    if hz < 1:
        return "---"
    midi = 69 + 12 * np.log2(hz / 440.0)
    note_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    octave = int(midi // 12) - 1
    note = note_names[int(midi % 12)]
    return f"{note}{octave}"


# ============================================================================
# VISUALIZATION MODES
# ============================================================================

def render_diagnostics(fb, audio, frame, lut, state):
    """Mode 0: Show all aubio features as labeled bars with text overlays.
    
    Labels are stored in state['overlays'] and rendered after halfblock output.
    """
    h, w, _ = fb.shape
    fb.fill(0)
    state['overlays'] = []  # list of (term_row, term_col, text, fg_rgb)
    
    def add_label(py, px, text, fg=(200, 200, 200)):
        """Add text overlay at pixel y (converted to terminal row)."""
        term_row = py // 2
        state['overlays'].append((term_row, px, text, fg))
    
    # ── Section 1: Mel Bands (top) ──
    mel_h = max(h // 4, 20)
    bar_w = max(2, (w - 2) // MEL_BANDS)
    add_label(0, 1, "MEL BANDS (40)", (150, 255, 150))
    
    for i in range(min(MEL_BANDS, (w - 2) // bar_w)):
        val = min(audio.mel_bands[i], 1.0)
        bar_h = max(0, int(val * (mel_h - 4)))
        x0 = 1 + i * bar_w
        x1 = min(x0 + bar_w - 1, w - 1)
        ci = int(np.clip(val * 255, 0, 255))
        color = lut[ci]
        if bar_h > 0:
            y_start = max(2, mel_h - bar_h)
            fb[y_start:mel_h, x0:x1] = color
    
    # ── Section 2: Spectral Descriptors ──
    y = mel_h + 4
    add_label(y - 2, 1, "SPECTRAL DESCRIPTORS", (150, 200, 255))
    
    desc_items = [
        ("centroid ", audio.centroid, (255, 200, 100)),
        ("spread   ", audio.spread, (100, 255, 200)),
        ("rolloff  ", audio.rolloff, (200, 100, 255)),
        ("flatness ", audio.flatness, (255, 100, 200)),
        ("flux     ", audio.flux, (100, 200, 255)),
        ("slope    ", audio.slope, (200, 255, 100)),
        ("kurtosis ", audio.kurtosis, (255, 150, 150)),
    ]
    
    label_w = 12
    bar_max = max(1, w - label_w - 12)
    for name, val, color_rgb in desc_items:
        if y + 3 >= h - 24:
            break
        val = min(max(val, 0), 1)
        bar_len = int(val * bar_max)
        ci = int(np.clip(val * 255, 0, 255))
        bar_color = lut[ci]
        if bar_len > 0:
            fb[y:y + 2, label_w:label_w + bar_len] = bar_color
        add_label(y, 1, name, color_rgb)
        add_label(y, label_w + bar_max + 1, f"{val:.2f}", (180, 180, 180))
        y += 4
    
    # ── Section 3: Rhythm & Pitch ──
    y += 2
    add_label(y, 1, "RHYTHM & PITCH", (255, 255, 150))
    y += 3
    
    beat_str = "BEAT: \u25cf" if audio.beat else "BEAT: \u25cb"
    onset_str = "ONSET: \u25cf" if audio.onset else "ONSET: \u25cb"
    bpm_str = f"BPM: {audio.bpm:.0f}" if audio.bpm > 0 else "BPM: ---"
    add_label(y, 1, bpm_str, (255, 255, 100))
    add_label(y, 16, beat_str, (255, 100, 100) if audio.beat else (100, 100, 100))
    add_label(y, 28, onset_str, (100, 255, 100) if audio.onset else (100, 100, 100))
    
    # Onset strength bar
    os_len = int(audio.onset_strength * min(bar_max, 30))
    if os_len > 0:
        fb[y:y + 2, 45:45 + os_len] = lut[int(np.clip(audio.onset_strength * 255, 0, 255))]
    add_label(y, 42, "os:", (180, 180, 180))
    y += 4
    
    # Pitch
    if audio.pitch_hz > 20 and audio.pitch_confidence > 0.3:
        note = hz_to_note(audio.pitch_hz)
        add_label(y, 1, f"Pitch: {audio.pitch_hz:.0f}Hz ({note}) conf:{audio.pitch_confidence:.2f}",
                  (200, 200, 255))
    else:
        add_label(y, 1, "Pitch: ---", (100, 100, 100))
    y += 4
    
    # ── Section 4: MFCC ──
    add_label(y, 1, "MFCC (13 coefficients)", (200, 150, 255))
    y += 3
    mfcc_w = max(2, (w - 4) // MFCC_COEFFS)
    for i in range(MFCC_COEFFS):
        val = np.clip(abs(audio.mfcc[i]) * 0.1, 0, 1) if i < len(audio.mfcc) else 0
        bar_h = max(0, int(val * 8))
        x0 = 2 + i * mfcc_w
        x1 = min(x0 + mfcc_w - 1, w - 1)
        ci = int(np.clip(val * 255, 0, 255))
        if bar_h > 0 and y + 8 < h:
            fb[y + 8 - bar_h:y + 8, x0:x1] = lut[ci]
    y += 12
    
    # ── Section 5: Waveform ──
    if y + 24 < h and len(audio.waveform) > 0:
        add_label(y, 1, "WAVEFORM", (150, 200, 150))
        y += 2
        wave_h = min(20, h - y - 6)
        if wave_h > 4:
            wave_mid = y + wave_h // 2
            wave_w = min(len(audio.waveform), w - 4)
            indices = np.linspace(0, len(audio.waveform) - 1, wave_w).astype(int)
            for i, idx in enumerate(indices):
                s = audio.waveform[idx]
                py = int(wave_mid + s * wave_h * 0.45)
                py = max(y, min(py, min(y + wave_h - 1, h - 1)))
                fb[py, 2 + i] = (0, 200, 100)
                lo = min(py, wave_mid)
                hi = max(py, wave_mid)
                for fill_y in range(lo, hi + 1):
                    if y <= fill_y < min(y + wave_h, h):
                        fb[fill_y, 2 + i] = (0, 180, 80)
            y += wave_h + 2
    
    # ── Section 6: RMS ──
    if y + 3 < h:
        rms_len = int(audio.rms * min(bar_max, 40))
        quiet_str = " QUIET" if audio.is_quiet else ""
        add_label(y, 1, f"RMS:{quiet_str}", (200, 200, 200))
        if rms_len > 0:
            ci = int(np.clip(audio.rms * 255, 0, 255))
            fb[y:y + 2, 12:12 + rms_len] = lut[ci]
    
    return fb


def render_plasma(fb, audio, frame, lut, state):
    """Mode 1: Classic demoscene plasma with irrational frequencies."""
    h, w, _ = fb.shape
    
    # Initialize state
    if "phase" not in state:
        state["phase"] = 0.0
        state["centers"] = np.random.rand(6, 2) * 2 - 1
        state["drift_vel"] = np.random.randn(6, 2) * 0.001
    
    # Beat triggers phase jump
    if audio.beat:
        state["phase"] += 0.3
    
    state["phase"] += 0.01 + audio.rms * 0.05
    state["centers"] += state["drift_vel"]
    state["centers"] = np.clip(state["centers"], -1.5, 1.5)
    
    # Grid coordinates
    y_coords = np.linspace(-1, 1, h)
    x_coords = np.linspace(-1, 1, w)
    xx, yy = np.meshgrid(x_coords, y_coords)
    
    # Irrational frequency ratios
    freqs = np.array([1.0, 1.618, 3.14159, 2.71828, 1.41421, 2.236])
    bass_mod = 1.0 + audio.mel_bands[:6].mean() * 2
    
    plasma = np.zeros((h, w))
    for i, (cx, cy) in enumerate(state["centers"]):
        dx = xx - cx
        dy = yy - cy
        dist = np.sqrt(dx*dx + dy*dy)
        plasma += np.sin(dist * freqs[i] * bass_mod + state["phase"] + i)
    
    plasma = (plasma - plasma.min()) / (plasma.max() - plasma.min() + 1e-6)
    plasma = (plasma + audio.centroid * 0.5) % 1.0
    
    indices = (plasma * 255).astype(int)
    fb[:] = lut[indices]
    
    return fb


def render_fire(fb, audio, frame, lut, state):
    """Mode 2: Cellular automata fire with mel-band injection."""
    h, w, _ = fb.shape
    
    if "heat" not in state:
        state["heat"] = np.zeros((h, w), dtype=np.float32)
    
    heat = state["heat"]
    
    # Inject heat at bottom from mel bands
    for i in range(min(MEL_BANDS, w)):
        x = int(i * w / MEL_BANDS)
        heat[-1, x] = audio.mel_bands[i]
    
    # Propagate and cool
    cooling = 0.05 + audio.flux * 0.05
    heat[:-1, :] = heat[1:, :] * (1 - cooling)
    
    # Wind/turbulence
    if audio.flux > 0.5:
        shift = np.random.randint(-2, 3)
        heat[:] = np.roll(heat, shift, axis=1)
    
    # Smooth
    heat[1:-1, 1:-1] = (heat[1:-1, 1:-1] * 2 + 
                        heat[:-2, 1:-1] + heat[2:, 1:-1] +
                        heat[1:-1, :-2] + heat[1:-1, 2:]) / 6
    
    state["heat"] = heat
    
    indices = (np.clip(heat, 0, 1) * 255).astype(int)
    fb[:] = lut[indices]
    
    return fb


def render_spectrum(fb, audio, frame, lut, state):
    """Mode 3: Mel-band spectrum analyzer with smooth bars and peak hold."""
    h, w, _ = fb.shape
    fb.fill(0)
    
    if "smooth_vals" not in state:
        state["smooth_vals"] = np.zeros(MEL_BANDS)
        state["peaks"] = np.zeros(MEL_BANDS)
        state["peak_vel"] = np.zeros(MEL_BANDS)
    
    # Asymmetric smoothing: fast attack, slow release
    for i in range(MEL_BANDS):
        target = audio.mel_bands[i]
        current = state["smooth_vals"][i]
        if target > current:
            state["smooth_vals"][i] = current + (target - current) * 0.6  # fast rise
        else:
            state["smooth_vals"][i] = current + (target - current) * 0.08  # slow fall
    
    # Peak hold with gravity
    for i in range(MEL_BANDS):
        val = state["smooth_vals"][i]
        if val > state["peaks"][i]:
            state["peaks"][i] = val
            state["peak_vel"][i] = 0.0
        else:
            state["peak_vel"][i] += 0.002  # gravity
            state["peaks"][i] = max(0, state["peaks"][i] - state["peak_vel"][i])
    
    # Calculate bar width with 1px gap between bars
    total_bars = min(MEL_BANDS, w)
    bar_w = max(2, w // total_bars)
    gap = 1 if bar_w > 2 else 0
    
    for i in range(min(total_bars, w // bar_w)):
        val = state["smooth_vals"][i]
        bar_h = int(val * (h - 2))
        peak_h = int(state["peaks"][i] * (h - 2))
        
        x0 = i * bar_w
        x1 = min(x0 + bar_w - gap, w)
        if x1 <= x0:
            continue
        
        # Draw bar with gradient
        if bar_h > 0:
            for y in range(max(0, h - bar_h), h):
                t = 1.0 - (y / h)
                ci = int(np.clip(t * 255, 0, 255))
                fb[y, x0:x1] = lut[ci]
        
        # Peak dot (2px tall for visibility)
        peak_y = h - peak_h
        if 1 <= peak_y < h - 1 and peak_h > bar_h + 2:
            fb[peak_y, x0:x1] = (255, 255, 255)
            fb[peak_y - 1, x0:x1] = (180, 180, 180)
    
    return fb


def render_particles(fb, audio, frame, lut, state):
    """Mode 4: Beat-triggered particle system."""
    h, w, _ = fb.shape
    
    if "particles" not in state:
        state["particles"] = []
    
    # Decay background
    fb[:] = (fb * 0.88).astype(np.uint8)
    
    # Spawn particles on onset/beat
    if audio.onset:
        n = int(audio.onset_strength * 50) + 10
        for _ in range(n):
            state["particles"].append({
                "x": w / 2,
                "y": h / 2,
                "vx": np.random.randn() * 5,
                "vy": np.random.randn() * 5,
                "life": 1.0,
                "color_t": audio.centroid
            })
    
    if audio.beat:
        for _ in range(30):
            angle = np.random.rand() * 2 * np.pi
            speed = 5 + np.random.rand() * 5
            state["particles"].append({
                "x": w / 2,
                "y": h / 2,
                "vx": np.cos(angle) * speed,
                "vy": np.sin(angle) * speed,
                "life": 1.0,
                "color_t": audio.centroid
            })
    
    # Update and draw
    gravity = 0.1
    turbulence = audio.flux * 2
    
    alive = []
    for p in state["particles"]:
        p["vy"] += gravity
        p["vx"] += (np.random.rand() - 0.5) * turbulence
        p["vy"] += (np.random.rand() - 0.5) * turbulence
        p["x"] += p["vx"]
        p["y"] += p["vy"]
        p["life"] *= 0.98
        
        if p["life"] > 0.01 and 0 <= p["x"] < w and 0 <= p["y"] < h:
            x, y = int(p["x"]), int(p["y"])
            color = lut[int(p["color_t"] * 255)]
            brightness = int(p["life"] * 255)
            fb[y, x] = (color * brightness // 255).astype(np.uint8)
            alive.append(p)
    
    state["particles"] = alive
    return fb


def render_tunnel(fb, audio, frame, lut, state):
    """Mode 5: Perspective tunnel with BPM-synced zoom."""
    h, w, _ = fb.shape
    
    if "polar" not in state:
        # Pre-compute polar coordinates
        y_coords = np.arange(h) - h / 2
        x_coords = np.arange(w) - w / 2
        xx, yy = np.meshgrid(x_coords, y_coords)
        angle = np.arctan2(yy, xx)
        dist = np.sqrt(xx*xx + yy*yy) + 1
        state["polar"] = (angle, dist)
        state["zoom"] = 0.0
    
    angle, dist = state["polar"]
    
    # BPM-synced zoom
    zoom_speed = 0.02 * (audio.bpm / 120.0) if audio.bpm > 0 else 0.02
    if audio.beat:
        zoom_speed *= 2
    state["zoom"] += zoom_speed
    
    # Tunnel pattern
    u = angle / np.pi  # -1 to 1
    v = state["zoom"] / dist
    
    # Distortion from spread
    v += np.sin(angle * 4 + state["zoom"]) * audio.spread * 0.1
    
    # Color from centroid
    pattern = (u * 5 + v * 10) % 1.0
    pattern = (pattern + audio.centroid) % 1.0
    
    indices = (pattern * 255).astype(int)
    fb[:] = lut[indices]
    
    return fb


def render_wave_interference(fb, audio, frame, lut, state):
    """Mode 6: Expanding ripples with interference."""
    h, w, _ = fb.shape
    
    if "waves" not in state:
        state["waves"] = []
    
    # Spawn waves
    if audio.beat:
        state["waves"].append({
            "x": np.random.rand() * w,
            "y": np.random.rand() * h,
            "age": 0,
            "amplitude": 1.0,
            "width": 1.0 + audio.flatness * 3
        })
    
    if audio.onset:
        state["waves"].append({
            "x": np.random.rand() * w,
            "y": np.random.rand() * h,
            "age": 0,
            "amplitude": 0.5,
            "width": 0.5 + audio.flatness * 2
        })
    
    # Grid
    y_coords = np.arange(h)[:, np.newaxis]
    x_coords = np.arange(w)[np.newaxis, :]
    
    # Accumulate waves
    field = np.zeros((h, w))
    alive = []
    
    for wave in state["waves"]:
        wave["age"] += 1
        decay = np.exp(-wave["age"] / 30.0)
        
        if decay > 0.01:
            dx = x_coords - wave["x"]
            dy = y_coords - wave["y"]
            dist = np.sqrt(dx*dx + dy*dy)
            ripple = np.sin(dist / wave["width"] - wave["age"] * 0.5)
            field += ripple * wave["amplitude"] * decay
            alive.append(wave)
    
    state["waves"] = alive
    
    # Normalize and colorize
    if field.max() > field.min():
        field = (field - field.min()) / (field.max() - field.min())
    field = (field + audio.centroid) % 1.0
    
    indices = (field * 255).astype(int)
    fb[:] = lut[indices]
    
    return fb


def render_voronoi(fb, audio, frame, lut, state):
    """Mode 7: Stained glass Voronoi cells."""
    h, w, _ = fb.shape
    
    if "cells" not in state:
        n_cells = 12
        state["cells"] = np.random.rand(n_cells, 2)
        state["cell_vel"] = np.random.randn(n_cells, 2) * 0.002
        state["cell_colors"] = np.random.rand(n_cells)
    
    # Update cells
    state["cells"] += state["cell_vel"]
    
    # Bass pushes from center
    bass = audio.mel_bands[:8].mean()
    center = np.array([0.5, 0.5])
    for i in range(len(state["cells"])):
        direction = state["cells"][i] - center
        dist = np.linalg.norm(direction)
        if dist > 0:
            state["cells"][i] += direction / dist * bass * 0.01
    
    # Spawn new cell on onset
    if audio.onset and len(state["cells"]) < 16:
        state["cells"] = np.vstack([state["cells"], np.random.rand(1, 2)])
        state["cell_vel"] = np.vstack([state["cell_vel"], np.random.randn(1, 2) * 0.002])
        state["cell_colors"] = np.append(state["cell_colors"], np.random.rand())
    
    state["cells"] = np.clip(state["cells"], 0, 1)
    
    # Voronoi diagram
    y_grid = np.linspace(0, 1, h)[:, np.newaxis]
    x_grid = np.linspace(0, 1, w)[np.newaxis, :]
    
    closest = np.zeros((h, w), dtype=int)
    min_dist = np.full((h, w), float('inf'))
    
    for i, (cx, cy) in enumerate(state["cells"]):
        dx = x_grid - cx
        dy = y_grid - cy
        dist = dx*dx + dy*dy
        mask = dist < min_dist
        closest[mask] = i
        min_dist[mask] = dist[mask]
    
    # Color cells
    for i in range(len(state["cells"])):
        mask = closest == i
        energy = audio.mel_bands[i % MEL_BANDS]
        color_t = (state["cell_colors"][i] + audio.centroid) % 1.0
        color = lut[int(color_t * 255)]
        fb[mask] = (color * energy).astype(np.uint8)
    
    # Edge detection for borders
    edges = np.zeros((h, w), dtype=bool)
    edges[:-1, :] |= closest[:-1, :] != closest[1:, :]
    edges[:, :-1] |= closest[:, :-1] != closest[:, 1:]
    fb[edges] = [255, 255, 255]
    
    return fb


def render_scope(fb, audio, frame, lut, state):
    """Mode 8: Lissajous oscilloscope with phosphor glow."""
    h, w, _ = fb.shape
    
    # Phosphor decay
    fb[:] = (fb * 0.85).astype(np.uint8)
    
    if len(audio.waveform) < 2:
        return fb
    
    # Lissajous: x = wave[i], y = wave[i + delay]
    delay = len(audio.waveform) // 4
    n = len(audio.waveform) - delay
    
    brightness = int(audio.rms * 255)
    color = lut[128]  # Green phosphor
    
    for i in range(n - 1):
        x0 = int((audio.waveform[i] * 0.4 + 0.5) * w)
        y0 = int((audio.waveform[i + delay] * 0.4 + 0.5) * h)
        x1 = int((audio.waveform[i + 1] * 0.4 + 0.5) * w)
        y1 = int((audio.waveform[i + 1 + delay] * 0.4 + 0.5) * h)
        
        # Bresenham-ish line
        x0, y0, x1, y1 = np.clip([x0, y0, x1, y1], 0, [w-1, h-1, w-1, h-1])
        dx = abs(x1 - x0)
        dy = abs(y1 - y0)
        steps = max(dx, dy, 1)
        
        for t in range(steps):
            x = int(x0 + (x1 - x0) * t / steps)
            y = int(y0 + (y1 - y0) * t / steps)
            if 0 <= x < w and 0 <= y < h:
                fb[y, x] = (color * brightness // 255).astype(np.uint8)
    
    return fb


def render_kaleidoscope(fb, audio, frame, lut, state):
    """Mode 9: Kaleidoscopic symmetry transform."""
    h, w, _ = fb.shape
    
    if "segments" not in state:
        state["segments"] = 6
        state["rotation"] = 0.0
        state["base_pattern"] = np.random.rand(h, w)
    
    # Change segments on beat
    if audio.beat:
        state["segments"] = np.random.randint(4, 13)
    
    # BPM-synced rotation
    rot_speed = 0.02 * (audio.bpm / 120.0) if audio.bpm > 0 else 0.02
    state["rotation"] += rot_speed
    
    # Generate base pattern (mini plasma)
    y_coords = np.linspace(-1, 1, h)[:, np.newaxis]
    x_coords = np.linspace(-1, 1, w)[np.newaxis, :]
    
    complexity = 1.0 + audio.flatness * 5
    pattern = np.sin(x_coords * complexity + state["rotation"]) + \
              np.sin(y_coords * complexity * 1.618 + state["rotation"] * 0.7)
    pattern = (pattern - pattern.min()) / (pattern.max() - pattern.min() + 1e-6)
    
    # Polar coordinates
    angle = np.arctan2(y_coords, x_coords)
    
    # Kaleidoscope symmetry
    segment_angle = 2 * np.pi / state["segments"]
    kaleid_angle = (angle + state["rotation"]) % segment_angle
    mirror = ((angle + state["rotation"]) // segment_angle) % 2
    kaleid_angle = np.where(mirror == 0, kaleid_angle, segment_angle - kaleid_angle)
    
    # Map back to pattern
    kx = np.cos(kaleid_angle)
    ky = np.sin(kaleid_angle)
    
    # Sample pattern (simple nearest neighbor)
    px = ((kx + 1) * 0.5 * (w - 1)).astype(int)
    py = ((ky + 1) * 0.5 * (h - 1)).astype(int)
    px = np.clip(px, 0, w - 1)
    py = np.clip(py, 0, h - 1)
    
    kaleid = pattern[py, px]
    kaleid = (kaleid + audio.centroid) % 1.0
    
    indices = (kaleid * 255).astype(int)
    fb[:] = lut[indices]
    
    return fb


def render_fractal(fb, audio, frame, lut, state):
    """Mode 10: Mandelbrot/Julia fractal with audio-reactive zoom and morph."""
    h, w, _ = fb.shape

    if "zoom" not in state or state.get("_dims") != (h, w):
        state.clear()
        state["_dims"] = (h, w)
        state["zoom"] = 1.5
        state["center_x"] = -0.5
        state["center_y"] = 0.0
        state["julia_mode"] = False
        state["julia_cx"] = -0.7
        state["julia_cy"] = 0.27015
        state["zoom_vel"] = 0.0
        state["color_shift"] = 0.0
        state["smooth_bass"] = 0.0

    # Audio-driven parameters
    bass = float(np.mean(audio.mel_bands[:8]))
    mid = float(np.mean(audio.mel_bands[12:25]))
    high = float(np.mean(audio.mel_bands[28:]))
    state["smooth_bass"] = state["smooth_bass"] * 0.85 + bass * 0.15

    # Beat toggles Julia/Mandelbrot mode
    if audio.beat:
        state["julia_mode"] = not state["julia_mode"]
        state["zoom_vel"] += 0.02

    # Zoom in continuously, bass accelerates
    state["zoom_vel"] = state["zoom_vel"] * 0.95 + bass * 0.005
    state["zoom"] *= (1.0 - state["zoom_vel"] * 0.3)
    state["zoom"] = max(state["zoom"], 1e-12)

    # Reset zoom if it gets too deep
    if state["zoom"] < 1e-10:
        state["zoom"] = 1.5
        state["center_x"] = -0.5 + np.random.randn() * 0.3
        state["center_y"] = np.random.randn() * 0.3

    # Julia c-parameter morphs with audio
    t = frame * 0.01
    state["julia_cx"] = -0.7 + np.sin(t * 1.618) * 0.15 + mid * 0.1
    state["julia_cy"] = 0.27015 + np.cos(t * 1.414) * 0.15 + high * 0.1

    # Color shift from centroid
    state["color_shift"] += 0.002 + audio.centroid * 0.01

    # Build coordinate grid
    aspect = w / max(h, 1)
    zoom = state["zoom"]
    cx, cy = state["center_x"], state["center_y"]

    x_lin = np.linspace(cx - zoom * aspect, cx + zoom * aspect, w)
    y_lin = np.linspace(cy - zoom, cy + zoom, h)
    real, imag = np.meshgrid(x_lin, y_lin)

    # Max iterations scale with treble energy
    max_iter = int(40 + high * 60)
    max_iter = min(max_iter, 120)

    if state["julia_mode"]:
        # Julia set: z starts at pixel, c is fixed
        zr = real.copy()
        zi = imag.copy()
        cr = np.full_like(real, state["julia_cx"])
        ci = np.full_like(imag, state["julia_cy"])
    else:
        # Mandelbrot: z starts at 0, c is pixel
        zr = np.zeros_like(real)
        zi = np.zeros_like(imag)
        cr = real
        ci = imag

    # Escape-time iteration with smooth coloring
    escape_count = np.zeros((h, w), dtype=np.float64)
    escaped = np.zeros((h, w), dtype=bool)

    for i in range(max_iter):
        zr2 = zr * zr
        zi2 = zi * zi
        mag2 = zr2 + zi2

        new_escaped = (~escaped) & (mag2 > 4.0)
        # Smooth escape: i + 1 - log2(log2(|z|))
        log_zn = np.log(np.maximum(mag2[new_escaped], 1e-10)) * 0.5
        escape_count[new_escaped] = i + 1.0 - np.log2(np.maximum(log_zn, 1e-10))
        escaped |= new_escaped

        if np.all(escaped):
            break

        # z = z² + c
        zi_new = 2.0 * zr * zi + ci
        zr_new = zr2 - zi2 + cr
        zr = np.where(escaped, zr, zr_new)
        zi = np.where(escaped, zi, zi_new)

    # Normalize to 0-1 with color shift
    values = escape_count / max(max_iter, 1)
    values = (values + state["color_shift"]) % 1.0

    # Interior points get bass-reactive glow
    interior = ~escaped
    values[interior] = state["smooth_bass"] * 0.3

    indices = (np.clip(values, 0, 1) * 255).astype(int)
    fb[:] = lut[indices]

    return fb
VIZ_MODES = [
    render_diagnostics,
    render_plasma,
    render_fire,
    render_spectrum,
    render_particles,
    render_tunnel,
    render_wave_interference,
    render_voronoi,
    render_scope,
    render_kaleidoscope,
    render_fractal
]


AI_MODE = -1  # special mode index for AI visualization


class InlinePrompt:
    """Non-blocking text prompt that renders as an overlay while animation continues."""

    def __init__(self):
        self.active = False
        self.text: list[str] = []
        self.callback = None  # called with (str) on submit, None on cancel
        self.label = "AI Prompt"

    def open(self, label: str, callback):
        """Start capturing input. callback(text_or_None) on finish."""
        self.active = True
        self.text = []
        self.label = label
        self.callback = callback

    def handle_key(self, key, term) -> bool:
        """Process a keypress while prompt is active. Returns True if consumed."""
        if not self.active:
            return False
        if key.code == term.KEY_ENTER or key in ("\n", "\r"):
            result = "".join(self.text).strip() or None
            self.active = False
            if self.callback:
                self.callback(result)
            return True
        elif key.code == term.KEY_ESCAPE:
            self.active = False
            if self.callback:
                self.callback(None)
            return True
        elif key.code == term.KEY_BACKSPACE or key == "\x7f":
            if self.text:
                self.text.pop()
            return True
        elif key.is_sequence:
            return True  # swallow arrow keys etc. while typing
        else:
            self.text.append(str(key))
            return True

    def render(self, term_width, term_height) -> str:
        """Return ANSI string for the prompt overlay (2 lines near bottom)."""
        if not self.active:
            return ""
        prompt_y = term_height - 3
        display = "".join(self.text)[:term_width - 6]
        bar = "─" * max(0, term_width - len(self.label) - 4)
        return (
            f"\x1b[{prompt_y};1H"
            f"\x1b[38;2;0;255;100m\x1b[48;2;10;10;30m"
            f" {self.label}: {bar}"
            f"\x1b[{prompt_y+1};1H"
            f"\x1b[38;2;255;255;255m\x1b[48;2;20;20;40m"
            f"> {display}{' ' * max(0, term_width - len(display) - 4)}"
            f"\x1b[{prompt_y+1};{3 + len(display)}H"
            f"\x1b[?25h"  # show cursor while typing
        )


# ============================================================================
# RENDERING ENGINE
# ============================================================================

def render_halfblock(fb, term):
    """Render framebuffer using half-block characters with ANSI escapes."""
    h, w, _ = fb.shape
    rows = h // 2
    
    parts = ["\x1b[H"]  # Home cursor
    prev_fg = None
    prev_bg = None
    
    for row in range(rows):
        y_top = row * 2
        y_bot = y_top + 1
        
        for col in range(w):
            r_fg, g_fg, b_fg = int(fb[y_top, col, 0]), int(fb[y_top, col, 1]), int(fb[y_top, col, 2])
            if y_bot < h:
                r_bg, g_bg, b_bg = int(fb[y_bot, col, 0]), int(fb[y_bot, col, 1]), int(fb[y_bot, col, 2])
            else:
                r_bg, g_bg, b_bg = 0, 0, 0
            
            fg = (r_fg, g_fg, b_fg)
            bg = (r_bg, g_bg, b_bg)
            
            s = ''
            if fg != prev_fg:
                s = f"\x1b[38;2;{r_fg};{g_fg};{b_fg}m"
                prev_fg = fg
            if bg != prev_bg:
                s += f"\x1b[48;2;{r_bg};{g_bg};{b_bg}m"
                prev_bg = bg
            
            parts.append(s + "▀")
        
        if row < rows - 1:
            parts.append("\n")
    
    parts.append("\x1b[0m")
    return "".join(parts)


def render_hud(term, mode_idx, palette_idx, bass_flash, gain, bpm, beat, fps, paused,
               ai_active=False, version_info=""):
    """Render bottom HUD bar."""
    n_modes = len(MODE_NAMES)
    if mode_idx == AI_MODE:
        mode_label = "AI"
    elif 0 <= mode_idx < n_modes:
        mode_label = MODE_NAMES[mode_idx]
    else:
        mode_label = "?"

    beat_dot = "●" if beat else "○"
    pause_status = " [PAUSED]" if paused else ""
    ver_str = f" │ {version_info}" if version_info else ""

    hud = (f"▲▼:mode ◄►:ver │ {mode_label} ({mode_idx+1 if mode_idx>=0 else 'AI'}/{n_modes}) │ "
           f"c:pal b:flash a:AI f:refine ?:help │ "
           f"{int(bpm)}bpm {beat_dot} │ {int(fps)}fps{pause_status}{ver_str}")

    return term.move_x(0) + term.on_black + term.white + hud[:term.width] + term.normal


# ============================================================================
# MAIN LOOP
# ============================================================================

def list_devices():
    """List available audio input devices."""
    p = pyaudio.PyAudio()
    print("\nAvailable audio input devices:\n")
    for i in range(p.get_device_count()):
        info = p.get_device_info_by_index(i)
        if info["maxInputChannels"] > 0:
            print(f"  [{i}] {info['name']}")
            print(f"      Channels: {info['maxInputChannels']}, "
                  f"Rate: {int(info['defaultSampleRate'])} Hz")
    print()
    p.terminate()


def select_device_interactive():
    """Interactive device selection."""
    p = pyaudio.PyAudio()
    devices = []
    
    for i in range(p.get_device_count()):
        info = p.get_device_info_by_index(i)
        if info["maxInputChannels"] > 0:
            devices.append((i, info["name"]))
    
    p.terminate()
    
    if not devices:
        print("No input devices found!")
        return None
    
    print("\nSelect audio input device:\n")
    for idx, (dev_id, name) in enumerate(devices):
        print(f"  {idx + 1}. {name}")
    
    while True:
        try:
            choice = input("\nEnter device number (or press Enter for default): ").strip()
            if not choice:
                return None
            choice_idx = int(choice) - 1
            if 0 <= choice_idx < len(devices):
                return devices[choice_idx][0]
            print("Invalid selection.")
        except (ValueError, KeyboardInterrupt):
            return None


def main():
    parser = argparse.ArgumentParser(description="TermVJ - Terminal Audio-Reactive Visualizer")
    parser.add_argument("--list", action="store_true", help="List audio devices and exit")
    parser.add_argument("--device", type=int, help="Audio device index")
    args = parser.parse_args()
    
    if args.list:
        list_devices()
        return
    
    device_index = args.device
    if device_index is None:
        device_index = select_device_interactive()
    
    term = Terminal()
    
    # Start audio engine
    audio_engine = AudioEngine(device_index=device_index)
    audio_engine.start()
    
    # Restore persisted state
    saved = load_persisted_state()
    mode = saved.get("mode", 0)
    palette_idx = saved.get("palette_idx", 0)
    # Clamp to valid range
    if mode != AI_MODE and not (0 <= mode < len(VIZ_MODES)):
        mode = 0
    palette_idx = palette_idx % len(PALETTE_NAMES)

    bass_flash = False
    gain = 1.0
    paused = False
    frame_count = 0
    viz_state = {}
    show_help = False
    
    # AI visualization + version store
    debug_panel = DebugPanel()
    ai_manager = None
    version_store = ShaderVersionStore.load(VERSIONS_FILE)

    if HAS_COPILOT:
        ai_manager = AIVizManager(debug_panel)
        debug_panel.log("Copilot SDK available ✓", (100, 255, 100))
    else:
        debug_panel.log("Copilot SDK not installed", (255, 200, 100))
        debug_panel.log("pip install github-copilot-sdk", (200, 200, 200))

    # Restore AI render function from version store if we were in AI mode
    if mode == AI_MODE and version_store.current and ai_manager:
        fn, err = load_render_fn(version_store.current.code)
        if fn:
            ai_manager.render_fn = fn
            ai_manager.iteration = version_store.count
            debug_panel.log(f"Restored AI v{version_store.cursor+1}/{version_store.count}", (100, 200, 255))

    # Total modes including AI (AI is after all built-in modes)
    n_builtin = len(VIZ_MODES)
    
    fps_history = deque(maxlen=30)
    last_time = time.monotonic()
    
    def cycle_mode(delta):
        """Cycle through modes: 0..n_builtin-1, then AI_MODE."""
        nonlocal mode, viz_state
        # Build ordered mode list: [0, 1, ..., n_builtin-1, AI_MODE]
        modes = list(range(n_builtin)) + [AI_MODE]
        try:
            idx = modes.index(mode)
        except ValueError:
            idx = 0
        idx = (idx + delta) % len(modes)
        mode = modes[idx]
        viz_state.clear()
        save_persisted_state(mode, palette_idx)

    def cycle_ai_version(delta):
        """Cycle through AI shader versions with left/right."""
        if not ai_manager or version_store.count == 0:
            return
        ver = version_store.go_next() if delta > 0 else version_store.go_prev()
        if ver:
            fn, err = load_render_fn(ver.code)
            if fn:
                ai_manager.render_fn = fn
                viz_state.clear()
                debug_panel.log(
                    f"Version {version_store.cursor+1}/{version_store.count}: {ver.description[:30]}",
                    (100, 200, 255))
            else:
                debug_panel.log(f"Version load error: {err[:40]}", (255, 100, 100))
        version_store.save(VERSIONS_FILE)

    def store_ai_version(code, prompt, screenshot_path=None, description=""):
        """Store a new AI shader version."""
        parent_id = version_store.current.id if version_store.current else None
        ver = ShaderVersion.create(
            code=code,
            prompt=prompt,
            parent_id=parent_id,
            screenshot_path=screenshot_path,
            iteration=version_store.count + 1,
            description=description,
        )
        version_store.add(ver)
        version_store.save(VERSIONS_FILE)
        debug_panel.log(f"Stored v{version_store.count}", (100, 255, 100))

    # Wire up version callback now that store_ai_version is defined
    if ai_manager:
        ai_manager.on_new_version = store_ai_version

    inline_prompt = InlinePrompt()
    _pending_screenshot = [None]  # mutable container for closure access

    try:
        with term.hidden_cursor(), term.cbreak(), term.fullscreen():
            try:
                sys.stdout.write("\x1b[?25l")
            except Exception:
                pass
            
            while True:
                frame_start = time.monotonic()
                
                # Handle keyboard
                key = term.inkey(timeout=0)
                if key:
                    # Inline prompt gets first crack at keys
                    if inline_prompt.handle_key(key, term):
                        pass  # consumed by prompt
                    elif key.lower() == 'q' or key.code == term.KEY_ESCAPE:
                        break
                    elif key.code == term.KEY_UP:
                        cycle_mode(-1)
                    elif key.code == term.KEY_DOWN:
                        cycle_mode(1)
                    elif key.code == term.KEY_LEFT:
                        if mode == AI_MODE:
                            cycle_ai_version(-1)
                        else:
                            cycle_mode(-1)
                    elif key.code == term.KEY_RIGHT:
                        if mode == AI_MODE:
                            cycle_ai_version(1)
                        else:
                            cycle_mode(1)
                    elif key.lower() == 'c':
                        if key.isupper():
                            palette_idx = (palette_idx - 1) % len(PALETTE_NAMES)
                        else:
                            palette_idx = (palette_idx + 1) % len(PALETTE_NAMES)
                        save_persisted_state(mode, palette_idx)
                    elif key.lower() == 'b':
                        bass_flash = not bass_flash
                    elif key in ('+', '='):
                        gain = min(gain + 0.2, 5.0)
                    elif key == '-':
                        gain = max(gain - 0.2, 0.1)
                    elif key.lower() == 'r':
                        gain = 1.0
                    elif key == ' ':
                        paused = not paused
                    elif key.lower() == 'a' and ai_manager:
                        show_help = False
                        def _on_ai_prompt(text):
                            nonlocal mode, viz_state
                            if text:
                                debug_panel.log(f"Generating: {text[:40]}", (100, 200, 255))
                                ai_manager.generate(text)
                                mode = AI_MODE
                                viz_state.clear()
                                save_persisted_state(mode, palette_idx)
                        inline_prompt.open("AI Prompt", _on_ai_prompt)
                    elif key.lower() == 'f' and ai_manager and mode == AI_MODE:
                        show_help = False
                        _pending_screenshot[0] = None
                        if HAS_PIL and 'last_fb' in viz_state:
                            _pending_screenshot[0] = ai_manager.screenshot(viz_state['last_fb'])
                        def _on_refine(text):
                            if text:
                                debug_panel.log(f"Refining: {text[:40]}", (100, 200, 255))
                                ai_manager.generate(text, _pending_screenshot[0])
                        inline_prompt.open("Refine", _on_refine)
                    elif key.lower() == 'i' and ai_manager and mode == AI_MODE:
                        show_help = False
                        if HAS_PIL and 'last_fb' in viz_state:
                            screenshot_path = ai_manager.screenshot(viz_state['last_fb'])
                            debug_panel.log("Self-improving... 🔄", (255, 200, 100))
                            ai_manager.generate(
                                "Look at this screenshot of the current visualization. "
                                "Analyze what works and what doesn't. Then generate an IMPROVED "
                                "version that is more visually striking, has better audio reactivity, "
                                "smoother motion, and fills more of the screen. Keep what works, fix what doesn't.",
                                screenshot_path
                            )
                        else:
                            debug_panel.log("No screenshot available", (255, 100, 100))
                    elif key in ('?', 'h', 'H'):
                        show_help = not show_help
                
                if not paused:
                    # Get audio features
                    audio = audio_engine.get_features()
                    
                    # Apply gain
                    audio.spectrum *= gain
                    audio.mel_bands *= gain
                    audio.rms *= gain
                    
                    # Create framebuffer
                    ph = (term.height - 1) * 2
                    pw = term.width
                    fb = np.zeros((ph, pw, 3), dtype=np.uint8)
                    
                    # Bass flash background
                    if bass_flash and audio.beat:
                        bass_level = audio.mel_bands[:8].mean()
                        fb[:] = int(bass_level * 255)
                    
                    # Generate palette LUT
                    lut = make_palette_lut(PALETTE_NAMES[palette_idx])
                    
                    # Clear stale overlays
                    viz_state.pop('overlays', None)
                    
                    # Render visualization
                    if mode == AI_MODE and ai_manager and ai_manager.render_fn:
                        try:
                            ai_manager.render_fn(fb, audio, frame_count, lut, viz_state)
                        except Exception as e:
                            err_str = str(e)
                            debug_panel.log(f"💥 {err_str[:45]}", (255, 100, 100))
                            fb[fb.shape[0]//2-2:fb.shape[0]//2+2, :] = (80, 0, 0)
                            if not ai_manager.generating:
                                ai_manager.report_runtime_error(err_str)
                    elif mode == AI_MODE:
                        h, w = fb.shape[:2]
                        if ai_manager and ai_manager.generating:
                            msg = "⏳ Generating..."
                        elif version_store.count > 0:
                            msg = "◄► to browse versions, 'a' for new prompt"
                        else:
                            msg = "Press 'a' for AI prompt"
                        viz_state['overlays'] = [(h // 4, max(0, w // 2 - len(msg)), msg, (100, 200, 255))]
                    elif 0 <= mode < len(VIZ_MODES):
                        VIZ_MODES[mode](fb, audio, frame_count, lut, viz_state)
                    
                    # Store fb for screenshot
                    viz_state['last_fb'] = fb.copy()
                    
                    # Render to terminal
                    frame_str = render_halfblock(fb, term)
                    
                    # HUD
                    fps = 1.0 / (frame_start - last_time + 1e-6)
                    fps_history.append(fps)
                    avg_fps = np.mean(fps_history)
                    
                    # Version info string
                    ver_info = ""
                    if mode == AI_MODE and version_store.count > 0:
                        ver_info = f"v{version_store.cursor+1}/{version_store.count}"
                        cur = version_store.current
                        if cur and cur.description:
                            ver_info += f" {cur.description[:20]}"

                    hud_str = render_hud(term, mode, palette_idx, bass_flash, gain,
                                        audio.bpm, audio.beat, avg_fps, paused,
                                        ai_active=(mode == AI_MODE),
                                        version_info=ver_info)
                    
                    # Output
                    sys.stdout.write(frame_str)
                    
                    # Text overlays
                    overlays = viz_state.get('overlays', [])
                    for ov_row, ov_col, ov_text, ov_fg in overlays:
                        if 0 <= ov_row < term.height - 1 and ov_col < term.width:
                            truncated = ov_text[:term.width - ov_col]
                            r, g, b = ov_fg
                            sys.stdout.write(
                                f"\x1b[{ov_row + 1};{ov_col + 1}H"
                                f"\x1b[38;2;{r};{g};{b}m\x1b[48;2;0;0;0m"
                                f"{truncated}\x1b[0m"
                            )
                    
                    # Debug panel
                    if debug_panel.lines:
                        sys.stdout.write(debug_panel.render(term.width, term.height))
                    
                    # Help overlay
                    if show_help:
                        help_lines = [
                            "┌─ TermVJ Shortcuts ──────────────────────┐",
                            "│                                         │",
                            "│  ▲/▼    Cycle visualization mode        │",
                            "│  ◄/►    Browse AI shader versions       │",
                            "│  c/C    Next / previous color palette    │",
                            "│  b      Toggle bass flash background     │",
                            "│  +/-    Adjust gain (fine-tune AGC)      │",
                            "│  r      Reset gain to auto (1.0)         │",
                            "│  SPACE  Pause / resume                   │",
                            "│  a      AI mode — enter prompt           │",
                            "│  f      Refine AI viz (with screenshot)  │",
                            "│  i      AI self-improve (auto-iterate)   │",
                            "│  ?/h    Toggle this help                 │",
                            "│  q/ESC  Quit                             │",
                            "│                                         │",
                            "│  Modes cycle: DIAG → PLASMA → FIRE →   │",
                            "│  SPEC → PARTS → TUNNEL → WAVES →       │",
                            "│  VORONOI → SCOPE → KALEID → FRACTAL →  │",
                            "│  AI → (wrap around)                     │",
                            "│                                         │",
                            "└─────────────────────────────────────────┘",
                        ]
                        box_w = 43
                        box_h = len(help_lines)
                        x0 = max(0, (term.width - box_w) // 2)
                        y0 = max(0, (term.height - box_h) // 2)
                        for i, line in enumerate(help_lines):
                            row = y0 + i
                            if 0 <= row < term.height - 1:
                                sys.stdout.write(
                                    f"\x1b[{row+1};{x0+1}H"
                                    f"\x1b[38;2;200;255;200m\x1b[48;2;10;20;10m"
                                    f"{line}\x1b[0m"
                                )
                    
                    sys.stdout.write(term.move_xy(0, term.height - 1) + hud_str)

                    # Inline prompt overlay (rendered last so it's on top)
                    prompt_str = inline_prompt.render(term.width, term.height)
                    if prompt_str:
                        sys.stdout.write(prompt_str)
                    elif not inline_prompt.active:
                        # Hide cursor when prompt is not active
                        sys.stdout.write("\x1b[?25l")

                    sys.stdout.flush()
                    
                    frame_count += 1
                    last_time = frame_start
                
                # Frame timing
                elapsed = time.monotonic() - frame_start
                sleep_time = max(0, 1.0 / TARGET_FPS - elapsed)
                if sleep_time > 0:
                    time.sleep(sleep_time)
    
    finally:
        audio_engine.stop()
        save_persisted_state(mode, palette_idx)
        version_store.save(VERSIONS_FILE)
        sys.stdout.write(term.clear + "\x1b[?25h")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
