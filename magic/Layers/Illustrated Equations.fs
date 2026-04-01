/*{
  "CREDIT": "by mojovideotech",
  "CATEGORIES": [
    "Generator"
  ],
  "DESCRIPTION": "Automatically converted from http://glslsandbox.com/e#26145.0",
  "INPUTS": [
    {
      "NAME": "FIELD",
      "TYPE": "float",
      "MIN": 1.0,
      "MAX": 38.0,
      "DEFAULT": 32
    },
    {
      "NAME": "posX",
      "TYPE": "float",
      "MIN": 0.0,
      "MAX": 1.0,
      "DEFAULT": 0.5
    },
    {
      "NAME": "posY",
      "TYPE": "float",
      "MIN": 0.0,
      "MAX": 1.0,
      "DEFAULT": 0.5
    }
    ]
}*/


//---------------------------------------------------------
// Shader:   IllustratedEquations.glsl               4/2015
//           http://glslsandbox.com/e#24923
//           http://glslsandbox.com/e#24891
// Original: https://www.shadertoy.com/view/MtBGDW
//           Created by sofiane benchaa - sben/2015 
// tags:     procedural, 2d, fractal, trigonometric, curve, complex, iterative
// info:     http://www.mathcurve.com/surfaces/tore/tn.shtml
//           http://xrt.wikidot.com/gallery:implicit
//---------------------------------------------------------

#ifdef GL_ES
precision mediump float; 
#endif


//---------------------------------------------------------
#define ITERATION 12
#define CHANNEL bvec3(true,true,true)
#define PI4 0.7853981633974483
#define TONE vec3(0.299,0.587,0.114)

//just a line
float crossEQ(vec3 p,float t)
{
	float pv = p.x * p.y;
	return pv * pv;
}

// triangle
float triangleEQ( vec3 p, float t )
{
	return max(abs(p.x)*PI4+p.y*0.5,-p.y) - 0.1+ 0.2*sin(t);
}

//---------------------------------------------------------
// regular trifolium
// http://www.mathcurve.com/surfaces/tore/tn.shtml
// ((x^2+y^2)^2-x*(x^2-3*y^2))^2+z^2-0.008=0
float bretzTrifolEQ (vec3 p, float t)
{	
	float x2 = p.x*p.x;
	float y2 = p.y*p.y;
	float fv = (x2+y2)*(x2+y2)-p.x*(x2-3.0*y2);
	fv *= fv;
	fv += p.z * p.z;
	fv /= 0.008+0.006*sin(t);
	return fv;
}

// Bretzel6
// ((x^2+y^2/4-1)*(x*x/4+y*y-1))^2-z^2=0.1
float bretzel6EQ(vec3 p,float t)
{	
	float x2 = p.x*p.x;
	float y2 = p.y*p.y;
	float fv = (x2+y2/4.-1.)*(x2/4.+y2-1.);
	fv *= fv;
	fv += p.z*p.z;
	fv /= 0.06+0.04*sin(t);
	return fv;
}

// quad torus
// (x^2*(1-x^2)^2*(4-x^2)^3-20*y^2)^2+80*z^2=22
float quadTorusEQ(vec3 p,float t)
{
	float x2 = p.x*p.x;
	float y2 = p.y*p.y;
	float fv = x2*pow(1.0-x2,2.)*pow(4.0-x2,3.0)-20.0*y2;
	fv *= fv;
	fv += 1.0*(p.z*p.z);
	fv /= 22.0 + 16.*sin(t);
	return fv;
}
//lemniscat Bernoulli
// ((x^2+y^2)^2-x^2+y^2)^2+z^2=0.01
float bretzBernEQ(vec3 p,float t)
{
	float x2 = p.x*p.x;
	float y2 = p.y*p.y;
	float fv = ((x2+y2)*(x2+y2)-x2+y2);
	fv *= fv;
	fv /= 0.02 + 0.01*sin(t);
	return fv;
}

// animated calamari
float pieuvreEQ(vec3 p,float t)
{
	float fv = p.x;
	fv = (p.y+length(p*fv)-cos(t+p.y));
	fv = (p.y+length(p*fv)-cos(t+p.y));
	fv = (p.y+length(p*fv)-0.5*cos(t+p.y));
	fv *= fv*0.1;
	return fv;
}

//---------------------------------------------------------
//iterative equations

//mandelbrot
float mandelbrotEQ(vec3 c,float t)
{
	vec4 z = vec4(c,0.0);
	vec3 zi = vec3(0.0);
	for(int i=0; i<ITERATION; ++i)
	{
		zi.x = (z.x*z.x-z.y*z.y);
		zi.y = 2.*(z.x*z.y);
		zi.xyz += c;
		if(dot(z.xy,z.xy)>4.0)break;
		z.w++;
		z.xyz=zi;
	}
	z.w /= float(ITERATION);
	return 1.0-z.w;
}

//---------------------------------------------------------
// wolf face
float wolfFaceEQ(vec3 p,float t)
{
	vec2 fx = p.xy;
	p=(abs(p*2.0+sin(t)*0.7));
	const float j=float(ITERATION);
	vec2 ab = vec2(2.0-p.x);
	for(float i=0.0; i<j; i++)
	{
		ab+=(p.xy)-cos(length(p));
		p.y+=sin(ab.x-p.z)*0.5;
		p.x+=sin(ab.y)*0.5;
		p-=(p.x+p.y);
		p+=(fx.y+cos(fx.x));
		ab += vec2(p.y);
	}
	p /= FIELD;
	return p.x + p.x + p.y;
}

// dog face
float dogFaceEQ(vec3 p,float t)
{
	vec2 fx = p.xy;
	p=(abs(p*2.0)+sin(t)*0.2);
	const float j=float(ITERATION);
	vec2 ab = vec2(2.0-p.x);
	for(float i=0.0; i<j; i++)
	{		
		ab+=p.xy+cos(length(p));
		p.y+=sin(ab.x-p.z)*0.5;
		p.x+=sin(ab.y)*0.5;
		p-=(p.x+p.y);
		p-=((fx.y)-cos(fx.x));
	}
	p /= FIELD;
	return p.x + p.x + p.y;
}

//---------------------------------------------------------
vec3 computeColor(float fv)
{
	vec3 color = vec3(vec3(CHANNEL)*TONE);
	color -= (fv);
	color.r += color.g*2.0;
	color.g += color.b;
	return clamp(color,(0.0),(1.0));
}
//---------------------------------------------------------
void main() 
{
	float ratio = RENDERSIZE.y / RENDERSIZE.x;
	vec2 position = ( gl_FragCoord.xy / RENDERSIZE.xy )-vec2(posX, posY*ratio);
	position.y *= ratio;
	vec3 p = position.xyx*FIELD;
    
	p.z = 2.0*FIELD*0.5;
	vec3 color = computeColor(wolfFaceEQ(p+vec3(7.0, -1.0, 0.2),TIME));
	p.z = 0.0;  
	color += computeColor(dogFaceEQ(p*2.0+vec3(0.0,-3.0, 0.0),TIME));
	color += computeColor(mandelbrotEQ(p+vec3(-5.0,-4.0, 0.0),TIME));
 
	color += computeColor(triangleEQ(p+vec3(-4.0,-1.0, 0.0),TIME));
	color += computeColor(crossEQ(p+vec3(+2.3, 6.0, 0.0),TIME));

	color += computeColor(quadTorusEQ(p+vec3(-5.0, 1.0, 0.0),TIME));
	color += computeColor(bretzTrifolEQ(p+vec3(-6.0, 3.0, 0.0),TIME));
	color += computeColor(bretzel6EQ(p+vec3(-7.4, -2.0, 0.0),TIME));
	color += computeColor(bretzBernEQ(p+vec3(-4.0, 3.0, 0.0),TIME));
    	color += computeColor(pieuvreEQ(p*2.5+vec3(-4.0, 4.0, 0.0),TIME));
	gl_FragColor = vec4( color, 1.0 );
}