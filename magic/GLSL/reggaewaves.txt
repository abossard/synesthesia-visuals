#ifdef GL_ES
precision mediump float;
#endif

// fucking around with shaders
//      - Digitalis//Digitoxin

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

vec3 drawLines(vec2 pos, float vertWidth, vec3 col1, vec3 col2){
	if( mod(pos.y + sin(pos.x*7.0+time) + (cos(pos.x*time) * 0.05), vertWidth) < 0.3 ){
		return col1*pos.x;
	}
	return col2*pos.y;
}

void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy );

	vec3 color = drawLines(position, 0.7+sin(time)*0.1, vec3(1.0,0.0,0.0), vec3(0.0, 1.0, 0.0));

	gl_FragColor = vec4( color, 1.0);

}