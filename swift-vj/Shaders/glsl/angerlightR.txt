// A thingy. 
// By MK|C.

#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
uniform sampler2D backbuffer;

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec4 bbf(vec2 p)
{
	return texture2D(backbuffer, p);
}

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );

	
	float dist = sqrt( pow(mouse.x-position.x+.03*sin(40.0*position.y+ 5.0*time), 2.0) + pow(mouse.y-position.y+.03*sin(40.0*position.x+ 5.5*time), 2.0) );
	float light = 1.0 -( dist + 0.05*(-1.0+sin(0.5*time)) * 2.0*rand(position)-0.05*rand( vec2(position.y, time) ) ) * 5.0;
	float terrain = rand(position) ;
	float r = 0.8*terrain + max(light * 0.2, -.80);
	float g = 0.33*terrain + max(light * 0.70, -0.60);
	float b = 0.2*terrain + max(light * 0.50, -.90);
	
	
	vec3 color = vec3(r, g, b);

	gl_FragColor = mix(vec4( color, 1.0 ), bbf(position), 0.5);

}