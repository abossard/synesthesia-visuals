// by @neave
// Inspired by http://www.everyday3d.com/j3d/demo/011_Plasma.html

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

const vec3 col1 = vec3(.964705882, .890196078, .690196078);
const vec3 col2 = vec3(.666666667, .733333333, .431372549);
const vec3 col3 = vec3(.839215686, .380392157, .349019608);
const vec3 col4 = vec3(.576470588, .772549020, .729411765);
const vec3 col5 = vec3(.909803922, .592156863, .403921569);

void main( void ) {

	vec2 position = gl_FragCoord.xy / resolution.xy + mouse;
  	
	vec2 ca = vec2(0.1, 0.2);
	vec2 cb = vec2(0.7, 0.9);
	float da = distance(position, ca);
  	float db = distance(position, cb);
	
  	float t = time * 0.5;
	float c1 = sin(da * cos(t) * 16.0 + t * 4.0);
	float c2 = cos(position.y * 8.0 + t);
	float c3 = cos(db * 14.0) + sin(t);
	
	float p = (c1 + c2 + c3) / 3.0;
  	vec4 col = vec4(0, 0, 0, 1);
  	
  	if (p <= 0.0) col.rgb = col1;
  	else if (p < 0.2) col.rgb = col2;
  	else if (p < 0.3) col.rgb = col3;
  	else if (p < 0.4) col.rgb = col4;
  	else col.rgb = col5;
	
	gl_FragColor = col;
}