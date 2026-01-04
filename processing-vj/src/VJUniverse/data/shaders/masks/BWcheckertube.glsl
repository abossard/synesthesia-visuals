#ifdef GL_ES
precision mediump float;
#endif

#define zNear 0.001
#define PI 3.14159265359

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = gl_FragCoord.xy / resolution.xy;

	position -= 0.5;
	
 	position.x /= resolution.y / resolution.x;
	
	
	vec3 rayDir = normalize(vec3(position, zNear));
	vec3 rayPos = vec3(position, 0);

	float a = rayDir.x * rayDir.x + rayDir.y * rayDir.y;
	float b = 2.0 * (rayPos.x * rayDir.x + rayPos.y * rayDir.y);
	float c = rayPos.x * rayPos.x + rayPos.y * rayPos.y - 1.0;
	
	float d = (-b + sqrt(b * b - 4.0 * a * c)) / (2.0 * a);
		
	vec3 cp = rayPos + rayDir * d;
	float ca = (atan(cp.y, cp.x) + PI) / (2.0 * PI);
	bool w = mod(ca + cp.z + time * 0.1, 0.2) < 0.1;
	if (mod(cp.z + time * 0.005, 0.01) < 0.005)
	  w = !w;

	gl_FragColor = vec4(vec3(float(w) * (1.0 - cp.z * 20.0)), 1.0);
}