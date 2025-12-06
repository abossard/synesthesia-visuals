#ifdef GL_ES
precision mediump float;
#endif

uniform vec2 resolution;
uniform float time;
 
float lengthN(vec2 v, float n)
{
  vec2 tmp = pow(abs(v), vec2(n));
  return pow(tmp.x+tmp.y, 1.0/n);
}
 
float rings(vec2 p)
{
  vec2 p2 = mod(p*8.0, 4.0)-2.0;
  return sin(lengthN(p2,4.0)*16.0+time*20.0);
}

void main() {
  vec2 pos = (gl_FragCoord.xy*2.0 -resolution) / resolution.y;;
 
  gl_FragColor = vec4(rings(pos*sin(time)+.25));
}
