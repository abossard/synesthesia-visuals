float rand(float n){return fract(sin(n) * 43758.5453123);}
float sizeMod = mix(1.0, 0.5+(sin(_uvc.x*3.0+TIME*0.1)*_uv.y+cos(_uvc.x*4.7-TIME*0.47)+cos(_uvc.x*11.0+TIME*0.89)*(1.0-_uv.y))/4.0, 1.0);
vec2 flowVec = vec2(sin(syn_Time*PI*0.09+0.894*(syn_BassPresence))*0.5 + 0.5,sin(syn_HighTime*PI*0.03+0.72*(syn_HighPresence))*0.5 + 0.5);
vec2 d  = _xy - flowVec*RENDERSIZE.xy;
float m = exp(-length(d) / (50.0 * syn_FadeInOut + 5));
float useMedia =  use_media_col + blend_media;
float sg (vec2 p, vec2 a, vec2 b) {
    float i = clamp(dot(p-a,b-a)/dot(b-a,b-a),0.,1.);
	return (length(p-a-(b-a)*i));
}
float noise( vec2 co ){
    return fract( sin( dot( co.xy, vec2( 12.9898, 78.233 ) ) ) * 43758.5453 );
}
vec3 threeColMix(vec3 col1, vec3 col2, vec3 col3, float mixVal){
    mixVal = smoothstep(0.0, 1.0, mixVal);
    mixVal *= 2.0;
    float mix1 = clamp(mixVal,0.0,1.0);
    float mix2 = clamp(mixVal-1.0, 0.0, 1.0);
    return mix(mix(col1, col2, mix1), mix(col2, col3, mix2), step(1.0, mixVal));
}
vec2 normz(vec2 x) {
	return x == vec2(0.0, 0.0) ? vec2(0.0, 0.0) : normalize(x);
}
float nsin(float val) {
    return 0.5 + 0.5*sin(val);
}
float ncos(float val) {
    return 0.5 + 0.5*cos(val);
}
vec3 getCirclePulse() {
    float uvShifter = reactive_generator_uv;
    float timeVar = script_bass_time*0.07;
    vec2 uv = vec2(sin(_uvc.x), sin(_uvc.y));
    uv = vec2(uv.x + (sin(jump_position + uv.x) + uvShifter*uv.x*sin(timeVar*1.1)*0.6), uv.y);
    float pulseSize = 0.03 + script_intensity_pulser*0.12;
    return vec3(
        _pulse(_fbm(length(uv)), nsin(timeVar), pulseSize - 0.01) + 
        _pulse(_fbm(length(uv*5.3) + 20.), nsin(timeVar - 50.), pulseSize) + 
        _pulse(_noise(length(uv*5.)), nsin(timeVar + 150), pulseSize + 0.01) -
        _pulse(_noise(length(uv*2.)), ncos(timeVar*0.5+ 100.), pulseSize)
    );
}
vec3 getHorizontalJumpers(vec2 offset) {
    vec3 jumpers = vec3(0.);
        float uvShifter = reactive_generator_uv;
    float timeVar = script_bass_time*0.1;
    vec2 uv = vec2(sin(_uvc.x - offset.x), sin(_uvc.y + 0.5 - offset.y));
    uv = vec2(uv.x + (sin(jump_position + uv.x) + uvShifter*uv.x*sin(timeVar*1.5)*0.6), uv.y);
    
    uv.y = _pixelate(uv.y, floor(RENDERSIZE.y/50.) - 10.*step(0.6, 10.*sin(uv.x - syn_Time*0.1)));
    
    uv.x = mix(uv.x, 1.0 - uv.x, smoothstep(0.11, 0.9 - 0.3*script_intensity_pulser, nsin(uv.y*5. - syn_Time*0.1))- smoothstep(nsin(syn_BassTime*0.05 + uv.x*3. + syn_MidHighPresence)*0.2, 0.3 + 0.45*ncos(syn_BassTime*0.08 - uv.y*4.), nsin(uv.x*4. + syn_Time*0.1)));
    vec2 backupUv = uv;
    
    jumpers = vec3(_pulse(uv.x, nsin(TIME*0.1 + syn_MidHighTime*0.3), 0.03 + script_intensity_pulser*0.12));
    
    uv.y = _pixelate(uv.y, floor(RENDERSIZE.y/90.) + 10.*step(0.3, 10.*sin(uv.x + 10. - syn_Time*0.1)));
    uv.x = mix(uv.x, uv.x*2. - 1.,  clamp(nsin(syn_HighTime*0.3 + 100. + uv.x)-ncos(syn_BassTime*0.1*PI+200. - uv.y*3.), 0.0, 1.0));
    
    jumpers += vec3(_pulse(uv.x, nsin(TIME*0.1 + syn_MidHighTime*0.3 + syn_Time*0.11), 0.02 + script_intensity_pulser*0.12));
    jumpers += vec3(_pulse(backupUv.x - uv.x, nsin(TIME*0.1 + syn_MidHighTime*0.3 + syn_Time*0.11 + backupUv.x*2.), 0.04 + script_intensity_pulser*0.13));
    
    return jumpers;
}
vec3 getParticles() {
	vec2 fragCoord = _xy;
	float uvShifter = reactive_generator_uv;
	float timeVar = script_bass_time*0.13;
    float u_brightness = 0.22 + syn_Presence*0.25 + script_intensity_pulser;
    const float u_blobiness = 1.2;
    const float u_particles = 120.0;
    const float u_limit = 70.0;
    const float u_energy = 1.0 * 0.75;
    vec2 position = ( fragCoord.xy  / RENDERSIZE.x );
    position = mix(position, position - vec2( 0.35*(sin(position.x*0.1) + sin(position.x*0.1 + timeVar*1.5)*0.16), 0.0) - vec2(2.*cos(timeVar*0.3 + position.x*3.), sin(timeVar*0.05 + syn_BPMTwitcher*0.04)*0.07), uvShifter);
    float t = syn_Time*0.25 * u_energy + 500.;
    float a = 0.0;
    float b = 0.0;
    float c = 0.0;
    vec2 pos;
    vec2 center = vec2(_uvc.x + 0.5, _uvc.y + 0.25);
    float na, nb, nc, nd, d;
    float limit = u_particles / u_limit;
    float u_step = 1.0 / u_particles;
    float n = 0.0;
    for ( float i = 0.0; i <= 1.0; i += 0.06 ) {

            vec2 np = vec2(n, 1-1);
            na = _fbm( np * 1.1 );
            nb = _noise( np * 2.8 );
            nc = _fbm( np * 0.7 );
            nd = _noise( np * 3.2 );
            pos = center;
            pos.x += sin(t*na) * cos(t*nb) * tan(t*na*0.15) * 0.3;
            pos.y += tan(t*nc) * sin(t*nd) * 0.3;
            d = pow( 1.6*na / length( pos - position ), u_blobiness );
            // if ( i < limit * 0.3333 ) a += d;
            a += d;
            // else if ( i < limit * 0.5 ) b += d;
            b += d;
            n += u_step;
    }
    //blue only
    vec3 col = vec3(a*25.5,0.0 + a*15+b*21,a*b) * 0.0003 * u_brightness;
    return col;
}
vec4 renderBuffA() {
    vec4 fragColor = vec4(0.0);
    vec4 texColor = vec4(0.0);
	if(_exists(syn_UserImage)  ) {
		texColor = texture(BuffB, _uv);
	}
    vec2 offs = vec2(0.0);
    float colr = texColor.r;
	float colg = texColor.g;
    float colb = texColor.b;
	float mediaLuma = dot(texColor.rgb, vec3(1.))/3.;
	fragColor = texColor;
	
	return fragColor;
}
//load user image or create particles to feed the system
vec4 renderBuffB() {
    vec4 fragColor = vec4(0.0);
    vec2 texel = 1.0/RENDERSIZE;
    float renderRatio = (RENDERSIZE.x/RENDERSIZE.y);
    vec4 texColor = vec4(0.);
    vec4 mediaCol = vec4(0.0);
    vec3 particles = getParticles()*0.9;
    particles = smoothstep(0.0, 0.95, particles);
    vec4 particlesCol = vec4(particles, dot(particles, vec3(1.))/3.);
    vec3 circlePulse = getCirclePulse();
    vec4 circlesCol = vec4(circlePulse*0.95, circlePulse.r);
    vec3 horizontalJumpers = getHorizontalJumpers(vec2(0.));
    vec4 jumpersCol = vec4(horizontalJumpers*0.8, horizontalJumpers.r);
    
    //Auto generators
    texColor = mix(texColor, particlesCol, clamp(auto_generator, 0.0, 1.0));
    texColor = mix(texColor, circlesCol, clamp(auto_generator-1., 0.0, 1.0));
    texColor = mix(texColor, jumpersCol, clamp(auto_generator -2., 0.0, 1.0));
	if(_exists(syn_UserImage)) {
	    vec4 feedbackField = texture(BuffC, _uv);
        float mediaPulse = _pulse(length(_uvc), -0.1+(1.0-media_pulse)*2.0, 0.15+length(feedbackField.xy)*2.5);
        vec2 mediaPulser = mix(vec2(0.), vec2(-0.15)+ 0.45*mediaPulse, mediaPulse);
        mediaCol = _loadUserImage(mediaPulser);
	    texColor  = mix(texColor, mediaCol, clamp(auto_generator-3., 0.0, 1.0));
	}
	
	//pulse generators
	texColor += particlesCol*scriptParticlePulse*1.5;
	texColor += circlesCol*scriptCirclesPulse*1.5;
	texColor += jumpersCol*scriptJumpersPulse*1.5;
	texColor += mediaCol*scriptMediaPulse*1.0;
	
	fragColor = texColor;
	return fragColor;
}
vec4 field(sampler2D buff, vec2 position) {
    vec4 fragColor = vec4(0.);
    
    position += vec2(smoothstep(0.2, 0.8, _fbm(length(_uvc)))  + _rotate(vec2(0.0,-1.0+2.0), pow(_fbm(_uvc*2.),2.0)*10.*PI))*turbulence2;
    vec2 velocityGuess = texture(buff, position/RENDERSIZE.xy).xy;
    position += _uvc*2. * scatter_field*scatter_field;
    vec2 positionGuess = position - velocityGuess;
    positionGuess += vec2(cos(PI*length(_uvc)*5.+ syn_BassTime*0.1) - sin(syn_HighTime*0.2 + _uvc.x*5.), sin((12. + 4.*sin(length(position/RENDERSIZE.xy)*6. + 50. + TIME*0.1 + syn_BassTime*0.14)) ))*turbulence*0.5;
    fragColor = texture(buff, (positionGuess/RENDERSIZE.xy));
    return fragColor;
}
//advect difference between current frame and last frame
vec4 renderBuffC() {
    vec4 fragColor =vec4(0.);
    vec4 u = vec4(0.0);
    float lookupDist = 1.0 - (audio_react*0.75) + pow(feedback_strength, 2.) + audio_react*(syn_HighHits + syn_Intensity);
    //get neighbors
    vec2 n = vec2(0.0, lookupDist);
    vec2 e = vec2(lookupDist, 0.0);
    vec2 s = vec2(0.0, -lookupDist);
    vec2 w = vec2(-lookupDist, 0.0);
    vec2 ne = vec2(lookupDist, lookupDist);
    vec2 nw = vec2(-lookupDist, lookupDist);
    vec2 se = vec2(lookupDist, -lookupDist);
    vec2 sw = vec2(-lookupDist, -lookupDist);
    u = field(BuffD, _xy);
    vec4 pos_n = field(BuffD, _xy + n);
    vec4 pos_e = field(BuffD, _xy + e);
    vec4 pos_w = field(BuffD, _xy + w);
    vec4 pos_s = field(BuffD, _xy + s);
    // vec4 pos_nw = field(BuffD, _xy + nw);
    // vec4 pos_ne = field(BuffD, _xy + ne);
    // vec4 pos_sw = field(BuffD, _xy + sw);
    // vec4 pos_se = field(BuffD, _xy + se);
    // float neighborhood = (pos_n.z + pos_e.z + pos_w.z + pos_s.z + pos_nw.z + pos_ne.z + pos_sw.z + pos_se.z)/8.;
    float neighborhood = (pos_n.z + pos_e.z + pos_w.z + pos_s.z)/4.;
    u.z = neighborhood;
    
    vec2 force;
    force.x = pos_w.z - pos_e.z;
    force.y = pos_s.z - pos_n.z;
    // force.xy += (pos_ne.z - pos_nw.z)*ripples*(1.0 - audio_react);
    // force.xy -= (pos_se.z - pos_sw.z)*ripples*(1.0 - audio_react);
    // force.xy += (pos_ne.z - pos_nw.z)*audio_react*sin(_uvc.x*0.5 + 5.+syn_BassTime*0.05*PI)*1.25;
    // force.xy += (pos_se.z - pos_sw.z)*audio_react*sin(length(_uvc) + 10. + TIME*0.05*PI)*1.25;
    u.xy += force/4.0;
    u.x += scatter_field*1.25*sin(_uvc.x*2.*PI)*u.x;
    u.y += scatter_field*1.75*sin(_uvc.y*3.*2.*PI)*u.y;
    u.z += (pos_w.x - pos_e.x + pos_s.y - pos_n.y)/4.0;
    u.z += scatter_field*0.3*sign(u.z);
    // Mass conservation :
    // u.w += (pos_w.x*pos_w.w-pos_e.x*pos_e.w+pos_s.y*pos_s.w-pos_n.y*pos_n.w)/8.;
    u.w += (pos_w.x*pos_w.w-pos_e.x*pos_e.w+pos_s.y*pos_s.w-pos_n.y*pos_n.w)/4.;
    // u.w = mix(u.w, u.w*0.996, ripples*feedback_strength);
    
    vec4 currentFrame = texture(BuffB, _uv);
	float mediaLuma = dot(currentFrame.rgb, vec3(1.))/3.;
	//audio reactive feedback
    u.z = mix(u.z*(0.997-0.011*(1.0-syn_HighHits)*(1.0-feedback_strength)), u.z*0.85 + u.z*0.14*syn_HighHits, audio_react);
    u.w = mix(u.w*(0.997-0.011*(1.0-syn_HighHits)*(1.0-feedback_strength)), u.w*0.97 + u.w*0.03*syn_Presence, audio_react);
    u.z = mix(u.z, u.z*0.996, turbulence);
    u.w = mix(u.w, u.w*0.996, turbulence);
    //mix the media based on luma
    if (mediaLuma > feedback_threshold) {
        u.w = mediaLuma*3. ;
        u.z = u.z*0.1 + mediaLuma*0.7;
    }
    
    if (feedback_reset > 0.5) {
        u.w = 0;
    }
    
    u.z = mix(u.z,_pixelate(u.z, 2.), pixelate_feedback);
    
    fragColor = u;
    return fragColor;
}
vec3 getPalette1(float depth) {
    return _palette(depth + color_pulse, vec3(0.500, 0.408, 0.669), vec3(0.500, 0.500, 0.623), vec3(0.500, 0.250, 0.992), vec3(0.523, 0.500, 0.477));
}
vec3 getPalette2(float depth) {
    return _palette(depth + color_pulse, vec3(0.146, 0.285, 0.254), vec3(0.800, 0.708, 0.723), vec3(1.308, 0.873, 0.681), vec3(0.638, 0.331, 0.531));
}
vec3 getPalette3(float depth) {
    return _palette(depth + color_pulse,  vec3(-0.004, -0.013, 0.644), vec3(1.000, 1.000, 0.702), vec3(0.879, 0.946, 0.915), vec3(0.438, 0.446, 0.654));
}
vec3 getPalette4(float depth) {
    return _palette(depth + color_pulse, vec3(0.583, -0.086, -0.234), vec3(0.626, 0.859, 0.677), vec3(0.721, 0.929, 0.404), vec3(0.448, 0.275, 0.793));
}
vec4 finalBuffer() {
	vec4 fragColor = vec4(0.0);
    vec2 uv = _uv;
    // vec4 texColor = vec4(0.0);
    vec4 feedbackField = texture(BuffC, _uv);
    vec4 generatorField = texture(BuffB, _uv);
    
	float mediaLuma = dot(generatorField.rgb, vec3(1.))/3.;
	fragColor = generatorField;
    feedbackField.w =  feedbackField.w + smoothstep(0.0, 1.0, mediaLuma*1.2 + 0.3)*1.5;
    
    //remap our feedback velocity for easier color lookups
    feedbackField.w = clamp(feedbackField.w, 0.0, 5.5) + 0.5*smoothstep(6.0, 7.0, feedbackField.w);
    feedbackField.z = clamp(feedbackField.z, 0.0, 5.5) + 0.5*smoothstep(6.0, 7.0, feedbackField.z);
    //////color schemes 
    vec3 paletteCol = vec3(0.);
    vec3 palette1 = getPalette1(clamp(pow(feedbackField.w*0.5 + length(feedbackField.xy)*0.25,2), 0.0, 2.1));
    vec3 paletteHigh1 = threeColMix(vec3(0.), vec3(_rotate(palette1.rg, syn_HighPresence*20.), palette1.b), pow(palette1, vec3(1.3)), smoothstep(0.15, 2.0, length(feedbackField.xy)) );
    vec3 paletteBass1 = threeColMix(vec3(0.), palette1 *vec3(1.1, 0.96, 0.33), vec3(palette1.r*0.3, palette1.g, pow(palette1, vec3(1.1))),  fract(feedbackField.z)*2.);
    vec3 palette2 = _palette(smoothstep(0.0, 1.0, feedbackField.z/3. + feedbackField.w/3.), vec3(0.146, 0.285, 0.254), vec3(0.800, 0.708, 0.723), vec3(1.308, 0.873, 0.681), vec3(0.638, 0.331, 0.531));
    vec3 palette3 = _palette(smoothstep(0.0,1.0,pow(feedbackField.w + feedbackField.z, 0.5)),  vec3(-0.004, -0.013, 0.644), vec3(1.000, 1.000, 0.702), vec3(0.879, 0.946, 0.915), vec3(0.438, 0.446, 0.654));
    vec3 palette4 = _palette(smoothstep(0.0, 1.0, feedbackField.w*0.7 + pow(feedbackField.z*0.5,2.)*0.05), vec3(0.583, -0.086, -0.234), vec3(0.626, 0.859, 0.677), vec3(0.721, 0.929, 0.404), vec3(0.448, 0.275, 0.793));
    
    vec2 zoneMids = vec2(sin(syn_MidTime*0.23), cos(syn_MidTime*0.17));
    vec2 zoneMidHighs = vec2(sin(syn_MidHighTime*0.23), cos(syn_MidHighTime*0.17));
    vec2 zoneHighs = vec2(sin(syn_HighTime*0.23), cos(syn_HighTime*0.17));
    
        vec3 midHighCol = getPalette1(smoothstep(0.5, 1.4, pow(feedbackField.w*0.5,3)*1.1));
    vec3 bassCol1 = getPalette1(smoothstep(0.0, 0.4, length(feedbackField.xy)*0.25));
    vec3 highCol1 = getPalette1(smoothstep(0.5, 1.1, feedbackField.z*feedbackField.w + sqrt(feedbackField.z)+0.2));
    vec3 bassCol2 = getPalette1(smoothstep(1.1, 1.3, (1.0 - feedbackField.w*0.7)*distance(feedbackField.xy, _uvc)));
    vec3 highCol2 = getPalette1(smoothstep(1.5, 2.1, feedbackField.w - feedbackField.z));
    vec3 midCol = getPalette1(clamp(pow(feedbackField.w*0.5 + length(feedbackField.xy)*0.25,2), 0.0, 2.1));
    float colMixer = palette;
    float cm = smoothstep(0.05,0.95,clamp(colMixer, 0.0, 1.0));
    
    midHighCol = mix(midHighCol, getPalette2(smoothstep(0.5, 1.4, pow(feedbackField.w*0.5,3))), cm);
    bassCol1 = mix(bassCol1, getPalette2(smoothstep(0.0, 0.4, length(feedbackField.xy)*0.25)), cm);
    highCol1 = mix(highCol1, getPalette2(smoothstep(0.5, 1.1, feedbackField.z*feedbackField.w + sqrt(feedbackField.z)*2.)), cm);
    bassCol2 = mix(bassCol2, getPalette2(smoothstep(1.1, 1.3, (1.0 - feedbackField.w*0.7)*distance(feedbackField.xy, _uvc))), cm);
    highCol2 = mix(highCol2, getPalette2(smoothstep(1.5, 2.1, feedbackField.w - feedbackField.z)), cm);
    midCol = mix(midCol, getPalette2(smoothstep(0.0, 1.0, feedbackField.z/3. + feedbackField.w/3.)), cm);
    
    colMixer = colMixer-1.0;
    cm = smoothstep(0.05,0.95,clamp(colMixer, 0.0, 1.0));
    
    midHighCol = mix(midHighCol, getPalette3(smoothstep(0.5, 1.1, pow(feedbackField.w*0.5,3))), cm);
    bassCol1 = mix(bassCol1, getPalette3(smoothstep(0.0, 0.4, length(feedbackField.xy)*0.25)), cm);
    highCol1 = mix(highCol1, getPalette3(smoothstep(0.5, 1.1, feedbackField.z*feedbackField.w + sqrt(feedbackField.z))), cm);
    bassCol2 = mix(bassCol2, getPalette3(smoothstep(1.1, 1.7, (1.0 - feedbackField.w*0.7)*distance(feedbackField.xy, _uvc))), cm);
    highCol2 = mix(highCol2, getPalette3(smoothstep(1.5, 2.1, feedbackField.w - feedbackField.z)), cm);
    midCol = mix(midCol, getPalette3(smoothstep(0.0,1.0,pow(feedbackField.w + feedbackField.z, 0.5))), cm);
    
    colMixer = colMixer-1.0;
    cm = smoothstep(0.05,0.95,clamp(colMixer, 0.0, 1.0));
    
    midHighCol = mix(midHighCol, getPalette4(smoothstep(0.5, 1.4, pow(feedbackField.w*0.5,3))), cm);
    bassCol1 = mix(bassCol1, getPalette4(smoothstep(0.0, 0.4, length(feedbackField.xy)*0.25)), cm);
    highCol1 = mix(highCol1, getPalette4(smoothstep(0.5, 1.1, feedbackField.z*feedbackField.w + sqrt(feedbackField.z))), cm);
    bassCol2 = mix(bassCol2, getPalette4(smoothstep(1.1, 1.3, (1.0 - feedbackField.w*0.7)*distance(feedbackField.xy, _uvc))), cm);
    highCol2 = mix(highCol2, getPalette4(smoothstep(1.5, 2.1, feedbackField.w - feedbackField.z)), cm);
    midCol = mix(midCol, getPalette4(smoothstep(0.0, 1.0, feedbackField.w*0.9 + pow(feedbackField.z,2.)*0.05 - dot(feedbackField.xy, _uvc)*0.5)), cm);
    
    midHighCol *= (0.2+0.95*syn_MidHighPresence*distance(zoneMidHighs, _uvc)*0.8);
    bassCol1 *= (0.2+0.8*(sqrt(syn_BassPresence))*1.25);
    highCol1 *= (0.2+0.8*sqrt(syn_HighPresence));
    bassCol2 *= (0.2+0.8*sqrt(syn_BassPresence)*1.5);
    highCol2 *= (0.2+0.8*(0.5 + 0.5*sin(syn_HighTime*0.2))*(0.5+syn_Presence*0.5)*distance(zoneHighs, _uvc));
    midCol *= (0.2+0.8*distance(zoneMids, _uvc)*sqrt(syn_MidPresence));
    
    paletteCol += midCol;
    
        paletteCol = mix(paletteCol, bassCol1, sqrt(feedbackField.w)-0.5);
    paletteCol = mix(paletteCol, highCol1, 0.75 - clamp(length(feedbackField.xy), 0.0, 0.75));
       paletteCol = mix(paletteCol, midHighCol, 0.5+0.5*cos(_uvc.y + dot(feedbackField.xy, vec2(1.)*0.5+sin(feedbackField.w))) );
    paletteCol = mix(paletteCol, bassCol2, clamp(_uvc.x*sin(syn_Time*0.1) -0.25 +feedbackField.w/4., 0., 0.8) );
    paletteCol = mix(paletteCol, highCol2, pow(feedbackField.w*0.5, 2.)*0.5 );
 
    paletteCol = min(paletteCol, vec3(1.1));
    
    
    float pulseUV = dot(_rotate(_uvc.xy, 5*sin(syn_Time*0.2)), vec2(0.3 + 0.7*(0.5+0.5*sin(syn_BassTime*0.2))));
    float pulser = pulse_rotating_sweeper + auto_pulse_sweeper*(syn_BPMSin4*0.8);
    
    //fine tune color values
    // paletteCol = _gamma(vec4(paletteCol, 1.), 0.8).rgb;
    paletteCol = _rgb2hsv(paletteCol);
    
    paletteCol.b = smoothstep(0.0, 1.1, paletteCol.b);
    paletteCol.r = paletteCol.r - skew_color*0.3;
    
    paletteCol = _hsv2rgb(paletteCol);
    
    vec4 temp = vec4(0.);
    
    if(_exists(syn_UserImage)) {
        float mediaPulse = _pulse(length(_uvc), -0.1+(1.0-media_pulse)*2.0, 0.03 + length(_uvc)-length(feedbackField.xy)*2.5)*media_pulse + length(_uvc)*0.2*liquify2*feedbackField.w*0.1 + nsin(_uvc.x*0.9 + syn_Time*0.1)*feedbackField.z*liquify2;
        
        vec2 mediaPulser = mix(vec2(0.), vec2(-0.15)+ 0.45*mediaPulse, mediaPulse);
        vec2 offset =  vec2(feedbackField.x*0.5 + clamp(feedbackField.w, 0.0, 1.0)*0.1, feedbackField.y*0.5 + feedbackField.z*0.5)*0.5*(0.7+syn_HighPresence*audio_react)*(pow(liquify, 2.5)*0.75);
        offset = mix(offset, vec2(feedbackField.xy + feedbackField.z)*(0.2 + 0.3*syn_Intensity)*media_corrosion, smoothstep( feedbackField.w - 0.75,  feedbackField.w-0.65, media_corrosion));
        offset += mediaPulser;
        
        vec4 imageFeedback = _loadUserImage(offset); //TODO: Add a pulse that shoots out from the center and adds to the liquify param <====== DO THIS NOW
       
        fragColor = mix(imageFeedback, fragColor, smoothstep(0.0, 1.0, mediaLuma*mediaLuma*1.9));
         
        fragColor = vec4(paletteCol, feedbackField.w ); 
        vec4 mediaMix = mix(imageFeedback, imageFeedback*min(vec4(1.0),pow(feedbackField.wwww*0.8,vec4(2.))), multiply_media);
        fragColor = mix(fragColor, mediaMix, use_media_col);
        float timeVar = script_high_time;
        //blend media by channel
        fragColor = mix(fragColor, imageFeedback, blend_media*nsin(timeVar*0.2 + 20. + 0.2*dot(imageFeedback, vec4(1.))/4. + uv.x + uv.y*0.25 + feedbackField.w ));
               
    } else {
        fragColor = vec4(paletteCol, clamp(feedbackField.w, 0.0, 1.0) );
    }
	return fragColor;
}
vec4 renderBuffD() {
    vec4 fragColor =vec4(0.);
    vec4 u = vec4(0.0);
    float lookupDist = 1.0 + pow(feedback_strength, 2.)*1.5 + audio_react*syn_BassHits*1.5;
    
    //get neighbors
    vec2 n = vec2(0.0, lookupDist);
    vec2 e = vec2(lookupDist, 0.0);
    vec2 s = vec2(0.0, -lookupDist);
    vec2 w = vec2(-lookupDist, 0.0);
    vec2 ne = vec2(lookupDist, lookupDist);
    vec2 nw = vec2(-lookupDist, lookupDist);
    vec2 se = vec2(lookupDist, -lookupDist);
    vec2 sw = vec2(-lookupDist, -lookupDist);
    u = field(BuffC, _xy);
    vec4 pos_n = field(BuffC, _xy + n);
    vec4 pos_e = field(BuffC, _xy + e);
    vec4 pos_w = field(BuffC, _xy + w);
    vec4 pos_s = field(BuffC, _xy + s);
    vec4 pos_nw = field(BuffC, _xy + nw);
    vec4 pos_ne = field(BuffC, _xy + ne);
    vec4 pos_sw = field(BuffC, _xy + sw);
    vec4 pos_se = field(BuffC, _xy + se);
    float neighborhood = (pos_n.z + pos_e.z + pos_w.z + pos_s.z + pos_nw.z + pos_ne.z + pos_sw.z + pos_se.z)/8.;
    // float neighborhood = (pos_n.z + pos_e.z + pos_w.z + pos_s.z)/4.;
    u.z = neighborhood;
    vec2 force;
    force.x = pos_w.z - pos_e.z;
    force.y = pos_s.z - pos_n.z;
    u.xy += force/4.0;
    u.z += (pos_w.x - pos_e.x + pos_s.y - pos_n.y)/4.0;
    // Mass conservation :
    u.w += (pos_w.x*pos_w.w-pos_e.x*pos_e.w+pos_s.y*pos_s.w-pos_n.y*pos_n.w)/8.;
    
    vec4 currentFrame = texture(BuffB, _uv);
	float mediaLuma = dot(currentFrame.rgb, vec3(1.))/3.;
	//audio reactive feedback
    u.z = mix(u.z*(0.997-0.009*(1.0-syn_HighHits)*(1.0-feedback_strength)), u.z*0.85 + u.z*0.14*syn_HighHits, audio_react);
    u.w = mix(u.w*(0.997-0.009*(1.0-syn_HighHits)*(1.0-feedback_strength)), u.w*0.97 + u.w*0.03*syn_Presence, audio_react);
    u.z = mix(u.z, u.z*0.999, turbulence);
    float pulseUV = dot(_rotate(_uvc.xy, 5*sin(syn_Time*0.2)), vec2(0.3 + 0.7*(0.5+0.5*sin(syn_BassTime*0.2))));
    float pulser = pulse_rotating_sweeper + auto_pulse_sweeper*(syn_BPMSin4*0.8);
    u.w += _sqPulse(pulseUV, sin(TIME)*pulser, 0.2)*pulser*1.1;
    //mix the media based on luma
    if (mediaLuma > feedback_threshold) {
        u.w = mediaLuma*(5.);
        u.z = u.z*0.1 + mediaLuma*1.1;
    }
    if (feedback_reset > 0.5) {
        u.w = 0;
    }
    u *= 0.997;
    
    
    fragColor = u;
    return fragColor;
}
vec4 renderMain(void) {
if (PASSINDEX == 0.0){
        //Generator & media loading
        return renderBuffB();
	} else if (PASSINDEX == 1.0){
        //diffuse pass
        return  renderBuffC();
   } else if (PASSINDEX == 2.0) {
        //diffuse pass
        return texture(BuffC, _uv);
        // return renderBuffD();
   } else if (PASSINDEX == 3.0) {
        //final coloring and render
        return finalBuffer();
   }
}
