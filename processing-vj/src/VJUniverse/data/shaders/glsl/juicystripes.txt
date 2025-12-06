#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 pos = -0.5 + ( gl_FragCoord.xy / resolution.xy ) * 5.1;// *mouse.x;
	
	float v = sin(pos.x+pos.y)+cos(pos.y*(1.0+pos.x)+sin(time/7.0))+ pos.x+pos.y + time/3.99999999;
	float a = mod((v), 0.2);
	//a = a-fract(a);
	//a = (mod(ceil(a),0.8)<0.01)?0.0:1.0;
		gl_FragColor = vec4(sin(a-pos.y-cos(time)), cos(a+pos.x*pos.y+time), sin(a+0.4*pos.x), 1.0 );
	
	//	gl_FragColor = vec4(a, a, a, 1.0 );
}