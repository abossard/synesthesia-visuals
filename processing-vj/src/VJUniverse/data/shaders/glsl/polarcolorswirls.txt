#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 resolution;
uniform vec4 mouse;
uniform sampler2D tex0;
uniform sampler2D tex1;


vec4 textureRND2D(vec2 uv){
	uv = floor(fract(uv)*1e3);
	float v = uv.x+uv.y*1e3;
	return fract(1e5*sin(vec4(v*1e-2, (v+1.)*1e-2, (v+1e3)*1e-2, (v+1e3+1.)*1e-2)));
}

float noise(vec2 p) {
	vec2 f = fract(p*1e3);
	vec4 r = textureRND2D(p);
	f = f*f*(3.0-2.0*f);
	return (mix(mix(r.x, r.y, f.x), mix(r.z, r.w, f.x), f.y));	
}

float cloud(vec2 p) {
	float v = 0.0;
	v += noise(p*1.)*.50000;
	v += noise(p*2.)*.25000;
	v += noise(p*4.)*.12500;
	v += noise(p*8.)*.06250;
	v += noise(p*16.)*.03125;
	return v*v*v;
}

vec3 plasma(vec2 uv)
{
   float x = uv.x*400.;
   float y = uv.y*400.;
   float mov0 = x+y+cos(sin(time)*2.)*100.+sin(x/100.)*1000.;
   float mov1 = y / resolution.y / 0.2 + time;
   float mov2 = x / resolution.x / 0.2;
   float c1 = abs(sin(mov1+time)/2.+mov2/2.-mov1-mov2+time);
   float c2 = abs(sin(c1+sin(mov0/1000.+time)+sin(y/40.+time)+sin((x+y)/100.)*3.));
   float c3 = abs(sin(c2+cos(mov1+mov2+c2)+cos(mov2)+sin(x/1000.)));
   return vec3(c1,c2,c3);   
}


void main(void)
{
    vec2 p = -1.0 + 2.0 * gl_FragCoord.xy / resolution.xy;
    vec2 m = -1.0 + 2.0 * mouse.xy / resolution.xy;

	float frametime=time*2.0;


	float i=(((p.x+1.0)/2.0)*40.0);
    float j=(((p.y+1.0)/2.0)*30.0);
	

	//float x = p.x;
	//float y = p.y;
	float q;


#define pi 3.141592653589793238462643383279

    float intens = 1.0;
	float intens2 = 0.0;
	float x,y;
	float x_2, y_2;
	
	
// EFFECT 1
/*
    x=i*0.05;
    y=j*0.05;    x+=y*exp(sin(x+frametime*0.7)*1.0)*0.52389;
    y+=(1.0-x)*exp(cos(y+frametime*4.2345)*1.0)*0.3;
    x+=(1.0-y)*exp(cos(y+frametime*2.0)*1.0)*0.24;
    y+=x*exp(sin(x+frametime*1.5234)*1.0)*0.3235;
    x+=y*(1.0-y)*sin(x+y+frametime*2.54)*0.3235;
*/

// EFFECT 2	
   float fak=(1.0-exp((0.0-frametime)*0.3))*64.0;
   float arms = 2.0;
   
	float cj=(j-sin(frametime*0.5)*13.0-15.0);
   float ci=i-cos(frametime*1.3)*16.0-20.0;
   float cj2=(j-sin(1.234+frametime*.1)*13.0-15.0);
   float ci2=i-cos(2.342+frametime*0.443)*16.0-20.0;
   float at1=arms*atan(ci,cj);
   float at2=atan(ci2,cj2);
   x=i*0.05*(30.0+fak+fak*(1.0+sin((ci2-cj2)/10.0))*sin(frametime+2.0*(0.5*(at1+at2))))/256.0;
   y=j*0.05*(30.0+fak+fak*(1.0+cos((ci-cj)/10.0))*cos(frametime+2.0*(0.5*(at1+at2))))/256.0;
	
   intens = (sin(4.0*frametime+2.0*((at1+at2)))+1.0)/2.0;
   x_2 = sin(x*2.0);
   y_2 = cos(y*2.0);	
   intens2 = 1.0-intens;
	
// EFFECT 3
/*
	float x2,y2,g;

    x2=x=i*0.05;
    y2=y=j*0.05;

    float f1=(1.0+sin(sin(x)+frametime*0.7)+cos(sin(y)+frametime*0.3));
    float f2=0.5+0.5*sin(x+y+frametime*1.4);
    x+=max(f1,f2);

    f1=(1.0+cos(sin(y)+frametime*0.345)+sin(sin(x)+frametime*0.64));
    f2=0.5+0.5*cos(y+x+frametime*1.3);
    y+=max(f1,f2);

    x2+=(1.0+sin(sin(x2)+frametime*0.25)+cos(sin(y2)+frametime*0.3));
    y2+=(1.0+cos(sin(y)+frametime*0.565)+sin(sin(x2)+frametime*0.64));
	
	x=max(x,x2);
    y=max(y,y2);

	intens=((sin(x*4.0+frametime)*cos(y*4.0+frametime))+1.0)/2.0;

*/
// EFFECT 4
/*	
    float movex=-frametime*0.3;
    float movey=sin(frametime*0.15)*2.0;
    float wobyf=7.0;
    float wobyi=0.25;
    float wobyp=frametime*0.52635;
    float twistf=0.0;
    float twisti=0.0;
    float twistp=frametime*0.9;
    float flt=(1.0+sin(frametime*2.0))*0.5;
    float highfi;
    float lowfi;

	
#define LOWFIIN 10.0
    lowfi=0.0;
//    if (frametime>LOWFIIN)
//      lowfi=4.0*(1.0-exp((LOWFIIN-frametime)*0.3));

#define HIGHFIIN 15.0
    highfi=0.0;
//    if (frametime>HIGHFIIN)
//      highfi=0.5*(1.0-exp((HIGHFIIN-frametime)*0.3));

#define WOBYIIN 5.0
    wobyi=0.4;
//    if (frametime>WOBYIIN)
//      wobyi=0.3*(1.0-exp((WOBYIIN-frametime)*0.3));	


#define TWISTIN 20.0
#define TWISTIN2 35.0
    twistf=0.0;
    twisti=0.0;
    if (frametime>TWISTIN)
    {
      twistf=3.0*(1.0-exp((TWISTIN-frametime)*0.5));
      twisti=0.5*(1.0-exp((TWISTIN-frametime)*0.5));
    }
    if (frametime>TWISTIN2)
      twistf+=6.0*(1.0-exp((TWISTIN2-frametime)*0.8));

    x=(i-20.5);
    y=(j-15.5);

	x+=cos(frametime*0.31234)*4.0;
    y+=sin(frametime*0.40454)*2.0;

    x+=highfi*sin(y*0.6+frametime*1.3-x*0.43);
    y+=highfi*cos(x*0.6+frametime*0.6+y*0.43);
    x+=lowfi*cos(y*0.1*(1.0+cos(frametime*0.1))+frametime*1.4+x*0.1234);

    q=atan(y,x)/(2.0*pi);
    x=sqrt(x*x+y*y);

    x*=1.0+sin(twistf*2.0*pi*q+twistp)*twisti;

    y=intens*(exp(-10.0*0.6/x)*1.3-0.3);

    x=5.0*(0.002*x)*flt+(1.0-flt)*5.0/x+movex;
    q+=movey+wobyi*sin(wobyf*x+wobyp);

    y=q;	

//	if (y>1.0) y=1.0;
//	if (y<0.0) y=0.0;
//	if (x>1.0) x=1.0;
//	if (x<0.0) x=0.0;

    x+=cos(time*0.31234)*4.0;
    y+=sin(time*0.40454)*2.0;

    x+=sin(y*0.6+time*1.3-x*0.43);
    y+=cos(x*0.6+time*0.6+y*0.43);
    x+=cos(y*0.1*(1.0+cos(time*0.1))+time*1.4+x*0.1234);

    float a1 = sin(p.y-m.y);
    float r1 = sqrt(dot(p-m,p-m));
    float a2 = atan(p.y+m.y,p.x+m.x);
    float r2 = sqrt(dot(p+m,p+m));
*/
	
	
    vec2 uv;
	
    uv.x = x;
    uv.y = y;
 
	
//    vec3 col = vec3(noise(uv/(4.*sin(time/3.0)+4.)), noise(uv/(4.*cos(time/6.0)+4.)), noise(uv/(4.*sin(time/4.0)+4.)));
//    col.x+=col.y/4.;
//    col.y+=col.x/3.;
//    col.z+=col.y/6.;
	

    gl_FragColor = vec4(plasma(uv)*intens,1.0);
}