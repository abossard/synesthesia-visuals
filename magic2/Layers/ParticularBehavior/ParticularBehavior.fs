/*{
	"CREDIT": "by mojovideotech",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"particles"
	],
	"INPUTS": [

	]
}*/

////////////////////////////////////////////////////////////
// ParticularBehavior1  by mojovideotech
//
// based on :
// glslsandbox/\e#44948.0
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////

#define 	pi	3.141592653589793 	// pi
#define T   (TIME + 10000.0) * 0.1

float hash(vec2 co) { float m = dot(co, vec2(237.561, 39.1)); return fract(sin(cos(m)* 1113.27)); }

float random(float n) { return fract(cos(sin(n * 55.753) * 367.34)); }

mat2 rotate2d(float angle){ return mat2(cos(angle), -sin(angle),  sin(angle), cos(angle)); }

void main() {
	
	vec2 uv = (gl_FragCoord.xy * 2.0 -  RENDERSIZE.xy) / RENDERSIZE.x;
	vec2 p = uv * rotate2d(T * 0.213); 
	float direction = 120.0/(T/p.x,-T/p.y,sqrt(T));
	float speed = T * direction * 0.231 ;
	float distanceFromCenter = random(1.5) + length(p);
	p.yx *= rotate2d(-T * 0.239);
	float meteorAngle = atan(p.y, p.x) * (359.0 + cos(atan(speed,pi))+pi);
	float flooredAngle = floor(meteorAngle);
	float randomAngle = pow(random(flooredAngle),mix(cos(direction*pi),-sin(speed*pi),distanceFromCenter));
	float t = speed + randomAngle;
	float lightsCountOffset = 0.9;
	float adist = randomAngle / distanceFromCenter * lightsCountOffset;
	float dist = t + adist;
	float meteorDirection = (direction < 0.5) ? -1.0 : 0.0;
	dist = abs(fract(dist) + meteorDirection);
	float lightLength = 40.0/hash(uv.xy);
	float meteor = (random(3.0)  / dist)  * cos(sin(speed)) / lightLength;
	meteor -= dot(vec2(distanceFromCenter,meteorDirection),vec2(randomAngle,meteorAngle));
	vec3 color = vec3(0.0);
	color += meteor;

	gl_FragColor = vec4(color, 1.0);
}