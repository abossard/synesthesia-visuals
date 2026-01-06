#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float distance(vec2 pos){
	float x = pos.x * 13.0 + time*1.0;
	float height = sin(x) / 5.0;
	
	float angle;
	angle = atan(1.0 / cos(x));

	return abs(height - pos.y) - 0.001 - abs(0.05*(cos(time*0.3)/2.0 + 0.0) / sin(angle*47.0));
}

void main( void ) {
	vec2 pos = gl_FragCoord.xy / resolution - vec2(0.5, 0.5);
	float dist = distance(pos);
	
	vec3 color = vec3(0.7,0.4 ,0.2);

	if(dist < 0.0){
		color *= log(-dist * (42.0 + abs(cos(time*0.3))*100.0 ));
	}else{
		color = vec3(0,0,0);
	}
	
	gl_FragColor = vec4(color, 1.3 );
}