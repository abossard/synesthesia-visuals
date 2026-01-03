#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// this is some WEIRD non-fractal scheisse!
void main( void ) 
{
	vec2 i,p = abs(( gl_FragCoord.xy / resolution.xy  * 2.0) - 1.0);
	
	vec2 pos = abs(( gl_FragCoord.xy / resolution.xy  * 2.0) - 1.0);
	
	
	
	float m = atan(sin(pos.x+time) * (sin(pos.y+time)));
	float k = dot(vec2(sin(pos.x+time),sin(pos.y+time)), pos);
	float y = atan(cos(time) + 0.5) * sin(pos.y*10.0+time*2.0);
	
	float z = atan(cos(time) + 0.5) * sin(pos.x*10.0+time*2.0) * (pos.x*time) + (pos.y*time + 0.5);
	
	
	
	gl_FragColor = vec4(z*m*k,m*y*z,m*k,m*k*z);
}