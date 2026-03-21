def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape

    # Initialize coordinate grids
    if 'xx' not in state or state.get('_dims') != (h, w):
        y_coords = np.linspace(-1, 1, h)
        x_coords = np.linspace(-1, 1, w)
        state['xx'], state['yy'] = np.meshgrid(x_coords, y_coords)
        state['_dims'] = (h, w)

    xx, yy = state['xx'], state['yy']

    # Beat-reactive wobble — use kick_pulse envelope (shaped, not binary)
    if 'wobble' not in state:
        state['wobble'] = 0.0
    # Kick pulse drives wobble smoothly (already a shaped envelope)
    state['wobble'] = max(state['wobble'] * 0.85, audio.kick_pulse * 0.8)

    # Time parameters driven by audio
    t = frame * 0.02

    # Use pre-smoothed bands (no raw mel_bands slicing needed)
    bass_energy = audio.band_kick
    mid_energy = audio.band_mid

    # Wobble distortion on coordinates
    wobble_amount = state['wobble'] * 0.3 * bass_energy
    xx_dist = xx + np.sin(yy * 5 + t * 2) * wobble_amount
    yy_dist = yy + np.cos(xx * 5 + t * 2) * wobble_amount

    # Fluid gradient using multiple sine layers
    gradient = np.sin(xx_dist * 2.718 + t * 0.8 + audio.centroid * 3.14)
    gradient += np.sin(yy_dist * 1.618 - t * 0.5 + mid_energy * 2)
    gradient += np.sin((xx_dist - yy_dist) * 3.14159 + t * 1.2)
    gradient += np.sin(np.sqrt(xx_dist**2 + yy_dist**2) * 2.5 - t * 0.3)

    # Add spectral spread for complexity
    gradient += audio.spread * np.sin(xx_dist * yy_dist * 8 + t)

    # Normalize and apply audio brightness
    gradient = (gradient / 5 + 1) * 0.5
    gradient *= (0.5 + audio.rms * 0.5)

    # Color shift based on spectral centroid (already smoothed)
    gradient = (gradient + audio.centroid * 0.2) % 1.0

    # Apply palette
    indices = (gradient * 255).astype(int)
    fb[:] = lut[indices]

    # Waveform overlay using pre-smoothed, downsampled waveform
    waveform_height = max(8, h // 12)
    waveform_y_pos = h - waveform_height - 2
    waveform = audio.waveform  # already 128-sample, smoothed
    waveform_width = min(len(waveform), w - 10)
    waveform_x_start = (w - waveform_width) // 2

    # Draw smoothed waveform (no per-sample jitter)
    high_energy = audio.band_high
    accent_idx = int((0.8 + high_energy * 0.2) * 255)
    accent_color = lut[min(accent_idx, 255)]

    for i in range(waveform_width):
        x = waveform_x_start + i
        if 0 <= x < w:
            sample = waveform[min(i, len(waveform) - 1)]
            y_offset = int(sample * (waveform_height // 2))
            y = waveform_y_pos + waveform_height // 2 - y_offset
            y = max(0, min(h - 1, y))
            fb[y, x] = accent_color
