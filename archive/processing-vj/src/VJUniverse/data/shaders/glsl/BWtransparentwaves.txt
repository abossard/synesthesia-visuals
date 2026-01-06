#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
const float PI = 3.14159265359;

float circle(vec2 pos, float time, float height, float amplitude, float y){
	float waveX = sin(pos.x * PI + time) * amplitude * y;
	float waveY = waveX - pos.y - height * sin(time* 0.1);
	if (waveY < 0.0) {
		waveY *= -1.0;
		waveY = 2.0 - waveY;
	} else {
		//waveY = (2.0 - waveY);
	}
	waveY *= 0.5;
	return pow(waveY, 0.125);
}

void main( void ) {
	vec2 pos = (gl_FragCoord.xy / resolution) * 2.0 - vec2(1.0, 1.0);
	float y = cos(pos.y * PI * 0.5);
	vec3 color = vec3(1.0, 1.0, 1.0); 

	for (int i = 1; i < 10; i++) {
		float index = float(i) / 10.0;
		float sinus = circle(pos, time * 0.4 / index, 0.9 - 1.8 * index, index, y);
		//sinus = smoothstep(0.7, 1.0, sinus);
		color *= sinus;
	}
	
	color -= 0.5;
	color *= 2.0;
	color = abs(color);
	

	gl_FragColor = vec4(color, 1.0 );
}