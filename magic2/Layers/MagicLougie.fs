/*{
  "CREDIT": "by mojovideotech",
  "CATEGORIES": [
    "fractal"
  ],
  "DESCRIPTION": "",
  "INPUTS": [
    {
      "MAX": [
        1,
        1
      ],
      "MIN": [
        0.01,
        0.01
      ],
      "DEFAULT": [
        0.5,
        0.4
      ],
      "NAME": "matrix",
      "TYPE": "point2D"
    },
    {
      "NAME": "seed1",
      "TYPE": "float",
      "DEFAULT": 5,
      "MIN": 2,
      "MAX": 7
    },
    {
      "NAME": "seed2",
      "TYPE": "float",
      "DEFAULT": 29,
      "MIN": 23,
      "MAX": 37
    },
    {
      "NAME": "seed3",
      "TYPE": "float",
      "DEFAULT": 13,
      "MIN": 11,
      "MAX": 19
    },
    {
      "NAME": "offset1",
      "TYPE": "float",
      "DEFAULT": -1,
      "MIN": -3,
      "MAX": 3
    },
    {
      "NAME": "offset2",
      "TYPE": "float",
      "DEFAULT": 2,
      "MIN": -3,
      "MAX": 3
    },
    {
      "NAME": "offset3",
      "TYPE": "float",
      "DEFAULT": 1.5,
      "MIN": -3,
      "MAX": 3
    },
    {
      "NAME": "depth",
      "TYPE": "float",
      "DEFAULT": 128,
      "MIN": 18,
      "MAX": 216
    },
    {
      "NAME": "rate",
      "TYPE": "float",
      "DEFAULT": 6,
      "MIN": 1.1,
      "MAX": 60
    },
    {
      "NAME": "cycle",
      "TYPE": "float",
      "DEFAULT": 0.99,
      "MIN": 0.5,
      "MAX": 1.5
    },
    {
      "NAME": "multiplier",
      "TYPE": "float",
      "DEFAULT": 3,
      "MIN": 2,
      "MAX": 24
    },
    {
      "NAME": "scale",
      "TYPE": "float",
      "DEFAULT": 1.25,
      "MIN": -3,
      "MAX": 3
    }
  ]
}*/


////////////////////////////////////////////////////////////
// MagicLougie  by mojovideotech
//
// based on:
// glslsandbox.com/\e#28998.1
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////

#ifdef GL_ES
precision mediump float;
#endif

#define PI  6.283185307179586

float eps = 1.0/RENDERSIZE.y; 
const float stepScale = 0.25;
float stopThreshold = 2.0/RENDERSIZE.y;

float sphere(in vec3 p, in vec3 centerPos, float radius) {
	return length(p-centerPos) - radius;
}

float zoidBumps(in vec3 p){
	float TT = TIME / -rate;
	float CC = TIME * log(cycle);
	p+= CC;
    return mix((multiplier*(cos(p.x*seed1+TT*offset1)*cos(p.y*seed2+TT*offset2))*sin(p.z*seed3-TT*offset3)), 
    (multiplier*(sin(p.x*seed3+TT*offset2)*cos(p.y*seed1-TT*offset3)*cos(p.z*seed2-TT*offset1))),
    clamp(sin(0.75+mod(matrix.x,matrix.y)),matrix.x,matrix.y));
}
    
float scene(in vec3 p) {
	return sphere(p, vec3(0., 0. , 2.), 1.5) + 0.125*zoidBumps(p);
}

vec3 getNormal(in vec3 p) {
	return normalize(vec3(
		scene(vec3(p.x+eps,p.y,p.z))-scene(vec3(p.x-eps,p.y,p.z)),
		scene(vec3(p.x,p.y+eps,p.z))-scene(vec3(p.x,p.y-eps,p.z)),
		scene(vec3(p.x,p.y,p.z+eps))-scene(vec3(p.x,p.y,p.z-eps))));
}

float rayMarching( vec3 origin, vec3 dir, float start, float end ) {
	float rayDepth = start;
	float b = 1.0;
	for ( int i = 0; i < 216; i++ ) {
		b += 1.0;
    	if (b>depth) break;
		float sceneDist = scene( origin + dir * rayDepth );
		if (( sceneDist < stopThreshold ) || (rayDepth >= end)) {
			return rayDepth + sceneDist; 
		}
		rayDepth += sceneDist * stepScale;
	}
	return end;
}

void main(void) {
    vec2 aspect = vec2(RENDERSIZE.x/RENDERSIZE.y, 1.0)*scale; 
	vec2 screenCoords = (2.0*gl_FragCoord.xy/RENDERSIZE.xy - 1.0)*aspect;
	vec3 lookAt = vec3(0.25,-0.67,2.5);
	vec3 camPos = vec3(-0.5, 2.0, -1.5);
    vec3 forward = normalize(lookAt-camPos); 
    vec3 right = normalize(vec3(forward.z, 0., -forward.x )); 
    vec3 up = normalize(cross(forward,right)); 
    float FOV = 0.5;
    vec3 ro = camPos; 
    vec3 rd = normalize(forward + FOV*screenCoords.x*right + FOV*screenCoords.y*up);
    vec3 bgcolor = vec3(1.,0.97,0.92)*0.5;
    float bgshade = (1.0-length(vec2(screenCoords.x/aspect.x, screenCoords.y+1.5)+matrix)*0.8);
	bgcolor *= bgshade;
	float dist = rayMarching(ro, rd, 0.0, 4.0 );
	if ( dist >= 4.0 ) {
	    gl_FragColor = vec4(bgcolor, 1.0);
	    return;
	}
	vec3 sp = ro + rd*dist;
	vec3 surfNormal = getNormal(sp);
	float RR = TIME * (rate*0.0125);
	vec3 lp = vec3(cos(1.5*sin(RR)), 1.75-0.5*cos(RR), 0.0);
	vec3 ld = lp-sp;
	vec3 lcolor = vec3(0.925,0.97,0.92);
	float len = length( ld ); 
	ld /= len; 
	float lightAtten = min( 1.0 / ( 0.25*len*len ), 1.0 ); 
	vec3 ref = reflect(-ld, surfNormal); 
	vec3 sceneColor = vec3(0.0);
	vec3 objColor = vec3(0.7, 1.0, 0.3); 
	float bumps =  zoidBumps(sp);
   	objColor = clamp(objColor*0.8-vec3(0.4, 0.2, 0.1)*bumps, 0.0, 1.0);
	float ambient = .075; 
	float specularPower = 6.0; 
	float diffuse = max( 0.0, dot(surfNormal, ld) );  
	float specular = max( 0.0, dot( ref, normalize(camPos-sp)) ); 
	specular = pow(specular, specularPower); 
	sceneColor += lcolor*lightAtten*objColor*(diffuse*0.8+specular*0.5+ambient);
	gl_FragColor = vec4(clamp(sceneColor, 0.0, 1.0), 1.0);
}