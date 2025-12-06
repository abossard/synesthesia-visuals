// Newtow Fractal 1-z^3 by @hintz

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float deltax=12.0+sin(time*0.4)*10.0;
float deltay = resolution.y/resolution.x * deltax;

float theta=time*0.1;
float cosThetaPi = cos(theta);
float sinThetaPi = sin(theta);

float real = deltax*(gl_FragCoord.x/resolution.x-0.5);
float imag = deltay*(gl_FragCoord.y/resolution.y-0.5);
 
float realR =  real*cosThetaPi - imag*sinThetaPi;
float imagR =  real*sinThetaPi + imag*cosThetaPi;

// for pretty colors
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

// complex number math functions
vec2 mul(vec2 a, vec2 b)
{
  return vec2(a.x*b.x - a.y*b.y, a.y*b.x + a.x*b.y);
}

vec2 div(vec2 a, vec2 b)
{
  return vec2( (a.x*b.x + a.y*b.y)/(b.x*b.x + b.y*b.y), (a.y*b.x - a.x*b.y)/(b.x*b.x + b.y*b.y));
}

vec2 znext(vec2 z)
{
  vec2 z2=mul(z,z);
  
  return z-div(vec2(1.0,0.0)-mul(z2,z), -3.0*z2);
}

vec2 newtonfractal(vec2 z)
{
  for (int n=0;n<100;n++)
  {
    vec2 old=z;
    z = znext(z);
   
    vec2 d=z-old;
    d*=d;
      
    if (d.x+d.y < 0.08)
    {
      
      return vec2(z.x+z.y+time*0.1, float(n)*0.06);
    }
  }
  
    //(float(n) + (0.32663426-log(log(sqrt(z.x * z.x + z.y * z.y))))/0.693147181)/float(iterations)
    //float(n)/float(iterations)
  return z;
}

void main(void)
{
  vec2 results = newtonfractal(vec2(realR, imagR));

  float h = results.x;
  float v = 1.0-results.y;
  float s = 0.8;

  gl_FragColor = hsv2rgb(vec3(h, s, v));
}
