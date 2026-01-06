//author = ? 
//2012.04.26 tigrou(ind) fork : add glow

#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float segmentShape(vec2 p, vec2 s0, vec2 s1, float radius)
{
	vec2 d = normalize(s1 - s0);
	float slen = distance(s0, s1);

	float 	d0 = max(abs(dot(p - s0, d.yx * vec2(-1.0, 1.0))), 0.0),
		d1 = max(abs(dot(p - s0, d) - slen * 0.5) - slen * 0.5, 0.0);

		
	return step(length(vec2(d0, d1)), radius*30.0)*0.008/(length(vec2(d0, d1)));
		
}
vec2 sequence(float t)
{
	return vec2( mod((t * 1721.0) / 7.0, 1.0), mod((t * 1669.0) / 13.0, 1.0)) - vec2(0.5);
}

float snakeShape(vec2 p, float t)
{
	float ti = floor(t), radius = 0.02, tf = fract(t);

	vec2 	sp0 = sequence(ti), sp1 = sequence(ti - 1.0),
		sp2 = sequence(ti - 2.0), sp3 = sequence(ti - 3.0);

	float 	l0 = segmentShape(p, sp1, mix(sp1, sp0, tf), radius),
		l1 = segmentShape(p, sp2, sp1, radius),
		l2 = segmentShape(p, mix(sp3, sp2, tf), sp2, radius);

	return clamp(l0 + l1 + l2, 0.0, 8.5);
}

void main( void ) {

	vec2 p = (gl_FragCoord.xy / resolution.xy - vec2(0.5)) * vec2(resolution.x / resolution.y, 1.0);

	gl_FragColor.a = 1.0;
	gl_FragColor.rgb = 	snakeShape(p, time + 000.0) * vec3(0.8, 0.4, 0.8) +
				snakeShape(p, time + 100.2) * vec3(0.4, 0.8, 0.8) +
				snakeShape(p, time + 200.3) * vec3(0.8, 0.4, 0.4) +
				snakeShape(p, time + 300.4) * vec3(0.8, 0.8, 0.4) +
				snakeShape(p, time + 400.5) * vec3(0.4, 0.8, 0.4);
}