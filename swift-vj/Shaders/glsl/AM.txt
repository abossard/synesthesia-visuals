#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float PI = 3.14159265359;

float timeScale = 0.2; 		// Slow down time a little.
float zoom = 1.0;

struct params {
	float w;
	float k;
};

// l:  Wave length
// f:  Frequency
params calculateParams(float l, float f) {
	params p;
	
	p.w = 2.0 * PI * f;	// Angular frequency		
	p.k = (2.0 * PI) / l; 	// Wave number		
	
	return p;
}
	
void main( void ) {
	params p;
	float y0 = 0.15; // amplitude
	
	// Normalize and center coord
	float scale = resolution.y / zoom;
	vec2 pos = (gl_FragCoord.xy / scale);
	pos -= vec2((resolution.x / scale) / 2.0, (resolution.y / scale) / 2.0);
	
	// Standing wave equation first Harmonic
        p = calculateParams(1.0, 1.0);
	float y = 2.0 * y0 * cos(p.w * time* timeScale) * sin(p.k * pos.x);
	
	// Standing wave second harmonic
	//p = calculateParams(0.5, 2.0);
	//y += 2.0 * y0 * cos(p.w * time* timeScale) * sin(p.k * pos.x);
	
	// Standing wave third harmonic
	//p = calculateParams(0.25, 3.0);
	//y += 2.0 * y0 * cos(p.w * time* timeScale) * sin(p.k * pos.x);
	
	// Standing wave fourth harmonic
	//p = calculateParams(0.125, 4.0);
	//y += 2.0 * y0 * cos(p.w * time* timeScale) * sin(p.k * pos.x);
	
	// Standing wave fifth harmonic
	//p = calculateParams(0.0625, 5.0);
	//y += 2.0 * y0 * cos(p.w * time* timeScale) * sin(p.k * pos.x);
	
	// Pixel color based on distance to wave.
	float color = 1.0 / (exp(abs(y - pos.y) * 50.0));
	
	gl_FragColor = vec4( vec3( 0.4, 0.4, 1.0 ) * color, 1.0 );

}