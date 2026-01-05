#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

//MrOMGWTF
//party :D
vec3 flare(vec2 spos, vec2 fpos, vec3 clr)
{
	vec3 color;
	float d = distance(spos, fpos);
	vec2 dd;
	dd.x = spos.x - fpos.x;
	dd.y = spos.y - fpos.y;
	dd = abs(dd);
	
	color = clr * max(0.00, 0.015 / dd.y) * max(0.0, 1.2 -  dd.x);
	color += clr * max(0.0, 0.05 / d);
	color += clr * max(0.0, 0.13 / distance(spos, -fpos)) * 0.15 ;
	color += clr * max(0.0, 0.13 - distance(spos, -fpos * 1.5)) * 1.5 ;
	color += clr * pow(max(0.0, 0.07 - distance(spos, -fpos * 0.4)), 2.0) * 40.0 ;
	
	
	return color;
}

float noise(vec2 pos)
{
	return fract(1111. * sin(111. * dot(pos, vec2(2222., 22.))));	
}

float noise(float pos)
{
	return fract(1111. * sin(111. * pos));	
}

float snoise(float pos)
{
	return mix(noise(floor(pos)), noise(ceil(pos)), fract(pos));	
}


void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy * 2.0 ) - 1.0;
	position *= pow(1.0 - fract(time * 2.0) + 0.1, 0.2);

	
	position.x *= resolution.x / resolution.y;
	vec3 color = flare(position, vec2(sin(time * 1.5) * 0.5 + (0.1 * snoise(time * 5.0) * 2.0 - 1.0), cos(time * 2.0)) * 0.5 * (fract(time)) , vec3(0.9, 0.0, 0.25));
	color += flare(position, vec2(sin(time * 1.5 + 1.0)*0.5 + (0.1 * snoise(time * 5.0) * 2.0 - 1.0), cos(time * 2.0 + 2.0)) * 0.5 * (fract(time +0.3)) , vec3(0.25, 0.0, 0.9));
	
	color *= pow(snoise(time * 20.0), 1.0) * 2.0;
	color = pow(color, vec3(0.8));
	gl_FragColor = vec4( color * (0.950 + noise(position*0.001 + 0.00001) * 0.05), 1.0 );
	gl_FragColor *= cos(position.x*700.0)*0.1 + 0.9;

}