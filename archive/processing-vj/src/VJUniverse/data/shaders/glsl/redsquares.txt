//Coded by T_S/RTX1911
//@T_SRTX1911 @rtx1911
//REAL TiME XPRESS "RTX1911" demo divsion
//Best view in 1
#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

vec3 gcol(vec2 p, float ang, float k) {
	float sync;
	p = vec2(
		p.x * cos(ang) - p.y * sin(ang),
		p.x * sin(ang) + p.y * cos(ang));	
	if(sin(time * 0.25) > 0.0){
		sync = sin(k * 0.25) + 1.0;
	}else{
		sync = -sin(k * 0.25) + 1.0;
	}
	vec3 col = vec3(mod(floor(p.x * 10.0) + floor(p.y * 10.0), sync), 0.0, 0.0);
	col *= mod(gl_FragCoord.y, 2.0) + sin(gl_FragCoord.y * 0.05 + (k * 5.0)) * 0.125;
	col *= mod(gl_FragCoord.x, 2.0);
	return col;
}
	
void main( void ) {
	vec2 aspect = vec2(resolution.x / resolution.y, 1.0);
	vec2 p = ( gl_FragCoord.xy / resolution.xy ) * aspect;
	p = vec2(p.x += cos(time * 0.07) * 2.3, p.y -= sin(time * 0.03) * 0.7);
	vec3  col = gcol(p * sin(time * 0.1), time * 0.3, time);
	gl_FragColor = vec4( col, 1.0 );
}