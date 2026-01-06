#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
uniform sampler2D backbuffer;

float random(vec2 v) 
{
return fract(sin(dot(v ,vec2(12.9898,8.233))) * (100.0+time*0.05));
}

void main( void ) 
{
	const int numColors = 4;
	vec3 colors[numColors];
	colors[0] = vec3( 78, 205, 196) / 255.0;
	colors[1] = vec3( 199, 244, 100) / 255.0;
	colors[2] = vec3( 85, 98, 112)/ 255.0;
	colors[3] = vec3( 250, 98, 20)/ 255.0;
	
	vec2 screenPos = gl_FragCoord.xy;
	vec2 screenPosNorm = gl_FragCoord.xy / resolution.xy;
	vec2 position = screenPosNorm + mouse / 4.0;
	vec4 prevColor = texture2D( backbuffer, screenPosNorm );
	
	
	// calc block
	vec2 screenBlock0 = floor(screenPos*0.25 + vec2(time,0) + mouse*1.0);
	vec2 screenBlock1 = floor(screenPos*0.20 + vec2(time*1.5,0) + mouse*5.0);
	vec2 screenBlock2 = floor(screenPos*0.03 + vec2(time*2.0,0)+mouse*10.0);
	float rand0 = random(screenBlock0);
	float rand1 = random(screenBlock1);
	float rand2 = random(screenBlock2);
	
	float rand = rand1;
	if ( rand2 < 0.05 ) { rand = rand2; }
	
	// block color
	vec3 color = mix( colors[0], colors[1], pow(rand,5.0) );
	if ( rand < 0.05 ) { color=colors[2]; }
	if ( rand < 0.03 ) { color=colors[3]; }
	
	
	
	
	float vignette = 1.6-length(screenPosNorm*2.0-1.0);
	vec4 finalColor = vec4(color*vignette, 1.0);
	
	//gl_FragColor = finalColor;
	gl_FragColor = mix(prevColor, finalColor, sin( sin(screenPos.x)+cos(screenPos.y) +time*10.0)*0.5+0.5);
	
	if( rand==rand2) { gl_FragColor = finalColor;}

}