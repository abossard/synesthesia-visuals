"""
audio_smoothing — a deep module that transforms raw audio features into
smooth, visualization-ready signals.

Design principles (A Philosophy of Software Design / Grokking Simplicity):

  NARROW INTERFACE:
    smoother = AudioSmoother(fps=30)
    smooth   = smoother.update(raw_features)   # returns SmoothedAudio

  DEEP INTERNALS (hidden):
    - EMA filters on every continuous parameter
    - Shaped envelopes replacing binary beat/onset booleans
    - Critically-damped springs for velocity-sensitive values
    - Audio-rate → render-rate decimation with proper averaging
    - Pre-smoothed waveform (downsampled + filtered)

  DATA SEPARATION:
    SmoothedAudio is a pure data object — no methods, no state, no actions.
    AudioSmoother is the single action boundary.
    All internal helpers are pure calculations (data in → data out).

  COMPATIBLE FIELD NAMES:
    SmoothedAudio uses the SAME field names as AudioFeatures wherever
    possible.  This means existing renderers work without changes — the
    smoothing is invisible to them.  The module is deep because it hides
    significant complexity behind a compatible interface.

Visualizations should ONLY read SmoothedAudio fields.  They should never
apply their own EMA, never compute frame-to-frame diffs.  Everything they
need is pre-cooked.
"""

from __future__ import annotations

import numpy as np
from dataclasses import dataclass


# ──────────────────────────────────────────────────────────────────────────
# DATA — pure value objects, no behaviour
# ──────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True, slots=True)
class SmoothedAudio:
    """The single output type that every visualization reads.

    Field names match AudioFeatures for drop-in compatibility.
    All continuous values are pre-smoothed.  Binary events (beat, onset)
    are passed through, but their ENVELOPE counterparts (kick_pulse,
    snare_pulse, hat_pulse, beat_pulse) are shaped curves that should
    be preferred for driving visual motion.

    Visualizations never need to smooth anything themselves.
    """

    # ── Pre-processed arrays (smoothed + downsampled) ──
    spectrum: np.ndarray        # 64-bin smoothed spectrum, 0–1
    mel_bands: np.ndarray       # 40-bin smoothed mel bands, 0–1
    mfcc: np.ndarray            # 13 MFCC coefficients (passed through)
    waveform: np.ndarray        # 128-sample smoothed waveform, -1–1

    # ── Spectral shape (all 0–1, smoothed) ──
    centroid: float = 0.0
    spread: float = 0.0
    rolloff: float = 0.0
    flatness: float = 0.0
    flux: float = 0.0
    slope: float = 0.0
    kurtosis: float = 0.0

    # ── Pitch (passed through — already stable from aubio) ──
    pitch_hz: float = 0.0
    pitch_midi: float = 0.0
    pitch_confidence: float = 0.0

    # ── Rhythm ──
    beat: bool = False          # raw beat flag (use kick_pulse for motion)
    onset: bool = False         # raw onset flag (use snare/hat_pulse)
    onset_strength: float = 0.0 # smoothed onset strength
    bpm: float = 0.0

    # ── Energy (all 0–1, smoothed) ──
    rms: float = 0.0
    is_quiet: bool = True

    # ── Perceptual Energy Bands (all 0–1, smoothed) ──
    band_sub_bass: float = 0.0
    band_kick: float = 0.0
    band_snare: float = 0.0
    band_mid: float = 0.0
    band_presence: float = 0.0
    band_high: float = 0.0
    band_air: float = 0.0

    # ── Onset-Classified Pulses (0–1, shaped envelopes) ──
    #    These are the PRIMARY way to drive beat-reactive visuals.
    #    They have smooth attack (no binary snap) and tuned decay.
    kick_pulse: float = 0.0     # shaped envelope, slow decay (~300ms)
    snare_pulse: float = 0.0    # shaped envelope, medium decay (~200ms)
    hat_pulse: float = 0.0      # shaped envelope, fast decay (~100ms)
    beat_phase: float = 0.0     # 0–1 sawtooth, synced to tempo
    beat_pulse: float = 0.0     # shaped envelope peaking on each beat

    # ── Spectral Centroid Chaser ──
    centroid_velocity: float = 0.0  # signed, pre-smoothed via spring

    # ── Spectral Flux (all 0–1, smoothed) ──
    low_flux: float = 0.0
    high_flux: float = 0.0
    tension: float = 0.0

    # ── MFCC Timbral Navigator (all 0–1, smoothed) ──
    mfcc_distance: float = 0.0
    timbre_hue: float = 0.0
    timbre_scale: float = 0.0
    timbre_bright: float = 0.0

    # ── Phase-Locked Oscillators (-1–1, already continuous) ──
    osc_half: float = 0.0
    osc_beat: float = 0.0
    osc_double: float = 0.0
    osc_triplet: float = 0.0
    osc_sixteenth: float = 0.0


# ──────────────────────────────────────────────────────────────────────────
# CALCULATIONS — pure functions, no side effects
# ──────────────────────────────────────────────────────────────────────────

def _ema(prev: float, target: float, alpha: float) -> float:
    """Exponential moving average.  alpha in (0,1]: 0=frozen, 1=instant."""
    return prev + alpha * (target - prev)


def _ema_array(prev: np.ndarray, target: np.ndarray, alpha: float) -> np.ndarray:
    """EMA on arrays, element-wise."""
    return prev + alpha * (target - prev)


def _smooth_pulse(current: float, raw_pulse: float, alpha: float) -> float:
    """Smooth a pulse envelope that already has attack/decay shaping upstream.

    The raw pulse from AudioEngine already jumps to 1.0 on onset and decays
    per audio hop.  We DON'T re-trigger or re-decay — we just EMA-smooth
    to remove frame-to-frame jitter while preserving the peak and shape.

    Uses asymmetric alpha: fast rise (track peaks), slower fall (smooth tail).
    """
    if raw_pulse > current:
        # Fast attack: track rising edges closely so peaks aren't lost
        return current + (raw_pulse - current) * min(alpha * 3, 0.9)
    else:
        # Slower release: smooth the decay tail
        return current + (raw_pulse - current) * alpha


def _critically_damped_spring(pos: float, vel: float,
                               target: float, omega: float,
                               dt: float) -> tuple[float, float]:
    """Critically damped spring for smooth chasing without overshoot.

    omega: natural frequency (higher = faster response).
    Returns (new_pos, new_vel).
    """
    diff = pos - target
    exp_term = np.exp(-omega * dt)
    new_pos = target + (diff + (vel + omega * diff) * dt) * exp_term
    new_vel = (vel - omega * omega * diff * dt) * exp_term
    return new_pos, new_vel


def _downsample_waveform(raw: np.ndarray, target_len: int = 128) -> np.ndarray:
    """Downsample + smooth a raw waveform to target_len samples.

    Uses bin-averaging (box filter) instead of point-sampling, then
    applies a 3-tap triangle filter.  This removes the visual jitter
    of raw sample-by-sample plotting.
    """
    n = len(raw)
    if n <= target_len:
        out = np.zeros(target_len)
        out[:n] = raw
        return out
    bin_size = n // target_len
    trimmed = raw[:bin_size * target_len]
    averaged = trimmed.reshape(target_len, bin_size).mean(axis=1)
    kernel = np.array([0.25, 0.5, 0.25])
    return np.convolve(averaged, kernel, mode='same')


def _downsample_spectrum(raw: np.ndarray, target_len: int = 64) -> np.ndarray:
    """Downsample a spectrum to fewer bins via max-pooling."""
    n = len(raw)
    if n <= target_len:
        out = np.zeros(target_len)
        out[:n] = raw
        return out
    bin_size = n // target_len
    trimmed = raw[:bin_size * target_len]
    return trimmed.reshape(target_len, bin_size).max(axis=1)


# ──────────────────────────────────────────────────────────────────────────
# ACTION BOUNDARY — the one stateful object
# ──────────────────────────────────────────────────────────────────────────

class AudioSmoother:
    """Transforms raw AudioFeatures into SmoothedAudio.

    This is the ONLY class that holds smoothing state.  Visualizations
    never see this object — they only receive its output.

    Interface:
        smoother = AudioSmoother(fps=30)
        smooth   = smoother.update(raw_features)
    """

    def __init__(self, fps: float = 30.0):
        self._dt = 1.0 / fps

        # ── Smoothed scalar state ──
        self._rms = 0.0
        self._onset_strength = 0.0
        self._band_sub_bass = 0.0
        self._band_kick = 0.0
        self._band_snare = 0.0
        self._band_mid = 0.0
        self._band_presence = 0.0
        self._band_high = 0.0
        self._band_air = 0.0
        self._centroid = 0.0
        self._spread = 0.0
        self._rolloff = 0.0
        self._flatness = 0.0
        self._flux = 0.0
        self._slope = 0.0
        self._kurtosis = 0.0
        self._low_flux = 0.0
        self._high_flux = 0.0
        self._tension = 0.0
        self._timbre_hue = 0.0
        self._timbre_scale = 0.0
        self._timbre_bright = 0.0
        self._mfcc_distance = 0.0

        # ── Shaped envelopes ──
        self._kick_env = 0.0
        self._snare_env = 0.0
        self._hat_env = 0.0
        self._beat_pulse_env = 0.0

        # ── Spring state for centroid velocity ──
        self._centroid_spring_pos = 0.0
        self._centroid_spring_vel = 0.0

        # ── Array states ──
        self._spectrum = np.zeros(64)
        self._mel_bands = np.zeros(40)
        self._waveform = np.zeros(128)

        # ── Smoothing rates (the hidden complexity) ──
        #
        # Tuned for 30fps.  The raw AudioEngine already applies AGC with
        # its own EMA (smooth=0.35–0.6), so these alphas are the SECOND
        # smoothing layer.  They need to be high enough that the combined
        # latency stays under ~100ms for transient-sensitive features.
        #
        # Alpha = fraction of new value blended per frame.
        #   0.15 = responsive (~100ms combined with AGC)
        #   0.25 = snappy (~60ms combined)
        #   0.40 = near-instant (~30ms combined)

        self._alpha_energy = 0.25       # rms, bands — must track beats quickly
        self._alpha_spectral = 0.18     # centroid, spread, flatness
        self._alpha_flux = 0.30         # flux, tension — transient-sensitive
        self._alpha_timbre = 0.10       # MFCC-derived (timbre changes slowly)
        self._alpha_arrays = 0.25       # spectrum, mel_bands
        self._alpha_waveform = 0.40     # waveform — needs to track shape closely
        self._alpha_pulse = 0.35        # pulse envelopes — must preserve peaks

        self._centroid_omega = 12.0     # spring stiffness for velocity (snappier)

    def update(self, raw) -> SmoothedAudio:
        """Transform raw AudioFeatures into SmoothedAudio.

        Call once per render frame.  This is the entire public API.
        """
        dt = self._dt

        # ── 1. Smooth continuous energy ──
        a = self._alpha_energy
        self._rms = _ema(self._rms, raw.rms, a)
        self._onset_strength = _ema(self._onset_strength, raw.onset_strength, a)
        self._band_sub_bass = _ema(self._band_sub_bass, raw.band_sub_bass, a)
        self._band_kick = _ema(self._band_kick, raw.band_kick, a)
        self._band_snare = _ema(self._band_snare, raw.band_snare, a)
        self._band_mid = _ema(self._band_mid, raw.band_mid, a)
        self._band_presence = _ema(self._band_presence, raw.band_presence, a)
        self._band_high = _ema(self._band_high, raw.band_high, a)
        self._band_air = _ema(self._band_air, raw.band_air, a)

        # ── 2. Smooth spectral shape ──
        a = self._alpha_spectral
        self._centroid = _ema(self._centroid, raw.centroid, a)
        self._spread = _ema(self._spread, raw.spread, a)
        self._rolloff = _ema(self._rolloff, raw.rolloff, a)
        self._flatness = _ema(self._flatness, raw.flatness, a)
        self._flux = _ema(self._flux, raw.flux, a)
        self._slope = _ema(self._slope, raw.slope, a)
        self._kurtosis = _ema(self._kurtosis, raw.kurtosis, a)

        # ── 3. Smooth flux and tension ──
        a = self._alpha_flux
        self._low_flux = _ema(self._low_flux, raw.low_flux, a)
        self._high_flux = _ema(self._high_flux, raw.high_flux, a)
        self._tension = _ema(self._tension, raw.tension, a)

        # ── 4. Smooth timbre ──
        a = self._alpha_timbre
        self._timbre_hue = _ema(self._timbre_hue, raw.timbre_hue, a)
        self._timbre_scale = _ema(self._timbre_scale, raw.timbre_scale, a)
        self._timbre_bright = _ema(self._timbre_bright, raw.timbre_bright, a)
        self._mfcc_distance = _ema(self._mfcc_distance, raw.mfcc_distance, a)

        # ── 5. Smooth pulse envelopes ──
        # The raw pulses from AudioEngine ALREADY have attack/decay shaping
        # (jump to 1.0 on onset, decay at 0.88–0.96 per audio hop).
        # We just smooth them to remove frame-to-frame jitter — we do NOT
        # re-trigger or re-decay, which would double-smooth and kill peaks.
        a = self._alpha_pulse
        self._kick_env = _smooth_pulse(self._kick_env, raw.kick_pulse, a)
        self._snare_env = _smooth_pulse(self._snare_env, raw.snare_pulse, a)
        self._hat_env = _smooth_pulse(self._hat_env, raw.hat_pulse, a)
        # beat_pulse: track raw beat as a quick envelope
        beat_target = 1.0 if raw.beat else self._beat_pulse_env * 0.88
        self._beat_pulse_env = _smooth_pulse(self._beat_pulse_env, beat_target, a)

        # ── 6. Spring-based centroid velocity ──
        self._centroid_spring_pos, self._centroid_spring_vel = (
            _critically_damped_spring(
                self._centroid_spring_pos,
                self._centroid_spring_vel,
                self._centroid,
                self._centroid_omega,
                dt))
        centroid_vel = float(np.clip(self._centroid_spring_vel, -1.0, 1.0))

        # ── 7. Smooth arrays ──
        target_spectrum = _downsample_spectrum(raw.spectrum, 64)
        self._spectrum = _ema_array(self._spectrum, target_spectrum, self._alpha_arrays)

        target_mel = np.asarray(raw.mel_bands, dtype=np.float64)
        if len(target_mel) != 40:
            target_mel = np.resize(target_mel, 40)
        self._mel_bands = _ema_array(self._mel_bands, target_mel, self._alpha_arrays)

        target_waveform = _downsample_waveform(raw.waveform, 128)
        self._waveform = _ema_array(self._waveform, target_waveform, self._alpha_waveform)

        # ── 8. Build immutable output ──
        return SmoothedAudio(
            spectrum=self._spectrum.copy(),
            mel_bands=self._mel_bands.copy(),
            mfcc=np.array(raw.mfcc, dtype=np.float64),
            waveform=self._waveform.copy(),
            centroid=self._centroid,
            spread=self._spread,
            rolloff=self._rolloff,
            flatness=self._flatness,
            flux=self._flux,
            slope=self._slope,
            kurtosis=self._kurtosis,
            pitch_hz=raw.pitch_hz,
            pitch_midi=raw.pitch_midi,
            pitch_confidence=raw.pitch_confidence,
            beat=raw.beat,                      # bool passthrough
            onset=raw.onset,                    # bool passthrough
            onset_strength=self._onset_strength,
            bpm=raw.bpm,
            rms=self._rms,
            is_quiet=raw.is_quiet,
            band_sub_bass=self._band_sub_bass,
            band_kick=self._band_kick,
            band_snare=self._band_snare,
            band_mid=self._band_mid,
            band_presence=self._band_presence,
            band_high=self._band_high,
            band_air=self._band_air,
            kick_pulse=self._kick_env,
            snare_pulse=self._snare_env,
            hat_pulse=self._hat_env,
            beat_phase=raw.beat_phase,          # already continuous
            beat_pulse=self._beat_pulse_env,
            centroid_velocity=centroid_vel,
            low_flux=self._low_flux,
            high_flux=self._high_flux,
            tension=self._tension,
            mfcc_distance=self._mfcc_distance,
            timbre_hue=self._timbre_hue,
            timbre_scale=self._timbre_scale,
            timbre_bright=self._timbre_bright,
            osc_half=raw.osc_half,              # already continuous sinusoids
            osc_beat=raw.osc_beat,
            osc_double=raw.osc_double,
            osc_triplet=raw.osc_triplet,
            osc_sixteenth=raw.osc_sixteenth,
        )
