def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape

    # Initialize coordinate grids
    if 'xx' not in state or state.get('_dims') != (h, w):
        y_coords = np.linspace(-1, 1, h)
        x_coords = np.linspace(-1, 1, w)
        state['xx'], state['yy'] = np.meshgrid(x_coords, y_coords)
        state['_dims'] = (h, w)
        state['trail'] = np.zeros((h, w), dtype=np.float64)
        state['worm_phase'] = 0.0
        state['worm_speed'] = 0.0

    xx, yy = state['xx'], state['yy']

    # Use pre-smoothed bands (no raw mel_bands slicing)
    bass = audio.band_kick
    mid = audio.band_mid
    high = audio.band_high

    # Speed tracking — flux and bass are already smoothed
    target_speed = 0.02 + audio.flux * 0.08 + bass * 0.05
    state['worm_speed'] = state['worm_speed'] * 0.85 + target_speed * 0.15
    state['worm_phase'] += state['worm_speed']

    # Soft beat impulse via kick_pulse envelope (not a hard phase jump)
    # The envelope is a shaped curve, so this adds a gentle push per beat
    state['worm_phase'] += audio.kick_pulse * 0.08

    # Worm path parameters
    t = state['worm_phase']
    segments = 8

    # Create the worm as a series of sinusoidal segments
    worm_field = np.zeros((h, w), dtype=np.float64)

    for i in range(segments):
        seg_phase = t - i * 0.3

        # Worm spine position (Lissajous-like curve)
        x_pos = np.sin(seg_phase * 1.618) * 0.6
        y_pos = np.sin(seg_phase * 1.0 + audio.centroid * 2) * 0.5 * np.cos(seg_phase * 0.5)

        # Distance from this segment
        dist = np.sqrt((xx - x_pos)**2 + (yy - y_pos)**2)

        # Segment thickness — mid is already smoothed, no jitter
        thickness = 0.08 + mid * 0.1 + np.sin(seg_phase * 2) * 0.03

        # Soft falloff
        segment_intensity = np.exp(-dist / thickness) * (1.0 - i / float(segments) * 0.3)

        # Rainbow color cycling along the worm body
        color_offset = i / float(segments)
        worm_field = np.maximum(worm_field, segment_intensity * (color_offset + t * 0.1))

    # Add sparkle on high frequencies (already smoothed)
    sparkle = np.sin(xx * 20 + t * 3) * np.sin(yy * 20 - t * 2.5)
    sparkle = np.maximum(0, sparkle) * high * 0.3

    # Combine with trail for smooth motion
    state['trail'] *= 0.88
    state['trail'] = np.maximum(state['trail'], worm_field + sparkle)

    # Map to rainbow palette with overall brightness from RMS (smoothed)
    brightness = 0.6 + audio.rms * 0.4
    indices = np.clip(state['trail'] * 255 * brightness, 0, 255).astype(int)
    fb[:] = lut[indices]
