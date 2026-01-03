#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
const float PI = 3.14159265359;

float circle(vec2 pos, float time, float height, float amplitude, float y){
	float wave = sin(pos.x * PI + time) * amplitude * y;
	return sqrt(sqrt(abs(wave - pos.y - height * sin(time* 0.1))));
}

vec3 ToneMapFilmicALU_HEJL(vec3 y)
{
    vec3 x = max(vec3(0.), y-vec3(0.004));          // approx linear segment
    return (y*(6.2*y+0.5))/(y*(6.2*y+1.7)+0.06);    // approx gamma(2.2) & filmic response
}

void main( void ) {
	vec2 pos = (gl_FragCoord.xy / resolution) * 2.0 - vec2(1.0, 1.0);
	float y = cos(pos.y * PI * 0.5);
	vec3 color = vec3(1.0, 1.0, 1.0); 
	//float sin1 = circle(pos, time, -0.5, 0.5, y);
	//float sin2 = circle(pos, time + 1.0, 0.5, 0.3, y);
	//float sin3 = circle(pos, time / 2.0, -0.9, 1.0, y);
		
	for (int i = 1; i < 10; i++) {
		float index = float(i) / 10.0;
		//index = 0.25;
		float sinus = circle(pos, time / index, 0.9 - 1.8 * index, index, y);
		color *= sinus;
	}
	
	color = 1.0 - color;

	
	gl_FragColor = vec4(ToneMapFilmicALU_HEJL(color*color*color), 1.0 );
}