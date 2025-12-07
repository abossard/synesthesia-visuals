#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float speed;  // Audio-reactive speed 0-1

uniform float offset;
uniform float frequency;
uniform int curve;
uniform bool vertical;
uniform vec4 startColor;
uniform vec4 endColor;

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

const float pi = 3.14159265359;
const float e = 2.71828182846;



void main() {
	float mixAmount = 0.0;
	float phase = offset;
	
	if (vertical)	{
		mixAmount = phase + frequency * isf_FragNormCoord[1];
	}
	else	{
		mixAmount = phase + frequency * isf_FragNormCoord[0];
	}
	
	if (curve == 0)	{
		mixAmount = mod(2.0 * mixAmount,2.0);
		mixAmount = (mixAmount < 1.0) ? mixAmount : 1.0 - (mixAmount - floor(mixAmount));
	}
	else if (curve == 1)	{
		mixAmount = sin(mixAmount * pi * 2.0 - pi / 2.0) * 0.5 + 0.5;
	}
	else if (curve == 2)	{
		mixAmount = mod(2.0 * mixAmount, 2.0);
		mixAmount = (mixAmount < 1.0) ? mixAmount : 1.0 - (mixAmount - floor(mixAmount));
		mixAmount = pow(mixAmount, 2.0);
	}
	
	gl_FragColor = mix(startColor,endColor,mixAmount);
}
