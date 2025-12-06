#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 resolution;

void main(void){
	gl_FragColor=vec4(sin(length((gl_FragCoord.xy-resolution*.5)/resolution.y)*64.0-time)*.5+.5);
}