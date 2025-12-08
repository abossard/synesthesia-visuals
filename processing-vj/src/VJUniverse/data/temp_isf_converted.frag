#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float speed;  // Audio-reactive speed 0-1

uniform float scale;
uniform float thickness;
uniform float twists;
uniform float rate;
uniform float gamma;

// Audio-reactive uniforms (injected by VJUniverse)
uniform float bass;       // Low frequency energy 0-1
uniform float lowMid;     // Low-mid energy 0-1
uniform float mid;        // Mid frequency energy 0-1
uniform float highs;      // High frequency energy 0-1
uniform float level;      // Overall loudness 0-1
uniform float kickEnv;    // Kick/beat envelope 0-1
uniform float kickPulse;  // 1 on kick, decays to 0
uniform float beat;       // Beat phase 0-1
uniform float energyFast; // Fast energy envelope
uniform float energySlow; // Slow energy envelope

#define TIME max(time, 0.001)
#define RENDERSIZE resolution
#define isf_FragCoord vec2(gl_FragCoord.x, resolution.y - gl_FragCoord.y)
#define isf_FragNormCoord (isf_FragCoord / resolution)
#define FRAMEINDEX int(time * 60.0)

////////////////////////////////////////////////////////////
// RainbowRingCubicTwist  by mojovideotech
//
// based on :
// glslsandbox/e#58416.0
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////


#ifdef GL_ES
precision highp float;
#endif


void main() 
{
    float T = TIME * rate;
    vec2 R = RENDERSIZE;  
    vec2 P = (isf_FragCoord.xy - 0.5*R)*(2.1 - scale);
    vec4 S, E, F;
    P = vec2(length(P) / R.y - 0.333, atan(P.y,P.x));  
    P *= vec2(2.6 - thickness,floor(twists));                                                                                                             ;
    S = 0.08*cos(1.5*vec4(0.0, 1.0, 2.0, 3.0) + T + P.y + sin(P.y)*cos(T));
    E = S.yzwx; 
    F = max(P.x - S, E - P.x);
    gl_FragColor = pow(dot(clamp(F*R.y, 0.0, 1.0), 72.0*(S - E))*(S - 0.1), vec4(gamma));
}
