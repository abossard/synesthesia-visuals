#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float speed;  // Audio-reactive speed 0-1

uniform vec2 offset;
uniform float rate;

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

// LiquidFire by mojovideotech
// based on :
// glslsandbox.com/e#29962.1
// by @301z

#ifdef GL_ES
precision mediump float;
#endif

float rnd(vec2 n) 
{ 
	return fract(cos(dot(n, vec2(5.14229, 433.494437))) * 2971.215073);
}

float noise(vec2 n) 
{
	const vec2 d = vec2(0.0, 1.0);
	vec2 b = floor(n), f = smoothstep(vec2(0.0), vec2(1.0), fract(n));
	return mix(mix(rnd(b), rnd(b + d.yx), f.x), mix(rnd(b + d.xy), rnd(b + d.yy), f.x), f.y);
}

float fbm(vec2 n) {
	float total = 0.0, amplitude = 1.0;
	for (int i = 0; i < 6; i++) 
	{
		total += noise(n) * amplitude;
		n += n;
		amplitude *= 0.6;
	}
	return total;
}

void main() 
{
	vec3 uv = vec3(RENDERSIZE.x,RENDERSIZE.y,100.);
	vec2 p = isf_FragCoord.xy * 8.0 / uv.xx;
	float T = TIME*rate;
	const vec3 c1 = vec3(0.2, 0.3, 0.1); 
	const vec3 c2 = vec3(0.9, 0.1, 0.0);
	const vec3 c3 = vec3(0.2, 0.0, 0.0); 
	const vec3 c4 = vec3(1.0, 0.9, 0.0); 
	const vec3 c5 = vec3(0.1);
	const vec3 c6 = vec3(0.9);
	float q = fbm(p - T * 0.25); 
	vec2 r = vec2(fbm(p + q + log2(T * 0.618) - p.x - p.y), fbm(p + q - abs(log2(T * 3.142))));
	vec3 c = mix(c1, c2, fbm(p + r-offset.x)) + mix(c3, c4, r.x) - mix(c5, c6, r.y);
	gl_FragColor = vec4(c * cos(1.0-offset.y * isf_FragCoord.y / uv.y),1.0);
}
