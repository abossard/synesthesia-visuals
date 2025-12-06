#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float fps1 = 24.0; //left
float fps2 = 48.0; //middle
float fps3 = 60.0; //right
float speed = 20.0; // 1 - 100 makes sense
float radius = 50.0; // px
float grid = 25.0;

vec2 pos( float move, float fps ){
	float steptime = floor(time * fps) / fps * speed / 10.0;
	vec2 s = vec2( sin(steptime) / 7.0 + 0.5 + move * ( radius * 4.0 / resolution.x ), cos(steptime) / 3.0 + 0.5 );
	return s * resolution;
}
void main( void ) {
	vec3 blueprint = vec3( 30.0 / 255.0, 144.0 / 255.0, 255.0 / 255.0 );
	vec3 white = vec3( 1.0, 1.0, 1.0 );
	vec4 color = vec4( blueprint, 1.0 );
	float dist1 = dot( gl_FragCoord.xy - pos(-1.0,fps1), gl_FragCoord.xy - pos(-1.0, fps1) );
	float dist2 = dot( gl_FragCoord.xy - pos(0.0,fps2), gl_FragCoord.xy - pos(0.0, fps2) );
	float dist3 = dot( gl_FragCoord.xy - pos(1.0,fps3), gl_FragCoord.xy - pos(1.0, fps3) );
	if( mod( gl_FragCoord.x, grid ) == grid - 0.5 || mod( gl_FragCoord.y, grid ) == grid - 0.5 )
		color = vec4( blueprint + 0.2 , 1.0 );
	radius *= radius;
	if( dist1 < radius || dist2 < radius || dist3 < radius ) 
		color = vec4( 1.0 );
	gl_FragColor = color;

}