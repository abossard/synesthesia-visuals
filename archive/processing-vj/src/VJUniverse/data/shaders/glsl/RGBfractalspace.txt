#ifdef GL_ES
precision highp float;
#endif

uniform vec2 resolution;
uniform float time;
uniform vec2 mouse;



// rods and cones
// willed convulsions
// spoiled zombie bouquet
// incoherent signals
// united focus
// sweet spot
// o-zone




float getm(vec2 c, out float iters)
{
  vec2 z = vec2(-0.0,0.0);
  vec2 dz = vec2(1.0,0.0);
  vec2 zdz;
  float m2;
  iters = 0.0;
  for (float i=0.0; i<100.0; i++)
  {
    // z * dz = (z.x * dz.x - x.y * dz.y),(z.x*dz.y+z.y*dz.x)
    zdz = vec2(z.x * dz.x - z.y * dz.y,z.x*dz.y+z.y*dz.x);
    dz = 2.0 * zdz + 1.0;
    z = c + vec2(z.x * z.x - z.y * z.y, 2.0*z.x*z.y);
    m2 = dot(z,z);
    iters = i;
    if(m2 > 1024.0) break;
  }
  iters = iters + 1. - log(log(length(z)))/log(2.);
  return sqrt(m2/dot(dz,dz))*0.5*log(m2);
}
void main(void) 
{
  vec2 p = ( gl_FragCoord.xy / resolution.xy ) * 2.0 - vec2(1.0,resolution.y/resolution.x);

  float zoo = 0.62 + 0.38 * cos(0.25 * time);
    float coa = cos( 0.1*(1.0 - zoo) + time);
     float sia = sin( 0.1*(1.0 - zoo) +time);
    zoo = pow( zoo, 8.0);
    vec2 xy = vec2( p.x*coa-p.y*sia, p.x*sia+p.y*coa);
    vec2 cc = vec2(-.745,.186) + xy*zoo;
  float i;
  float col = getm(cc,i)*(1024.0 * (1.0/zoo));
  float colb = sin(i);
  //vec3 rgb = vec3(cos(i + col),min(cos(col),0.5),0.0+sin(i * col));
  vec3 rgb = vec3(cos(col),cos(col),cos(col));
  vec3 rgb2 = vec3(cos(i),sin(i),cos(col)) * 0.8;
  
  //vec3 mixed = mix(rgb,rgb2, (sin(pow(length(-1.0 + 2.0 * gl_FragCoord.xy / resolution.xy),-1.1) + (time * 2.0))) < 0.4 ? 1.0:0.0);
  vec3 mixed = mix(rgb,rgb2, 1.0 + sin(pow(length(-1.0 + 2.0 * gl_FragCoord.xy / resolution.xy),-0.8) + (time * 2.0)));
  gl_FragColor=vec4(mixed, 1.0);
}