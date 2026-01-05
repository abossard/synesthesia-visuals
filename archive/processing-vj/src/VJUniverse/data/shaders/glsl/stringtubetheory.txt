#ifdef GL_ES
precision mediump float;
#endif

uniform vec2 resolution;
uniform float time;



//Raymarching Distance Fields
//About http://www.iquilezles.org/www/articles/raymarchingdf/raymarchingdf.htm
//Also known as Sphere Tracing
//IQs sphere (http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
//by George Toledo (severe tweak of a shader from glsl sandbox by "Dennis Hjorth tweak of original by @paulofalcao"). 
//Heavy influence by "704" //a 1k javascript demo (http://www.pouet.net/prod.php?which=56992)



vec2 ObjUnion(in vec2 obj0,in vec2 obj1){
  if (obj0.x<obj1.x)
  	return obj0;
  else
  	return obj1;
}

//Scene Start

//Floor//nah, snakes
vec2 obj0(in vec3 p)
{
  //obj deformation
  p.x=(p.x*4.)+cos(sqrt(p.x*p.x+p.y*p.y+p.z*p.z)-time*5.0);
  p.y=(p.y)+sin(sqrt(p.x*p.x+p.y*p.y+p.z*p.z)-time*2.5)*0.5;
 // p.y=(p.y)+sin(sqrt(p.x*p.x+p.y*p.y+p.z*p.z)-time*2.5)*0.5;
  return vec2(sin(p.y)*cos(p.z+time*4.)+1.0);
}
//snake Color
vec3 obj0_c(in vec3 p)
{
return vec3(0.4,0.6,0.8);
}


vec2 obj1(in vec3 p)
{
  //obj repeating
  p.x=fract(p.x+0.5)-0.5;
  p.z=fract(p.z+0.5)-0.5;
  p.y=(p.y)+5.0;


	vec3 q = abs(p.xyz);
 	vec2 b = vec2(max(q.z-sin(2.),max(q.x+q.y*0.57735,q.y)-1.75));
 	vec2 q2 = vec2(length(p.xz)+1.25,p.y);
	vec2 s = vec2(length(q2)-.5);

  //vec2 s = vec2(length(p)-sphere_scale);
  return vec2(mix(b,s,(sin(time*1.5))*.25)-.25);
 }

//sphere with simple solid color
vec3 obj1_c(in vec3 p)
{
	return vec3(1.,.1,.2);
}

vec2 inObj(in vec3 p){
  return min(obj0(p),obj1(p));
}

void main(void)
{
  vec2 vPos=-1.0+2.0*gl_FragCoord.xy/resolution.xy;

  //animate
  vec3 vuv=vec3(0,1,sin(time*0.1));//Change camera up vector here
  vec3 prp=vec3(sin(time*0.15)*2.0,sin(time*0.5)*1.0,cos(time*0.1)*8.0); //Change camera path position here
  vec3 vrp=vec3(0,0,1.); //Change camera view here


  //camera
  vec3 vpn=normalize(vrp-prp);
  vec3 u=normalize(cross(vuv,vpn));
  vec3 v=cross(vpn,u);
  vec3 vcv=(prp+vpn);
  vec3 scrCoord=vcv+vPos.x*u*resolution.x/resolution.y+vPos.y*v;
  vec3 scp=normalize(scrCoord-prp);

  //Raymarching
  //refine edge w .01
  const vec3 e=vec3(0.01,0,0);
  vec2 s=vec2(0.1,0.0);
  vec3 c,p,n;
  
	float f=0.;
	for(int i=0;i<256;i++)
	{
		if (abs(s.x)<.01||f>64.) break;
		f+=s.x;
		p=prp+scp*f;
		s=inObj(p);
	}
  
	if (f<64.)
	{
	if (p.y<0.0)
      c=obj0_c(p);
    else
      c=obj1_c(p);
      
    		n=normalize(
		vec3(s.x-inObj(p-e.xyy).x, s.x-inObj(p-e.yxy).x, s.x-inObj(p-e.yyx).x));
		float b=dot(n,normalize(prp-p));
		gl_FragColor=vec4((b*c+pow(b,25.))*(1.0-f*.02),1.);//simple phong LightPosition=CameraPosition
	}
	
  else gl_FragColor=vec4(.0,.0,.0,1.0); //background color
}