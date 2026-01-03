// by @DanielPettersso

#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 resolution;
vec4 hsv2rgb(vec3 col)
{
    float iH = floor(mod(col.x,1.0)*6.0);
    float fH = mod(col.x,1.0)*6.0-iH;
    float p = col.z*(1.0-col.y);
    float q = col.z*(1.0-fH*col.y);
    float t = col.z*(1.0-(1.0-fH)*col.y);
  
  if (iH==0.0)
  {
    return vec4(col.z, t, p, 1.0);
  }
  if (iH==1.0)
  {
    return vec4(q, col.z, p, 1.0);
  }
  if (iH==2.0)
  {
    return vec4(p, col.z, t, 1.0);
  }
  if (iH==3.0)
  {
    return vec4(p, q, col.z, 1.0);
  }
  if (iH==4.0)
  {
    return vec4(t, p, col.z, 1.0);
  }
  
  return vec4(col.z, p, q, 1.0); 
}
float wave(float size, float speed, float strength, vec2 pos)
{
	return cos(length(pos*size)-time*speed)*(strength*max(0.,(1.-length(pos))));
}

float wavein(float size, float speed, float strength, vec2 pos)
{
	return cos(length(pos*size*(sin(time*2.)*0.3+1.))+time*speed)*(strength*max(0.,(1.-length(pos))));
}

float sinpp(float a)
{
	return (sin(a)+1.)*0.5;
}

float cospp(float a)
{
	return (cos(a)+1.)*0.5;
}

void main(void)
{
	vec2 p = -1.0 + 1.0 * gl_FragCoord.xy / resolution.xy;
	p.x *= resolution.x / resolution.y;

	vec2 pp = (p + 2.0)*0.5;
	vec3 col = vec3(pp.x, pp.y, (pp.x*pp.y)*sinpp(time*9.) + (pp.x+pp.y)*cospp(time*4.));
	
	col += wave(1.0, 7.0, 0.4, p);
	col += wave(6.0, 8.0, 0.9, p+0.03);
	col += wavein(180.0, 8.0, 0.4, p-0.02);
	
	gl_FragColor = hsv2rgb(col);
}