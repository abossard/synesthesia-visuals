// comment out the following line for original style
#define PAPER

// uncomment the following line for Mollweide projection
//#define ELLIPTICAL

#ifdef PAPER
#define  LOW_PRESSURE vec3(0.,0.5,1.)
#define HIGH_PRESSURE vec3(1.,0.5,0.)
#else
#define  LOW_PRESSURE vec3(1.,0.5,0.)
#define HIGH_PRESSURE vec3(0.,0.5,1.)
#endif

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
    float lat = 180. * fragCoord.y/iResolution.y - 90.;
#ifdef ELLIPTICAL
    fragCoord.x -= iResolution.x/2.;
    fragCoord.x /= sqrt(1. - pow(lat/90., 2.));
    if (abs(fragCoord.x/iResolution.x) > 0.5) return;
    fragCoord.x += iResolution.x/2.;
    fragCoord.x -= 0.05 * iTime * iResolution.x;
    fragCoord.x -= iMouse.x;
    fragCoord.x = mod(fragCoord.x, iResolution.x);
#endif
    vec2 p = fragCoord * MAPRES / iResolution.xy;
    if (p.x < 1.) p.x = 1.;
    vec2 uv = p / iResolution.xy;
    float land = texture(iChannel0, uv).x;
    fragColor = vec4(0,0,0,1);
    if (0.25 < land && land < 0.75) fragColor.rgb = vec3(0.5);
    float mbar = texture(iChannel1, uv + PASS3).x;
    if (iMouse.z > 0.) {
        vec3 r = LOW_PRESSURE;
        r = mix(r, vec3(0), smoothstep(1000., 1012., floor(mbar)));
        r = mix(r, HIGH_PRESSURE, smoothstep(1012., 1024., floor(mbar)));
        fragColor.rgb += 0.5 * r;
    } else {
        vec2 v = texture(iChannel1, uv + PASS4).xy;
        float flow = texture(iChannel2, fragCoord/iResolution.xy).z;
        vec3 hue = vec3(1.,0.75,0.5);
#ifndef PAPER
        hue = .6 + .6 * cos(atan(v.y,v.x) + vec3(0,23,21));
#endif
        float alpha = clamp(length(v), 0., 1.) * flow;
        fragColor.rgb = mix(fragColor.rgb, hue, alpha);
    }
#ifdef PAPER
    fragColor.rgb = 0.9 - 0.8 * fragColor.rgb;
    if (mod(fragCoord.x, floor(iResolution.x/36.)) < 1. ||
        mod(fragCoord.y, floor(iResolution.y/18.)) < 1.)
        fragColor.rgb = mix(fragColor.rgb, vec3(0.,0.5,1.), 0.2);
#endif
}
