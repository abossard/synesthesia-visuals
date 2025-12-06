// Recursive effects by Optimus

#ifdef GL_ES
precision mediump float;
#endif
 
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

const float recursion_level = 8.0;

void main(void)
{

	float scale = sin(time / 8.0) * 8.0 + 8.001;
	if (scale < 0.125) scale = 0.125;

	vec2 position = vec2((gl_FragCoord.x / resolution.x) - 0.5, (gl_FragCoord.y / resolution.y) - 0.5) * scale + mouse * 16.0;

	vec2 coord = mod(position,1.0);	// coordinate of single effect window (0.0 - 1.0)
	vec2 effect = floor(mod(position,2.0)); // effect number (0-1,0-1)
	float effect_number = effect.y * 2.0 + effect.x;
	vec2 effect_group = floor(position) * 7.0; // effect group float id
 
	float gradient = 0.0;
	vec3 color = vec3(0.0);
 
	float angle = 0.0;
	float radius = 0.0;
	const float pi = 3.141592;
	float fade = 0.0;
 
	float u,v;
	float z;
 
	vec2 centered_coord = coord - vec2(0.5);

	float dist_from_center = length(centered_coord);
	float angle_from_center = atan(centered_coord.y, centered_coord.x);

	float iii;
	for (float ii=0.0; ii<=recursion_level; ii++)
	{
		if (effect_number==3.0)
		{
			position *= 2.0;

			coord = mod(position,1.0);
			effect = floor(mod(position,2.0));
			effect_number = effect.y * 2.0 + effect.x;
			effect_group = floor(position) * 7.0;

			centered_coord = coord - vec2(0.5);
			dist_from_center = length(centered_coord);
			angle_from_center = atan(centered_coord.y, centered_coord.x);
		}
		else if (effect_number==2.0)
		{
			for (float i=1.0; i<=128.0; i++)
			{
				vec2 star_pos = vec2(sin(i) * 64.0, sin(i*i*i) * 64.0);
				float z = mod(i*i - 128.0*time, 256.0);
				float fade = (256.0 - z) / 256.0;
				vec2 blob_coord = star_pos / z;
				gradient += ((fade / 384.0) / pow(length(centered_coord - blob_coord), 1.5)) * (fade * fade);
			}

			color = vec3(gradient * 2.0, gradient, gradient / 2.0);
			break;
		}
		else if (effect_number==1.0)
		{
			u = 8.0 / dist_from_center + 16.0 * time;
			v = angle_from_center * 16.0 + sin(time * 0.5) * 32.0;
	 
			fade = dist_from_center * 2.0;
			gradient = ((1.0 - pow(sin(u) + 1.0, 0.1)) + (1.0 - pow(sin(v) + 1.0, 0.1))) * fade;
			color = vec3(gradient * 4.0, gradient, gradient / 2.0);
			break;
		}
		else if (effect_number==0.0)
		{
			gradient = sin(coord.x * 32.0 + 2.0 * time) + sin(coord.x * 16.0 + coord.y * 24.0) + sin(coord.x * 4.0 + sin(coord.y * 18.0 + 4.0*time)) + sin(sin((coord.x + coord.y) * 33.0) + sin(coord.y * 24.0 + time));
			color = vec3(sin(gradient * 2.0) * 0.5 + 0.5, sin(gradient * 1.5) * 0.75 + 0.25, sin(gradient * 1.2) * 0.5 + 0.5);
		}

		iii = ii;
	}
 
	color.r *= (sin(effect_group.x * iii) * 0.5 + 1.0);
	color.g *= (sin((effect_group.x + effect_group.y) * iii * iii) * 0.5 + 1.0);
	color.b *= (sin(effect_group.x * effect_group.y) * 0.5 + 1.0);
 
	gl_FragColor = vec4(color, 1.0);
}
