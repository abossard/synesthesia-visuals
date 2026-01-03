#ifdef GL_ES
precision mediump float;
#endif

// Mouse position tracking from http://glsl.heroku.com/e#3905.0

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	float aspect = resolution.x / resolution.y;
	vec2 screenPos = gl_FragCoord.xy / resolution;
	screenPos.x *= aspect;
	
	vec2 mousePos = mouse;
	mousePos.x *= aspect; // aspect fix for mouse
	
	mousePos.y += 15./resolution.y; // Why does this position mouse roughly correctly?
	
	float r = sin(screenPos.y);
	float g = sin(screenPos.x);
	float b = smoothstep(1.5, -1.5, length(mousePos - screenPos));
	b = sin((b * 200.0));

	gl_FragColor.r = r;
	gl_FragColor.g = g;
	gl_FragColor.b = b;
	gl_FragColor.rgb =  1.0 - gl_FragColor.rgb;
	gl_FragColor.a = 1.0;

}