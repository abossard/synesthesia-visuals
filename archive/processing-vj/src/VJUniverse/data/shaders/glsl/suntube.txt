#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main()
{

	vec2 position = -1.0 + 2.0 * (gl_FragCoord.xy / resolution.xy);
	position.x *= resolution.x / resolution.y;
	
	position += vec2(cos(time * 0.25), sin(time * 0.5)) * 0.8;

	vec3 colour = vec3(0.0);
	
	float u = sqrt(dot(position, position));
	float v = atan(position.y, position.x);
	
	float t = time + 1.0 / u;
	
	float val = smoothstep(0.0, 1.0, sin(5.0 * (time + sin(1.0*u * 3.7)) + 10.0 * v) + cos(t * 10.0));
	
	colour = vec3(val / 0.1, val, 0.0) + (0.9 - val) * vec3(0.05, 0.05, 0.05);
	colour *= clamp(u / 1.0, 0.0, 1.0);
	
	gl_FragColor = vec4(colour, 1.0);

}