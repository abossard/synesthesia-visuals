#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float speed;  // Audio-reactive speed 0-1

uniform float scale;
uniform float rate;
uniform float loops;
uniform vec2 center;
uniform float freq1;
uniform float freq2;
uniform float seed1;
uniform float seed2;

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
// Blobscillator  by mojovideotech
//
// based on :
// shadertoy.com\/view\/MlKXWm  
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////

float hash (float a) { return floor(cos(a)*seed1+sin(a*seed2));  }

void main() {
	
    vec2 uv = (2.0 * isf_FragCoord.xy - RENDERSIZE.xy) / RENDERSIZE.y;	
    uv -= center.xy;
    uv *= 10.5-scale;
    float C = sin(TIME * rate) * freq1, dist = 0.0;												
    for(float i=10.0; i < 90.0; i++) {								
        float R = C + i;									
        vec2 N = vec2(sin(R), cos(R));				
        N *= abs(hash(R)) * freq2;							
        dist += sin(i + loops * distance(uv, N));				
    }
	gl_FragColor = vec4(vec3(dist),1.0);
}
