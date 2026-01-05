#ifdef GL_ES
precision mediump float;
#endif

uniform vec2 resolution;
uniform float time;
uniform vec2 mouse;

float PI = 3.14159265;
float pcol, pc, pc2;

//uniform float backlight;


//Raymarching Distance Fields
//About http://www.iquilezles.org/www/articles/raymarchingdf/raymarchingdf.htm
//Also known as Sphere Tracing
//IQs sphere (http://www.iquilezles.org/www/articles/distfunctions/distfunctions.htm)
//Shamless plagarism by Cmen. Also a GPU sucking nightmare

vec2 planesim(vec2 p,float s){
   vec2 ret=p; 
   ret=p+s/2.0;
   ret=fract(ret/s)*s-s/2.0;
   return ret;
}

vec2 ObjUnion(in vec2 obj0,in vec2 obj1){
  if (obj0.x<obj1.x)
  	return obj0;
  else
  	return obj1;
}

//Scene Start
void computePolar(in vec2 p)
{
    	vec2 rA = vec2(1.25,atan(p.x,p.y));
  	
  	rA.x += sin(rA.y * 3.0 + time)
          * sin(rA.y * 4.0 + (time * 2.8));
  	
  	//projection onto cartesian coordinates.
      	vec2 proj = vec2(rA.x * cos(rA.y), rA.x * sin(rA.y));
  	//pcol = (abs(proj.x) > abs(p.x) && abs(proj.y) > abs(p.y)) ? 1.0 - abs(sin(proj.x + time)) : 0.2 + abs(sin(proj.x + time));
        
  	p.x += sin(time + rA.x) * 0.4;
  	p.y += sin(time * 0.4) * 0.2;

  	
  	pc = abs(sin(length(p) * 4.0 + time + (rA.x * sin(p.y * 2.0 + time)))) * (sin(length(p) * 4.0 + time * 3.0)) * 1.0; 
  	//pc2 = abs(sin(pow(length(p), -1.0) + time)) * abs(sin(proj.x + time)) * 0.7; 	
}

//Floor
vec2 obj0(in vec3 p)
{
  //obj deformation
  //computePolar(p);
	computePolar(p.xz);
  
  p.y=p.y+sin(sqrt(p.x*p.x+p.y*p.y+p.z*p.z)-time*5.*0.5)*0.5;
  p.y += 0.1+ pc * 0.05;
  return vec2(p.y+2.5,0);
}

//Floor Color
vec3 obj0_c(in vec3 p)
{
	
  	// terrible colour scheme
  	//vec3 rgb = vec3(mix(pcol*0.2,pc2 * 0.5,0.5),mix(pcol,pc * 0.2,2.2),mix(pc2 * 0.5,pc* 0.5,abs(sin(time))));
	//rgb = mix(rgb, vec3(length(p) * 0.1), -1.0);
  	//rgb = 0.2-mix(rgb * 0.5, rgb.zyx * 0.5,0.5 + sin(time) * 1.0);
  	//rgb = vec3(c);
  	//return rgb;
  	float c = 1.0+sin(length(p.xz) * 1.0 + time);
  	return vec3(0.8 * c,0.7 * c, 0.4);
}


vec2 obj1(in vec3 p)
{
  //obj repeating
  vec2 p2=planesim(vec2(p.x,p.z),4.0);
  p.y -= 2.5;
  p2.x += sin(p.y * 2.0 + (time * 2.5) + p.z) * 0.5;
  p2.y += sin(p.y * 6.5 + (time * 2.0) +  p.x) * 0.2;
  p.y += sin(length(p.xz) * 0.4 + time) * 2.0; 
  float d=length(vec3(p2.x,p.y,p2.y))-1.0;
  return vec2(d,1); 
  
  
  //p.x = p.x;
  //p.z = p.z;
  

  

 }

//sphere with simple solid color
vec3 obj1_c(in vec3 p)
{
	return vec3(0.9,0.1,0.1);
}

vec2 inObj(in vec3 p){
  return min(obj0(p),obj1(p));
}

void main(void)
{
  vec2 vPos=-1.0+2.0*gl_FragCoord.xy/resolution.xy;

  //animate
  //Camera animation
  //Camera animation
  vec3 vuv=vec3(0,1,sin(time*0.1));//Change camere up vector here
  vec3 prp=vec3(-sin(time*0.15)*2.0,-1,cos(time*0.05)*8.0); //Change camera path position here
  vec3 vrp=vec3(0,0,-2.); //Change camere view here
  //camera
  vec3 vpn=normalize(vrp-prp);
  vec3 u=normalize(cross(vuv,vpn));
  vec3 v=cross(vpn,u);
  vec3 vcv=(prp+vpn);
  vec3 scrCoord=vcv+vPos.x*u*resolution.x/resolution.y+vPos.y*v;
  vec3 scp=normalize(scrCoord-prp);

  //Raymarching
  //refine edge w .01
  const vec3 e=vec3(0.1,0,0);
  vec2 s=vec2(0.1,0.0);
  vec3 c,p,n;
  float maxf = 32.0;
	float f=0.;
	for(int i=0;i<256;i++)
	{
		if (abs(s.x)<.01||f>maxf) break;
		f+=s.x;
		p=prp+scp*f;
		s=inObj(p);
	}
  
	if (f<maxf)
	{
	if (p.y<-1.0)
      c=obj0_c(p);
    else
      c=obj1_c(p);
      
    		n=normalize(
		vec3(s.x-inObj(p-e.xyy).x, s.x-inObj(p-e.yxy).x, s.x-inObj(p-e.yyx).x));
		float b=dot(n,normalize(prp-p));
		gl_FragColor=vec4((b*c+pow(b,20.))*(1.0-f*.04),1.);//simple phong LightPosition=CameraPosition
	}
	
  else 
  {
   gl_FragColor=vec4(mix(0.1,0.0,scp.y),0.0,0.0,0.2); //background color
}
}