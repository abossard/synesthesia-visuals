#ifdef GL_ES
precision highp float;
#endif

uniform vec2 resolution;
uniform float time;
const int NaN=256;




float udRoundBox( vec3 p, vec3 b, float r )
{
  return length(max(abs(p)-b,0.0))-r;
}

float displacement(vec3 p) {
	return (sin((1.75*p.x)*cos(time*3.14159))*sin((1.75*p.y)*-sin(time*3.14159))*sin(.75*p.z));
}


float opDisplace( vec3 p )
{
    float d1 = udRoundBox(p, vec3(0.75,0.2,0.5), 0.15);
    float d2 = displacement(p);
    return d1+d2;
}


float sceneDistance (vec3 p) {
	// repeater
	vec3 c = vec3 (3., 3., 2.5);
	vec3 xx = mod (p,c)-0.5*c;
	
	return (opDisplace(xx));
}



void main(void){
  vec2 vPos=-1.0+2.0*gl_FragCoord.xy/resolution.xy;

  //Camera animation
  vec3 vuv=vec3(0,1,0);//Change camere up vector here
  vec3 vrp=vec3(0,1,0); //Change camere view here
  vec3 prp=vec3(0.0,2.,time); //Change camera path position here

  //Camera setup
  vec3 vpn=normalize(vrp-prp);
  vec3 u=normalize(cross(vuv,vpn));
  vec3 v=cross(vpn,u);
  vec3 vcv=(prp+vpn);
  vec3 scrCoord=vcv+vPos.x*u*resolution.x/resolution.y+vPos.y*v;
  vec3 scp=normalize(scrCoord-prp);

  //Raymarching
  const vec3 e=vec3(0.1,0,0);
  const float maxd=64.0; //Max depth

  vec3 c,p,n;

  float f=0.0;
  float objDist=1.0;
  for(int i=0;i<NaN;i++){
    if (abs(objDist)<.005||f>maxd) break;
    f+=objDist;
    p=prp+scp*f;
    objDist=sceneDistance(p);
  }
  
  if (f<maxd){
    c = vec3 (0.1, 0.1, 1.0);	 
	  vec3 fc;
    n=normalize(
      vec3(objDist-sceneDistance(p-e.xyy),
           objDist-sceneDistance(p-e.yxy),
           objDist-sceneDistance(p-e.yyx)));
    float b=dot(n,-scp);
	  fc = b*c;
    gl_FragColor=vec4((b*c+pow(b,8.0))*(1.0-f*.01),1.0);//simple phong LightPosition=CameraPosition
  }
  else
    gl_FragColor=vec4(0,0,0,1); //background color
}