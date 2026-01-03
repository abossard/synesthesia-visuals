#ifdef GL_ES
precision mediump float;
#endif

#define zNear 0.001
#define PI 3.14159265359

// INTERNET

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

bool one(vec2 pos) {
	return pos.x > 0.45 && pos.x < 0.55 && pos.y > 0.1 && pos.y < 0.9;
}

bool zero(vec2 pos) {
	float d = length(pos - 0.5);
	
	return d > 0.3 && d < 0.4;
}

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
	
	vec2 sp = vec2(cp.z * 1000.0, mod(ca * 20.0 + time, 20.0));
	sp.x += sin(floor(sp.y)) * time * 4.0 + time * 5.0;

	vec2 tp = mod(sp, 1.0);
	//bool w = mod(ca + cp.z + time * 0.1, 0.2) < 0.1;
	//if (mod(cp.z + time * 0.005, 0.01) < 0.005)
	//  w = !w;
	
	bool w;
	if (mod(floor(sp.x) * floor(sp.y), 2.0) < 1.0) {
		w = zero(tp);
	}
	else {
		w = one(tp);
	}

	gl_FragColor = vec4(vec3(0.0, 0.7, 0.7) * float(w) * (1.0 - cp.z * 10.0), 1.0);
}