#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float speed;  // Audio-reactive speed 0-1

uniform float size;
uniform float rotation;
uniform float angle;
uniform vec2 shift;
uniform vec4 xcolor;
uniform vec4 ycolor;
uniform vec4 background;

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

//	Basically just uses the same gradient as the Sine Warp Tile but uses the x/y values as the mix amounts for our colors


const float tau = 6.28318530718;


vec2 pattern() {
	float s = sin(tau * rotation * 0.5);
	float c = cos(tau * rotation * 0.5);
	vec2 tex = isf_FragNormCoord;
	float scale = 1.0 / max(size,0.001);
	vec2 point = vec2( c * tex.x - s * tex.y, s * tex.x + c * tex.y ) * scale;
	point = point - scale * shift / RENDERSIZE;
	//	do the sine distort
	point = 0.5 + 0.5 * vec2( sin(scale * point.x), sin(scale * point.y));
	
	//	now do a rotation
	vec2 center = vec2(0.5,0.5);
	float r = distance(center, point);
	float a = atan ((point.y-center.y),(point.x-center.x));
	
	s = sin(a + tau * angle);
	c = cos(a + tau * angle);
	
	float zoom = max(abs(s),abs(c))*RENDERSIZE.x / RENDERSIZE.y;
	
	point.x = (r * c)/zoom + 0.5;
	point.y = (r * s)/zoom + 0.5;

	return point;
}


void main() {

	vec2 pat = pattern();

	gl_FragColor = background + pat.x * xcolor + pat.y * ycolor;
}
