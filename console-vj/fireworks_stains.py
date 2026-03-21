def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape

    # Initialize persistent stain buffer and fireworks list
    if 'stains' not in state or state['stains'].shape != (h, w):
        state['stains'] = np.zeros((h, w), dtype=np.float64)
        state['fireworks'] = []
        state['_dims'] = (h, w)

    # Initialize coordinate grids
    if 'xx' not in state:
        y_coords = np.linspace(-1, 1, h)
        x_coords = np.linspace(-1, 1, w)
        state['xx'], state['yy'] = np.meshgrid(x_coords, y_coords)

    xx, yy = state['xx'], state['yy']

    # Spawn firework on kick pulse (shaped envelope, not binary beat)
    # Using a threshold on the envelope means we fire on strong beats
    # but not on every tiny fluctuation
    if audio.kick_pulse > 0.7 or (audio.snare_pulse > 0.6 and audio.onset_strength > 0.5):
        spawn_x = np.random.uniform(-0.4, 0.4)
        spawn_y = np.random.uniform(-0.3, 0.3)

        state['fireworks'].append({
            'x': spawn_x,
            'y': spawn_y,
            'age': 0,
            'color': audio.centroid,
            'intensity': 0.5 + audio.rms * 0.5
        })

    # Update and draw fireworks
    active_fireworks = []
    temp_layer = np.zeros((h, w), dtype=np.float64)

    for fw in state['fireworks']:
        fw['age'] += 1

        # Firework lasts about 1 second (30 frames)
        if fw['age'] < 30:
            active_fireworks.append(fw)

            # Explosion radius grows over time
            radius = (fw['age'] / 30.0) * 0.8

            # Distance from explosion center
            dist = np.sqrt((xx - fw['x'])**2 + (yy - fw['y'])**2)

            # Create expanding ring with sparkles
            ring_width = 0.1
            ring = np.exp(-((dist - radius) ** 2) / (ring_width ** 2))

            # Add radial sparkle pattern
            angle = np.arctan2(yy - fw['y'], xx - fw['x'])
            sparkle_count = 16
            sparkles = 0
            for i in range(sparkle_count):
                spoke_angle = (i / float(sparkle_count)) * 2 * 3.14159
                angle_diff = np.abs(((angle - spoke_angle + 3.14159) % (2 * 3.14159)) - 3.14159)
                spoke = np.exp(-(angle_diff ** 2) * 50) * (dist < radius) * (dist > radius * 0.3)
                sparkles += spoke

            # Combine ring and sparkles
            explosion = ring + sparkles * 0.5

            # Fade out over lifetime
            fade = (1.0 - fw['age'] / 30.0) ** 0.5
            explosion *= fade * fw['intensity']

            # Add to temporary layer
            temp_layer = np.maximum(temp_layer, explosion)

    state['fireworks'] = active_fireworks

    # Accumulate into permanent stain buffer (slow fade)
    state['stains'] *= 0.995
    state['stains'] = np.maximum(state['stains'], temp_layer)

    # Subtle audio-reactive background glow (using pre-smoothed band)
    bg_glow = audio.band_kick * 0.05

    # Combine stains with background
    combined = state['stains'] + bg_glow
    combined = np.clip(combined, 0, 1)

    # Color mapping — centroid is already smoothed
    color_offset = audio.centroid * 0.3
    color_values = (combined + color_offset) % 1.0

    # Apply palette
    indices = (color_values * 255).astype(int)
    fb[:] = lut[indices]
