float t;
float highcolor;
float lowcolor;
float fade;
float edibleHelper;

mat2 m(float a){
  float c=cos(a), s=sin(a);
  return mat2(c,-s,s,c);
}

float map(vec3 p){
    p.xz*= m(t*0.4);
    p.xy*= m(t*0.3);
    vec3 q = p*2.0+t*1.;
    q = mix(q, p*0.1+t*1., simplify);
    float map1 = length(p+vec3(sin(t*0.7)))*log(length(p*pow(size,3.0))+1.) + sin(q.x+sin(q.z+sin(q.y)))*0.5 - 1.;
    float map2 = map1 + length(q)*0.0005 + sin(q.z*q.y)*fract(syn_BPMTwitcher)*0.1*scratch;
    return map2;
}

vec3 color1() {
  vec3 C = vec3(0.1,0.3,.4);
  C = mix(C, vec3(0.1,0.3,0.4), c1);
  C = mix(C, vec3(0.4,0.2,0.2), c2);
  C = mix(C, vec3(0.05,0.3,0.15), c3);
  return C;
}

vec3 color2() {
  vec3 C = vec3(5, 2.5, 3);
  C = mix(C, vec3(5,4,2),   b1);
  C = mix(C, vec3(3,5,2.5), b2);
  C = mix(C, vec3(1,2.5,6), b3);
  return C;
}

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

vec3 mainImage(vec2 p){
  vec3 cl = vec3(0);
  float d = fade;
  float iters = 3.0+syn_HighHits*5.0;
  if (autofuzz <= 0.5){
    iters = 7+fuzz;
  }
  if (_isMediaActive()){
    float tempo = _loadMediaAsMask().r;
    iters -= (iters/2)*tempo*0.5;
  }
  for(int i=0; i<=iters; i++)	{
		vec3 p = vec3(0,0,5) + normalize(vec3(p, -1.))*d;
    vec3 posMod = vec3(fade_to_color, fade_to_color, 1.0+(1.0-fade_to_color)*0.75);
    float rz = map(p*vec3(1.0-bump_up,1.0+bump_up,1.0)*posMod);
		float f =  clamp((rz - map(p+.1*shading))*0.5, -.1, 1. );
    vec3 l = (color1()*lowcolor) + color2()*(f + highcolor);
    if (fog >= 0.5){
      cl = cl + hsv2rgb(vec3(f+edibleHelper, 0.5+0.5*sin(rz*2.0)-edibleHelper, f))*1.0;
    } else{
      cl = cl*l + (1.-smoothstep(0., 2.5, rz))*.7*l;
    }
		d += min(rz, 1.);
	}
  return cl;
}


vec4 renderMain() {
  t = mod((syn_CurvedTime*0.7+syn_Time*0.3),500.0);
  highcolor = syn_HighHits * 0.1;
  lowcolor = _scale(syn_BassHits, 1.2, 0.7);
  fade     = _scale(syn_FadeInOut, 10, 2.5);
  edibleHelper = (fog-0.5)*2.0;

  vec2 p = _uvc;
  p = _rotate(p, TIME/10);
  // p *= (1.0-bump_up);


  vec3 col = mainImage(p)*2/3;
  if (electrify >= 0.5){
    p = _rotate(p,length(col)*PI);
  } else {
    p = _rotate(p,1.0);
    p /= 5;
  }
  col += mainImage(p)/3;

  return vec4(col, 1.0);
}
