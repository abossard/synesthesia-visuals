#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float bass;
uniform float mid;
uniform float treble;
uniform float level;
uniform float beat;

uniform float scale;
uniform float cycle;
uniform float thickness;
uniform float loops;
uniform float warp;
uniform float hue;
uniform float tint;
uniform float rate;
uniform bool invert;

#define TIME time
#define RENDERSIZE resolution
#define isf_FragNormCoord (gl_FragCoord.xy / resolution)
#define FRAMEINDEX int(time * 60.0)

////////////////////////////////////////////////////////////
// CandyWarp  by mojovideotech
//
// based on :  
// glslsandbox.com/e#38710.0
// Posted by Trisomie21
// modified by @hintz
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////




void main(void)
{
	float s = RENDERSIZE.y / scale;
	float radius = RENDERSIZE.x / cycle;
	float gap = s * (1.0 - thickness);
	vec2 pos = gl_FragCoord.xy - RENDERSIZE.xy * 0.5;
	float d = length(pos);
	float T = TIME * rate;
	d += warp * (sin(pos.y * 0.25 / s + T) * sin(pos.x * 0.25 / s + T * 0.5)) * s * 5.0;
	float v = mod(d + radius / (loops * 2.0), radius / loops);
	v = abs(v - radius / (loops * 2.0));
	v = clamp(v - gap, 0.0, 1.0);
	d /= radius - T;
	vec3 m = fract((d - 1.0) * vec3(loops * hue, -loops, loops * tint) * 0.5);
	if (invert) 	gl_FragColor = vec4(m / v, 1.0);
	else gl_FragColor = vec4(m * v, 1.0);
}
