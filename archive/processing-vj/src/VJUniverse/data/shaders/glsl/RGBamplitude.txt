#ifdef GL_ES
precision mediump float;
#endif
#define pi 3.141592653589793238462643383279

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	// How fast it animates
	float tscale = 2.5;
	
	// normalize position
	vec2 position = gl_FragCoord.xy / resolution.xy;
	
	// Generate base luminance value
	float lum   = abs(tan(position.y * pi)) - pi/5.0;
	
	// generate RGB offset with different phase variances
        float red   = sin(position.x * 5.0 + time*tscale*1.00) * 2.0 - 1.0;
	float green = sin(position.x * 8.0 + time*tscale*1.33) * 2.0 - 1.0;
	float blue  = sin(position.x * 2.0 + time*tscale*1.93) * 2.0 - 1.0;
	
	// Add white and RGB channels together for final effect!
	gl_FragColor = vec4( vec3( lum + red, lum + green, lum + blue ), 1.0 );

}