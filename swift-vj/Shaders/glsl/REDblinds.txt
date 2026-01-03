#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float rand(vec2 p) 
{
	return fract(sin(dot(p.xy,vec2(1.9898,78.233)))*43758.5453);
}

void main( void ) {

	vec4 final = vec4(0,0,0,1);
	vec2 position = gl_FragCoord.xy / resolution.xy;
	float t = time*2.0;
	float width = 10.0;
	float distanceFromPoint = distance(position,vec2(0,0));
	if(floor(width*distanceFromPoint) == floor(width*distanceFromPoint-sin(t)))
	{
		final.x = abs(cos(t));
	}
	float distanceFromPoint2 = distance(position,vec2(1,0));
	if(floor(width*distanceFromPoint2) == floor(width*distanceFromPoint2-cos(t)))
	{
		final.x = abs(sin(t));
	}
	
	gl_FragColor = vec4(final);	
}