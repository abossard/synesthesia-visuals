// Frosted Glass
// the.savage@hotmail.co.uk

#ifdef GL_ES
precision highp float;
#endif

uniform vec2 resolution;
uniform vec2 mouse;

uniform float time;

//

const float fScale=0.1;
const float fHeight=100.0;
const float fEps=0.1;

const vec3 cBackground1=vec3(0.1,0.5,0.8);
const vec3 cBackground2=vec3(0.5,0.2,0.1);
const vec3 cAmbient=vec3(0.1,0.1,0.1);
const vec3 cDiffuse=vec3(0.1,0.5,0.3);
const vec3 cSpecular=vec3(1.0,1.0,1.0);
const vec3 cLight=vec3(1.0,1.0,0.0);

const float fBackground=0.0;
const float fAmbient=0.0;
const float fDiffuse=1.0;
const float fSpecularity=0.3;
const float fHardness=12.0;
const float fIntensity=0.0;
const float fOpacity=0.0;
const float fRefract=0.05;

//
//

vec3 mod289(vec3 x)
{
	return x-floor(x*(1.0/289.0))*289.0;
}

//
//

vec2 mod289(vec2 x)
{
	return x-floor(x*(1.0/289.0))*289.0;
}

//
//

vec3 permute(vec3 x)
{
	return mod289(((x*34.0)+1.0)*x);
}

//
//

float snoise(vec2 v)
{
	const vec4 C=vec4(0.211324865405187,0.366025403784439,-0.577350269189626,0.024390243902439);

	vec2 i=floor(v+dot(v,C.yy));
	vec2 x0=v-i+dot(i,C.xx);

	vec2 i1=(x0.x>x0.y)?vec2(1.0,0.0):vec2(0.0,1.0);
	vec4 x12=x0.xyxy+C.xxzz;

	x12.xy-=i1;
	i=mod289(i);

	vec3 p=permute(permute(i.y+vec3(0.0,i1.y,1.0))+i.x+vec3(0.0,i1.x,1.0));
	vec3 m=max(0.5-vec3(dot(x0,x0),dot(x12.xy,x12.xy),dot(x12.zw,x12.zw)),0.0);

	m=m*m;
	m=m*m;

	vec3 x=2.0*fract(p*C.www)-1.0;
	vec3 h=abs(x)-0.5;
	vec3 a0=x-floor(x+0.5);

	m*=1.79284291400159-0.85373472095314*(a0*a0+h*h);

	p.x=a0.x*x0.x+h.x*x0.y;
	p.yz=a0.yz*x12.xz+h.yz*x12.yw;

	return 130.0*dot(m,p);
}

//
//

float getDepth(const vec2 vPoint)
{
	return ((snoise(vPoint*fScale)+1.0)*0.5)*fHeight;
}

//
//

vec3 getNormal(const vec2 vPoint,const float fEps)
{
	vec2 v=vec2(fEps,0.0);

	return normalize(vec3(
		getDepth(vPoint+v.xy)-getDepth(vPoint-v.xy),
		getDepth(vPoint+v.yx)-getDepth(vPoint-v.yx),
		getDepth(vPoint)));
}

//
//

float getBlinnPhong(const vec3 vPoint,const vec3 vLight,const vec3 vNormal,const float fSpecular,const float fHardness)
{
	vec3 vHalf=normalize(vLight-vPoint);
	float fNdh=dot(vHalf,vNormal);

	return pow(max(0.0,fNdh),fHardness)*fSpecular;
}

//
//

float getLightIntensity(const vec2 vPoint,const vec3 vLight,const float fIntensity)
{
	float fDist=length(vPoint-vLight.xy);
	return clamp((1.0/(fDist*fDist))*fIntensity,0.0,1.0);
}

//
//

vec3 getBackground(const vec2 vPoint)
{
	vec2 vPixel1=vPoint;

	vec2 vScreen=resolution;
	vec2 vMouse=vec2(0.1,0.1)+mouse;

	float fTime=time*0.5;

	vec2 vPixel2=-1.0+2.0*vPixel1/vScreen;

	float n0=dot(vPixel2,vPixel2);
	float n1=atan(vPixel2.y,vPixel2.x);
	float n2=sqrt(n0);

	vec2 vPixel3=vec2(
		0.5*fTime+0.1/n2,
		n1/2.0)/0.01;

	vec3 v=vec3(
		vPixel3.x+vPixel3.y+cos(sin(fTime)*2.0)*100.0+sin(vPixel3.x/10.0)*100.0,
		(vPixel3.y/vScreen.y/1000.0)+fTime,
		vPixel3.x/vScreen.x/1000.0);

	float r=abs(sin(v.y+fTime)/2.0+v.z/2.0-v.y-v.z+fTime);
	float g=abs(sin(r+sin(v.x/50.0+fTime)+sin(vPixel3.y/50.0+fTime)+sin((vPixel3.x+vPixel3.y)/10.0)*1.0));
	float b=abs(sin(g+cos(v.y+v.z+g)+cos(v.z)+sin(v.x/100.0)));

	vec3 c=vec3(r,g,b); //*lines(vMouse.x*0.3,resolution.y*0.1,vMouse.xyx,vPixel1,fTime);
	if(n0>1.0) c=mix(c,vec3(0.0),(1.0-n0)*10.5);

	return clamp((1.0-c)*n2,0.0,1.0);
}

//
//

vec3 getColour(const vec2 vPoint)
{
	vec2 vScreen=resolution;
	vec2 vMouse=mouse;

	vec3 vLight=vec3(vMouse*vScreen,fHeight);
	vec3 vNormal=getNormal(vPoint,fEps);

	float fSpecular=getBlinnPhong(vec3(vPoint,-fHeight),vLight,vNormal,fSpecularity,fHardness);
	float fLight=getLightIntensity(vPoint,vLight,fIntensity)*fOpacity;

	vec3 cDiffuse=getBackground(vPoint);

	return (cAmbient*fAmbient)+(cDiffuse*fDiffuse)+(cSpecular*fSpecular)+(cLight*fLight);
}

//
//

vec3 getRefractColour(const vec2 vPoint,const float fRefract)
{
	vec2 vRefract=vPoint+((fRefract*2.0)-1.0);
	return getColour(vRefract);
}

//
//

vec3 getRefract(const vec2 vPoint,const float fRefract)
{
	return vec3(
		getRefractColour(vPoint,0.0).r,
		getRefractColour(vPoint,fRefract).g,
		getRefractColour(vPoint,fRefract*2.0).b);
}

//
//

void main(void)
{
	vec2 vPoint=gl_FragCoord.xy;
	gl_FragColor=vec4(getRefract(vPoint,getDepth(vPoint)*fRefract),1.0);
}
