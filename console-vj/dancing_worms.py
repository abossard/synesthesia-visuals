def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape
    
    # Initialize coordinate grid
    if 'xx' not in state or state.get('_dims') != (h, w):
        y_coords = np.linspace(-1, 1, h)
        x_coords = np.linspace(-1, 1, w)
        state['xx'], state['yy'] = np.meshgrid(x_coords, y_coords)
        state['_dims'] = (h, w)
    
    # Initialize worm states
    if 'worms' not in state:
        num_worms = 5
        state['worms'] = []
        for i in range(num_worms):
            state['worms'].append({
                'x': np.sin(i * 1.2) * 0.5,
                'y': np.cos(i * 1.7) * 0.5,
                'vx': 0.0,
                'vy': 0.0,
                'phase': i * 1.618,
                'jump': 0.0,
                'color_shift': i * 0.2
            })
    
    xx, yy = state['xx'], state['yy']
    fb[:] = 0
    
    # Create trail buffer for glow effect
    if 'trail' not in state or state['trail'].shape != (h, w):
        state['trail'] = np.zeros((h, w), dtype=np.float64)
    
    state['trail'] *= 0.85
    
    # Time progression
    t = frame * 0.05
    
    # Audio reactivity
    bass = np.mean(audio.mel_bands[:8]) if len(audio.mel_bands) > 8 else 0.5
    mid = np.mean(audio.mel_bands[12:20]) if len(audio.mel_bands) > 20 else 0.5
    high = np.mean(audio.mel_bands[28:]) if len(audio.mel_bands) > 28 else 0.5
    
    # Beat triggers jump
    if audio.beat:
        for worm in state['worms']:
            worm['jump'] = 1.5 + bass * 2.0
            worm['vx'] += (np.random.random() - 0.5) * 0.3
            worm['vy'] += (np.random.random() - 0.5) * 0.3
    
    # Render each worm
    for i, worm in enumerate(state['worms']):
        # Update physics
        worm['jump'] *= 0.88
        worm['vx'] *= 0.92
        worm['vy'] *= 0.92
        
        # Drift with audio flux
        worm['vx'] += np.sin(t * 0.7 + i) * 0.003 * (1 + audio.flux * 2)
        worm['vy'] += np.cos(t * 0.5 + i * 1.3) * 0.003 * (1 + audio.flux * 2)
        
        worm['x'] = np.clip(worm['x'] + worm['vx'], -0.9, 0.9)
        worm['y'] = np.clip(worm['y'] + worm['vy'], -0.9, 0.9)
        
        # Worm body segments
        num_segments = 15
        segment_field = np.zeros((h, w), dtype=np.float64)
        
        for seg in range(num_segments):
            seg_t = seg / float(num_segments)
            
            # Undulating motion
            seg_phase = worm['phase'] + t * (2 + mid * 3) + seg_t * 6.28
            
            seg_x = worm['x'] + np.sin(seg_phase) * 0.15 * (1 + bass * 0.5)
            seg_y = worm['y'] + np.cos(seg_phase * 1.3) * 0.15 * (1 + bass * 0.5)
            seg_y -= worm['jump'] * 0.3 * (1 - seg_t)
            
            # Distance from segment center
            dx = xx - seg_x
            dy = yy - seg_y
            dist = np.sqrt(dx**2 + dy**2)
            
            # Segment size (thicker at head, thinner at tail)
            seg_size = 0.08 * (1.2 - seg_t * 0.7) * (1 + worm['jump'] * 0.3)
            
            # Add segment to field with smooth falloff
            segment_intensity = np.maximum(0, 1 - dist / seg_size)
            segment_field += segment_intensity ** 2
        
        # Clamp and add to trail
        segment_field = np.clip(segment_field, 0, 1)
        state['trail'] = np.maximum(state['trail'], segment_field)
        
        # Color mapping with audio reactivity
        color_offset = worm['color_shift'] + audio.centroid * 0.4 + t * 0.1
        color_spread = 0.3 + audio.spread * 0.5 + high * 0.3
        
        color_values = segment_field * color_spread + color_offset
        color_values = color_values % 1.0
        
        # Apply brightness from audio
        brightness = segment_field * (0.6 + audio.rms * 0.4)
        brightness = np.clip(brightness, 0, 1)
        
        # Map to palette
        indices = (color_values * 255).astype(int)
        worm_colors = lut[indices]
        
        # Blend with brightness
        worm_colors = (worm_colors * brightness[:, :, np.newaxis]).astype(np.uint8)
        
        # Additive blending
        fb[:] = np.clip(fb.astype(int) + worm_colors.astype(int), 0, 255).astype(np.uint8)
    
    # Add subtle glow from trail
    glow = np.clip(state['trail'] * 0.4, 0, 1)
    glow_shift = t * 0.15 + audio.centroid * 0.3
    glow_values = (glow + glow_shift) % 1.0
    glow_indices = (glow_values * 255).astype(int)
    glow_colors = (lut[glow_indices] * glow[:, :, np.newaxis]).astype(np.uint8)
    
    fb[:] = np.clip(fb.astype(int) + glow_colors.astype(int), 0, 255).astype(np.uint8)
