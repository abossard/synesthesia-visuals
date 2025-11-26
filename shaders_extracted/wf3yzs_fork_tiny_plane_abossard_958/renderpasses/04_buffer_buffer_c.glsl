// Composite and temporal blur shader
// by Morgan McGuire, @CasualEffects, http://casual-effects.com

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    float mouseDeltaX = iMouse.x - texture(iChannel2, vec2(0, 0)).a; 
    
    // Increase blur constants when small because the screen-space derivatives
    // will be unstable at that scale. Both are on [0, 1]
    float hysteresis    = (abs(mouseDeltaX) > 1.0) ? 0.05 : 
        (iResolution.x > 800.0) ? 0.8 : 0.9;
    float spatialBlur   = (iResolution.x > 900.0) ? 0.70 : 0.90;

    vec2 invResolution = 1.0 / iResolution.xy;
    vec3 planet = texture(iChannel0, (fragCoord.xy + spatialBlur * 0.5) * invResolution).rgb;
    // Upsample clouds from 1/2 resolution
    vec4 clouds = texture(iChannel1, ((fragCoord.xy - 0.5) / 3.0 + 0.5) * invResolution);
    vec3 dst    = texture(iChannel2, fragCoord.xy * invResolution).rgb;
    
	// Hide clouds
   	// clouds = vec4(0.0); hysteresis = 0.0;
    
    if (! showPlanet) { planet *= 0.0; }
    
	fragColor.rgb = mix(planet * (1.0 - clouds.a) + clouds.rgb, dst, hysteresis);

    // Save the old mouse position. Most users only rotate horizontally, so save
    // a texture fetch on read by not storing the y component.
    fragColor.a   = iMouse.x;   
}

