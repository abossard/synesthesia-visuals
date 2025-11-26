// Cloud ray-march shader
// by Morgan McGuire, @CasualEffects, http://casual-effects.com


/** Computes the contribution of the clouds on [minDist, maxDist] along eyeRay towards net radiance 
    and composites it over background */
Radiance4 renderClouds(Ray eyeRay, float minDist, float maxDist, Color3 shadowedAtmosphere) {    
    const int    maxSteps = 80;
    const float  stepSize = 0.012;
    const Color3 cloudColor = Color3(0.95);
    const Radiance3 ambient = Color3(0.9, 1.0, 1.0);

    // The planet should shadow clouds on the "bottom"...but apply wrap shading to this term and add ambient
    float planetShadow = clamp(0.4 + dot(w_i, normalize(eyeRay.origin + eyeRay.direction * minDist)), 0.25, 1.0);

    Radiance4 result = Radiance4(0.0);
    
    // March towards the eye, since we wish to accumulate shading.
    float t = maxDist;
    for (int i = 0; i < maxSteps; ++i) {
        if (t > minDist) {
            Point3 X = ((eyeRay.direction * t + eyeRay.origin) - planetCenter) * (1.0 / planetMaxRadius);
            // Sample the clouds at X
            float density = cloudDensity(X, time);
            
            if (density > 0.0) {

                // Shade cloud
                // Use a directional derivative https://iquilezles.org/articles/derivative
                // for efficiency in computing a directional term             
                const float eps = stepSize;
                float wrapShading = clamp(-(cloudDensity(X + w_i * eps, time) - density) * (1.0 / eps), -1.0, 1.0) * 0.5 + 0.5;

                // Darken the portion of the cloud facing towards the planet
                float AO = pow8((dot(X, X) - 0.5) * 2.0);
                Radiance3 L_o = cloudColor * (B_i * planetShadow * wrapShading * mix(1.0, AO, 0.5) + ambient * AO);
                
                // Atmosphere tinting
		        L_o = mix(L_o, shadowedAtmosphere, min(0.5, square(max(0.0, 1.0 - X.z))));

                // Fade in at the elevation edges of the cloud layer (do this *after* using density for derivative)
                density *= square(1.0 - abs(2.0 * length(X - planetCenter) - (cloudMinRadius + planetMaxRadius)) * (1.0 / (planetMaxRadius - cloudMinRadius)));
                
                // Composite over result as premultiplied radiance
                result = mix(result, Radiance4(L_o, 1.0), density);
                
                // Step more slowly through empty space
	            t += stepSize * 2.0;
            } 
            
            t -= stepSize * 3.0;
        } else {
            return result;
        }
    }
    
    return result;
}


void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragColor = vec4(0.0);
    
    // Run at 1/3 resolution
    fragCoord.xy = (fragCoord.xy - 0.5) * 3.0 + 0.5;
    if ((fragCoord.x > iResolution.x) || (fragCoord.y > iResolution.y)) { return; }
    
    Ray eyeRay = Ray(Point3(0.0, 0.0, 5.0), normalize(Vector3(fragCoord.xy - iResolution.xy / 2.0, iResolution.y / (-2.0 * tan(verticalFieldOfView / 2.0)))));

    float minDistanceToPlanet, maxDistanceToPlanet;
    if (showClouds && intersectSphere(planetCenter, planetMaxRadius, eyeRay, minDistanceToPlanet, maxDistanceToPlanet)) {
        // This ray hits the cloud layer, so ray march the clouds
        
        // Find the hit point on the planet or back of cloud sphere and override
        // the analytic max distance with it.
    	maxDistanceToPlanet = texture(iChannel0, fragCoord.xy / iResolution.xy).a;
        
        Color3 shadowedAtmosphere = 1.1 * shadowedAtmosphereColor(fragCoord, iResolution, 0.08);
        fragColor = renderClouds(eyeRay, minDistanceToPlanet, maxDistanceToPlanet, shadowedAtmosphere);   
    }
}
