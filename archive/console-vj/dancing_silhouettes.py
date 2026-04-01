def render_ai(fb, audio, frame, lut, state):
    h, w, _ = fb.shape
    
    # Smooth easing function (ease-in-out cubic)
    def ease(t):
        return t * t * (3.0 - 2.0 * t)
    
    # Initialize coordinate grid
    if 'xx' not in state or state.get('_dims') != (h, w):
        y_coords = np.linspace(0, 1, h)
        x_coords = np.linspace(0, 1, w)
        state['xx'], state['yy'] = np.meshgrid(x_coords, y_coords)
        state['_dims'] = (h, w)
        state['dancers'] = []
        # 5 dancers with different personalities and phase offsets
        for i in range(5):
            state['dancers'].append({
                'x': 0.13 + i * 0.18,
                'phase_offset': i * 1.618,  # golden ratio for natural variation
                'style': i % 3,  # 3 dance styles
                'hip_sway': 0,
                'shoulder_roll': 0,
                'head_bob': 0,
                'knee_bend': 0,
                'arm_pose_l': 0,
                'arm_pose_r': 0,
                'leg_pose_l': 0,
                'leg_pose_r': 0,
                'energy': 0.5
            })
        state['time_smooth'] = 0
    
    xx, yy = state['xx'], state['yy']
    
    # Smooth time accumulator (uses beat phase for perfect sync)
    state['time_smooth'] += audio.beat_phase * 0.05 + 0.015
    t = state['time_smooth']
    
    # Global energy level — rms and band_mid are already smoothed
    # by the AudioSmoother, so a direct blend is all we need
    if 'energy' not in state:
        state['energy'] = 0.0
    state['energy'] = audio.rms * 0.6 + audio.band_mid * 0.4
    
    # Subtle background with breathing
    breath = (np.sin(audio.osc_beat * 3.14159) * 0.5 + 0.5) * 0.03
    bg_val = 0.02 + audio.band_sub_bass * 0.08 + breath
    bg = np.full((h, w), bg_val, dtype=np.float64)
    
    # Create canvas for silhouettes
    canvas = np.zeros((h, w), dtype=np.float64)
    
    # Draw each dancer with smooth, realistic movement
    for idx, dancer in enumerate(state['dancers']):
        dx = dancer['x']
        style = dancer['style']
        phase = t * 0.5 + dancer['phase_offset']
        
        # Smooth interpolation to target poses (iPod commercial feel)
        beat_pulse = ease(audio.beat_phase)
        
        # Different dance styles
        if style == 0:  # Groovy body roll
            target_hip = np.sin(phase * 2) * 0.06
            target_shoulder = np.sin(phase * 2 + 0.8) * 0.04
            target_head = np.sin(phase * 2 + 1.2) * 0.02
            arm_l_angle = -0.3 + np.sin(phase * 1.5) * 0.6
            arm_r_angle = 0.3 + np.sin(phase * 1.5 + 2.0) * 0.6
            leg_move = np.sin(phase * 2) * 0.15
        elif style == 1:  # Smooth sway
            target_hip = np.sin(phase * 1.5) * 0.08
            target_shoulder = np.sin(phase * 1.5 + 0.5) * 0.05
            target_head = np.sin(phase * 1.5 + 0.3) * 0.025
            arm_l_angle = -0.5 + np.sin(phase * 1.2) * 0.4
            arm_r_angle = 0.5 + np.sin(phase * 1.2 + 3.14159) * 0.4
            leg_move = np.sin(phase * 1.5) * 0.12
        else:  # Hip hop bounce
            bounce_phase = phase * 2.5
            bounce = ease(np.sin(bounce_phase) * 0.5 + 0.5) * 0.04
            target_hip = np.sin(bounce_phase * 0.5) * 0.05
            target_shoulder = -bounce * 0.5
            target_head = bounce * 0.8
            arm_l_angle = -0.8 + np.sin(bounce_phase * 0.8) * 0.5
            arm_r_angle = 0.2 + np.sin(bounce_phase * 0.8 + 1.0) * 0.5
            leg_move = np.sin(bounce_phase) * 0.1
        
        # Smooth interpolation (critical for fluid motion)
        dancer['hip_sway'] += (target_hip - dancer['hip_sway']) * 0.15
        dancer['shoulder_roll'] += (target_shoulder - dancer['shoulder_roll']) * 0.12
        dancer['head_bob'] += (target_head - dancer['head_bob']) * 0.18
        
        # Knee bend on beat
        target_knee = beat_pulse * 0.03 * state['energy']
        dancer['knee_bend'] += (target_knee - dancer['knee_bend']) * 0.2
        
        # Base position with knee bend
        base_y = 0.72 + dancer['knee_bend']
        
        # Head - bobs and nods with music
        head_x = dx + dancer['shoulder_roll'] * 0.3 + dancer['head_bob']
        head_y = base_y - 0.28 - dancer['head_bob'] * 0.5
        head_r = 0.045
        head_mask = ((xx - head_x)**2 + (yy - head_y)**2) < head_r**2
        canvas[head_mask] = 1.0
        
        # Neck
        neck_y = head_y + 0.035
        neck_mask = ((xx - head_x)**2 + (yy - neck_y)**2) < 0.02**2
        canvas[neck_mask] = 1.0
        
        # Torso - smooth curve with hip sway and shoulder roll
        torso_top_y = base_y - 0.24
        torso_bot_y = base_y - 0.04
        
        for i, t_val in enumerate(np.linspace(0, 1, 25)):
            # Smooth spine curve
            spine_curve = ease(t_val)
            tx = dx + dancer['hip_sway'] * (1 - spine_curve) + dancer['shoulder_roll'] * spine_curve
            ty = torso_top_y + (torso_bot_y - torso_top_y) * t_val
            # Wider at hips, narrower at shoulders
            torso_w = 0.045 + (1 - spine_curve) * 0.025
            torso_mask = ((xx - tx)**2 + (yy - ty)**2) < torso_w**2
            canvas[torso_mask] = 1.0
        
        # Hips
        hip_x = dx + dancer['hip_sway']
        hip_y = torso_bot_y
        hip_w = 0.08
        hip_h = 0.03
        hip_mask = ((xx - hip_x)**2 / hip_w**2 + (yy - hip_y)**2 / hip_h**2) < 0.5
        canvas[hip_mask] = 1.0
        
        # Arms - smooth, natural swing
        shoulder_x = dx + dancer['shoulder_roll']
        shoulder_y = torso_top_y + 0.02
        arm_len_upper = 0.11
        arm_len_lower = 0.12
        
        # Left arm (smooth two-segment with elbow)
        target_arm_l = arm_l_angle
        dancer['arm_pose_l'] += (target_arm_l - dancer['arm_pose_l']) * 0.12
        
        elbow_l_x = shoulder_x - 0.035 + np.sin(dancer['arm_pose_l']) * arm_len_upper
        elbow_l_y = shoulder_y + np.cos(dancer['arm_pose_l']) * arm_len_upper
        
        # Forearm naturally follows with slight delay
        forearm_angle_l = dancer['arm_pose_l'] + np.sin(phase * 1.8) * 0.4
        hand_l_x = elbow_l_x + np.sin(forearm_angle_l) * arm_len_lower
        hand_l_y = elbow_l_y + np.cos(forearm_angle_l) * arm_len_lower
        
        # Draw upper arm
        for t_arm in np.linspace(0, 1, 12):
            ax = shoulder_x - 0.035 + np.sin(dancer['arm_pose_l']) * arm_len_upper * t_arm
            ay = shoulder_y + np.cos(dancer['arm_pose_l']) * arm_len_upper * t_arm
            canvas[((xx - ax)**2 + (yy - ay)**2) < 0.022**2] = 1.0
        
        # Draw forearm
        for t_arm in np.linspace(0, 1, 12):
            ax = elbow_l_x + (hand_l_x - elbow_l_x) * t_arm
            ay = elbow_l_y + (hand_l_y - elbow_l_y) * t_arm
            canvas[((xx - ax)**2 + (yy - ay)**2) < 0.02**2] = 1.0
        
        # Right arm (mirror logic)
        target_arm_r = arm_r_angle
        dancer['arm_pose_r'] += (target_arm_r - dancer['arm_pose_r']) * 0.12
        
        elbow_r_x = shoulder_x + 0.035 + np.sin(dancer['arm_pose_r']) * arm_len_upper
        elbow_r_y = shoulder_y + np.cos(dancer['arm_pose_r']) * arm_len_upper
        
        forearm_angle_r = dancer['arm_pose_r'] + np.sin(phase * 1.8 + 3.14159) * 0.4
        hand_r_x = elbow_r_x + np.sin(forearm_angle_r) * arm_len_lower
        hand_r_y = elbow_r_y + np.cos(forearm_angle_r) * arm_len_lower
        
        for t_arm in np.linspace(0, 1, 12):
            ax = shoulder_x + 0.035 + np.sin(dancer['arm_pose_r']) * arm_len_upper * t_arm
            ay = shoulder_y + np.cos(dancer['arm_pose_r']) * arm_len_upper * t_arm
            canvas[((xx - ax)**2 + (yy - ay)**2) < 0.022**2] = 1.0
        
        for t_arm in np.linspace(0, 1, 12):
            ax = elbow_r_x + (hand_r_x - elbow_r_x) * t_arm
            ay = elbow_r_y + (hand_r_y - elbow_r_y) * t_arm
            canvas[((xx - ax)**2 + (yy - ay)**2) < 0.02**2] = 1.0
        
        # Legs - smooth stepping motion with proper knees
        leg_len_upper = 0.13
        leg_len_lower = 0.14
        
        # Left leg
        target_leg_l = leg_move
        dancer['leg_pose_l'] += (target_leg_l - dancer['leg_pose_l']) * 0.15
        
        knee_l_x = hip_x - 0.025 + np.sin(dancer['leg_pose_l'] * 0.6) * leg_len_upper * 0.3
        knee_l_y = hip_y + np.cos(dancer['leg_pose_l'] * 0.6) * leg_len_upper
        
        # Lower leg/foot
        foot_l_x = knee_l_x + np.sin(dancer['leg_pose_l'] * 0.8) * leg_len_lower * 0.2
        foot_l_y = knee_l_y + leg_len_lower
        
        # Draw thigh
        for t_leg in np.linspace(0, 1, 14):
            lx = (hip_x - 0.025) + (knee_l_x - (hip_x - 0.025)) * t_leg
            ly = hip_y + (knee_l_y - hip_y) * t_leg
            canvas[((xx - lx)**2 + (yy - ly)**2) < 0.032**2] = 1.0
        
        # Draw shin
        for t_leg in np.linspace(0, 1, 14):
            lx = knee_l_x + (foot_l_x - knee_l_x) * t_leg
            ly = knee_l_y + (foot_l_y - knee_l_y) * t_leg
            canvas[((xx - lx)**2 + (yy - ly)**2) < 0.028**2] = 1.0
        
        # Right leg
        target_leg_r = -leg_move
        dancer['leg_pose_r'] += (target_leg_r - dancer['leg_pose_r']) * 0.15
        
        knee_r_x = hip_x + 0.025 + np.sin(dancer['leg_pose_r'] * 0.6) * leg_len_upper * 0.3
        knee_r_y = hip_y + np.cos(dancer['leg_pose_r'] * 0.6) * leg_len_upper
        
        foot_r_x = knee_r_x + np.sin(dancer['leg_pose_r'] * 0.8) * leg_len_lower * 0.2
        foot_r_y = knee_r_y + leg_len_lower
        
        for t_leg in np.linspace(0, 1, 14):
            lx = (hip_x + 0.025) + (knee_r_x - (hip_x + 0.025)) * t_leg
            ly = hip_y + (knee_r_y - hip_y) * t_leg
            canvas[((xx - lx)**2 + (yy - ly)**2) < 0.032**2] = 1.0
        
        for t_leg in np.linspace(0, 1, 14):
            lx = knee_r_x + (foot_r_x - knee_r_x) * t_leg
            ly = knee_r_y + (foot_r_y - knee_r_y) * t_leg
            canvas[((xx - lx)**2 + (yy - ly)**2) < 0.028**2] = 1.0
    
    # Soft glow around silhouettes (iPod aesthetic)
    if 'glow' not in state or state['glow'].shape != (h, w):
        state['glow'] = np.zeros((h, w), dtype=np.float64)
    
    state['glow'] *= 0.82
    state['glow'] = np.maximum(state['glow'], canvas * 0.6)
    
    # Subtle bloom
    bloom = canvas * (0.3 + audio.band_high * 0.2)
    
    # Combine layers
    final = bg + canvas * 0.7 + state['glow'] * 0.25 + bloom * 0.15
    
    # Very subtle floor reflection
    floor_y = 0.72
    for dy in range(h):
        y_val = dy / h
        if y_val > floor_y:
            reflect_y = int((floor_y - (y_val - floor_y)) * h)
            if 0 <= reflect_y < h:
                fade = np.maximum(0, 1.0 - (y_val - floor_y) * 5)
                final[dy, :] = np.maximum(final[dy, :], canvas[reflect_y, :] * 0.15 * fade)
    
    # Smooth color shift with music
    palette_shift = audio.centroid * 0.25 + np.sin(t * 0.1) * 0.15
    color_vals = np.clip(final + palette_shift, 0, 1)
    indices = (color_vals * 255).astype(int)
    fb[:] = lut[indices]
