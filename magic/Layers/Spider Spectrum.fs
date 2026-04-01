/*{
  "CATEGORIES": [
    "Automatically Converted",
    "Shadertoy"
  ],
  "DESCRIPTION": "Automatically converted from https://www.shadertoy.com/view/4ddSDS by aiekick.  Based on shane shader : [url=https://www.shadertoy.com/view/ll2SRy]Transparent Cube Field[/url]",
  "IMPORTED": {},
  "INPUTS": [
    {
      "DEFAULT": 1.8,
      "LABEL": "twist",
      "MAX": 5,
      "MIN": 1,
      "NAME": "twist",
      "TYPE": "float"
    },
    {
      "DEFAULT": 1,
      "LABEL": "speed",
      "MAX": 1,
      "NAME": "speed",
      "TYPE": "float"
    },
    {
      "DEFAULT": 15,
      "LABEL": "fade",
      "MAX": 50,
      "MIN": 0,
      "NAME": "fade",
      "TYPE": "float"
    },
    {
      "LABEL": "twist2",
      "MAX": 20,
      "MIN": 0,
      "NAME": "twist2",
      "TYPE": "float"
    },
    {
      "LABEL": "cork",
      "MAX": 4,
      "MIN": 0,
      "NAME": "cork",
      "TYPE": "float"
    },
    {
      "DEFAULT": 1,
      "LABEL": "opacity",
      "MAX": 1,
      "MIN": 0,
      "NAME": "opacity",
      "TYPE": "float"
    },
    {
      "DEFAULT": 1,
      "LABEL": "clip",
      "MAX": 1,
      "MIN": 0,
      "NAME": "clip",
      "TYPE": "float"
    }
  ],
  "ISFVSN": "2"
}*/


// Created by Stephane Cuillerdier - @Aiekick/2016
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
// Tuned via XShade (http://www.funparadigm.com/xshade/)

/* 
	Based on shane shader : https://www.shadertoy.com/view/ll2SRy
*/

mat3 getRotZMat(float a){return mat3(cos(a),-sin(a),0.,sin(a),cos(a),0.,0.,0.,1.);}

float dstepf = 0.0;

float map(vec3 p)
{
	p.x += sin(p.z*twist);
    p.y += cos(p.z*twist2) * sin(p.x*cork);
	p *= getRotZMat(p.z*0.8+sin(p.x)+cos(p.y));
    p.xy = mod(p.xy, 0.3) - 0.15;
	dstepf += 0.003;
	return length(p.xy);
}

void main() {

	vec2 uv = (gl_FragCoord.xy - RENDERSIZE.xy*.5 )/RENDERSIZE.y;
    vec3 rd = normalize(vec3(uv, (1.-dot(uv, uv)*.5)*.5)); 
    vec3 ro = vec3(0, 0, TIME*1.26*speed), col = vec3(0), sp;
	float cs = cos( TIME*0.375*speed ), si = sin( TIME*0.375*speed );    
    rd.xz = mat2(cs, si,-si, cs)*rd.xz;
	float t=0.06, layers=0., d=0., aD;
    float thD = 0.02;
	for(float i=0.; i<150.; i++)	
	{
        if(layers>15. || col.x > 1. || t>5.6) break;
        sp = ro + rd*t;
        d = map(sp); 
        aD = (thD-abs(d)*fade/16.)/thD;
        if(aD>0.) 
		{ 
            col += aD*aD*(3.-2.*aD)/(1. + t*t*0.25)*.2*opacity; 
            layers++; 
		}
        t += max(d*.7, thD*1.5) * dstepf *clip; 
	}
    col = max(col, 0.);
    col = mix(col, vec3(min(col.x*1.5, 1.), pow(col.x, 2.5), pow(col.x, 12.)), 
              dot(sin(rd.yzx*8. + sin(rd.zxy*8.)), vec3(.1666))+0.4);
    col = mix(col, vec3(col.x*col.x*.85, col.x, col.x*col.x*0.3), 
             dot(sin(rd.yzx*4. + sin(rd.zxy*4.)), vec3(.1666))+0.25);
	gl_FragColor = vec4( clamp(col, 0., 1.), 1.0 );
}
