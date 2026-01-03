// by @eddbiddulph
// autumn trees at night, from hiding in the grass
// PLEASE view in 0.5 mode!!

#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float circle(vec2 p, vec2 o, float r)
{
	p -= o;
	return step(dot(p, p), r);
}

vec2 rotate(vec2 v, float angle)
{
	return vec2(v.x * cos(angle) - v.y * sin(angle),
		    v.y * cos(angle) + v.x * sin(angle));
}

float tree(vec2 p, vec2 o, float a)
{
	p -= o;

	float m = step(p.y, 0.5) * step(abs(p.x), 0.01 / ((p.y + 0.3)));

	vec2 bo = vec2(0.0, 0.5);

	// make the branches and leaves with some circles
	m = max(m, circle(p, bo + rotate(vec2(0.0, 0.0), a), 0.01));
	m = max(m, circle(p, bo + rotate(vec2(0.1, 0.1), a), 0.011));
	m = max(m, circle(p, bo + rotate(vec2(-0.06, 0.05), a), 0.008));
	m = max(m, circle(p, bo + rotate(vec2(-0.02, 0.12), a), 0.008));

	return m;
}

float rowOfTrees(vec2 p)
{
	float a = cos(floor(p.x) * 20.6) * 3.1415926, b = 1.0 + cos(floor(p.x) * 10.0) * 0.2;
	p.x = mod(p.x, 1.0);
	return tree(p * b, vec2(0.5, 0.0) * b, a);
}

float grass(vec2 p)
{
	p *= vec2(10.0, 1.0) * 2.5;
	float a = floor(p.x) * 12.0, b = 1.0 + sin(floor(p.x)) * cos(floor(p.x) * 0.3) * 0.1;
	p.x = mod(p.x, 1.0) - 0.5;
	return step(abs(p.x + cos(a) * p.y ), 0.5 - p.y * b);
}

float starPattern(vec2 p)
{
	return 0.1 / (abs(cos(p.x)) + 0.01) * 0.1 / (abs(sin(p.y)) + 0.01) * abs(sin(p.x)) * abs(cos(p.y));
}

vec3 stars(vec2 p)
{
	p -= 0.5;

	float a = starPattern(rotate(p * 26.0, 0.1)) * max(0.0, 1.3 + cos(p.x + time)) +
		starPattern(rotate(p * 50.0, 0.2)) * max(0.0, 1.2 + cos(p.x * 0.4 + time * 2.0));

	return vec3(a * 0.1 * (1.0 + (2.0 + sin(time * 30.0)) * 0.2));
}

void main(void)
{
	vec2 p = gl_FragCoord.xy / resolution.xy * vec2(resolution.x / resolution.y, 1.0),
		scroll = vec2(time * 0.05, 0.0);

	vec3 col = vec3((1.0 - p.y) * 0.1, (1.0 - p.y) * 0.1, 0.1); // backdrop

	col += stars(p) * max(0.0, p.y - 0.6);

	if(grass(p * 0.9 + scroll) > 0.0) // grass
		col = vec3(0.2, 0.5, 0.0);
	else if(rowOfTrees(p + scroll) > 0.0) // near trees
		col = vec3(0.6, 0.4, 0.0) * mix(0.8, 1.0, p.y);
	else if(grass(p * 1.2 + scroll) > 0.0) // far grass
		col = vec3(0.1, 0.3, 0.0);

          	else if(grass(p * .8 + scroll) > 0.0) // more grass
		col = vec3(0.4, 1.0, 0.0);
                  
          	else if(rowOfTrees(p * 1.1 + scroll) > 0.0) // more trees
		col = vec3(0.9, 0.9, 0.) * mix(0.8, 1.0, p.y);

                else if(rowOfTrees(p * 1.6 + scroll) > 0.0) // more trees
		col = vec3(0.9, 0.9, 0.) * mix(0.8, 1.0, p.y);

               else if(rowOfTrees(p * 1.5 + scroll) > 0.0) // more trees
		col = vec3(0.1, 0.87, 0.8) * mix(0.8, 1.0, p.y);
                  
                  
          else if(rowOfTrees(p * 1.5 + scroll + vec2(10.0, 0.0)) > 0.0) // far trees
		col = vec3(0.3, 0.2, 0.0) * mix(0.8, 1.0, p.y);

	gl_FragColor.a = 1.0;
	gl_FragColor.rgb = col;
}