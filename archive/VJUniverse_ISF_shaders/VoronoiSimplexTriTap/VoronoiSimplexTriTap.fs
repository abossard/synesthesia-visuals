/*
{
  "CREDIT": "by mojovideotech",
  "CATEGORIES" : [
    "generator",
    "voronoi"
  ],
  "DESCRIPTION" : "",
  "INPUTS" : [
  {
    "NAME" :      "scale",
    "TYPE" :      "float",
    "DEFAULT" :   8.45,
    "MIN" :       4.0,
    "MAX" :       11.0
  },
  {
    "NAME" :      "rate",
    "TYPE" :      "float",
    "DEFAULT" :   3.9,
    "MIN" :       0.5,
    "MAX" :       5.0
  },
  {
    "NAME" :		"seed1",
    "TYPE" : 		"float",
    "DEFAULT" : 	113,
    "MIN" : 		8,
    "MAX" :			987
  },
  {
     "NAME" :		"seed2",
     "TYPE" :		"float",
     "DEFAULT" :	4444,
     "MIN" : 		89,
     "MAX" :		6765	
   },
   {
     "NAME" :		"seed3",
     "TYPE" :		"float",
     "DEFAULT" :	273009,
     "MIN" :		28657, 
     "MAX" :		514229
   },
   {
     "NAME" : 		"edge",
     "TYPE" :		"float",
     "DEFAULT" :	-0.025,
     "MIN" : 		-0.05,
     "MAX" : 		 0.05
    },
   {
    "NAME" :      "C1",
    "TYPE" :      "color",
    "DEFAULT" :   [ 0.6, 0.2, 0.4, 1.0 ]
  },
  {
    "NAME" :      "C2",
    "TYPE" :      "color",
    "DEFAULT" :   [ 0.15, 0.05, 0.5, 1.0 ]
  },
  {
    "NAME" :      "colorCycle",
    "TYPE" :      "float",
    "DEFAULT" :  -0.24,
    "MIN" :       -1.0,
    "MAX" :        1.0
  },
  {
    "NAME" :      "gamma",
    "TYPE" :      "float",
    "DEFAULT" :   0.1,
    "MIN" :       0.01,
    "MAX" :       0.3
  },
  {
	"NAME" : 	"invert",
    "TYPE" : 	"bool",
    "DEFAULT" : false
  }
 ],
   "ISFVSN" : 2.0
}
*/


////////////////////////////////////////////////////////////////////
// VoronoiSimplexTriTap  by mojovideotech
//
// based on :
// shadertoy.com\/view\/4lBSzW by Shane
//
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////////////


#define   	twpi    	6.283185307   		//	two pi, 2*pi
#define 	pi   		3.141592653 		// 	pi
#define		twthpi		0.26179938779915	//	twelfth pi, pi/12


vec2 hash22(vec2 p) { 
    float n = sin(dot(p,vec2(seed1, seed2))); 
    p *= fract(vec2(pi*n, n)*seed3);
    vec2 e = fract(sin(p)*43758.5453);
	return sin(e*twpi + TIME*rate);
}

float Voronoi3Tap(vec2 p){
    vec2 s = floor(p + (p.x + p.y)*.3660254);
    p -= s - (s.x + s.y)*.2113249;
    float i = p.x<p.y? 0. : 1.;
    float g = 0.125-edge;
    vec2 p1 = p - vec2(i, 1. - i) + .2113249, p2 = p - .5773502; 
    p += hash22(s)*g;
    p1 += hash22(s +  vec2(i, 1. - i))*g;
    p2 += hash22(s + 1.)*g;
    float d = min(min(dot(p, p), dot(p1, p1)), dot(p2, p2))/.425;
    return sqrt(d);
}

void main() {
	vec4 col = vec4(0.0,0.0,0.0,1.0);
	vec2 pos = (gl_FragCoord.xy - RENDERSIZE.xy*.5)/RENDERSIZE.y;
    vec2 uv = pos * mat2(cos(twthpi), sin(twthpi), -sin(twthpi), cos(twthpi))*(11.25-scale);
    float c = Voronoi3Tap(uv*5.);
    float c2 = Voronoi3Tap(uv*5. - scale/RENDERSIZE.y);
    vec2 r = normalize(hash22(pos));
	float pattern = cos(pi*r.x)*sin(r.y*pi)*.125 + .125;
    col.rgb = mix(vec3(c*1.3, c*c, pow(c, 20.0-scale)), C1.rgb, pattern );
    vec3 col2 = mix(C2.rgb, vec3(c*1.3, c*c, pow(c, 20.0-scale)), pattern );
    float CT = cos(TIME) * colorCycle;
    col.rgb = mix(col.rgb, col2, smoothstep(.2, .8, sin(CT+1.0/length(r.xy))*.333 - colorCycle));  
	col.rgb += C1.rgb*(c2*c2*c2 - c*c*c)*5.;
	col.rgb -= (length(hash22(uv + CT))*.06 - .03)*C2.rgb;
	if (invert) { col.rgb = col.brg; } 
    gl_FragColor = sqrt(max(col, 0.0)-0.2+gamma);
}

    
    
    
/*    
    
    
    float c = Voronoi3Tap(uv*8.);
    float c2 = Voronoi3Tap(uv*8. - scale/RENDERSIZE.y);
    vec2 r = normalize(hash22(pos));
	float pattern = cos(pi*r.x)*sin(r.y*pi)*.125 + .125;
    col.rgb = mix(vec3(c*C1.r, c*c, pow(c, 16.0-scale)), vec3(c*c*C2.b, c, c*c*C1.g), pattern );
    vec3 col2 = mix(vec3(c*C2.b, pow(c, C1.b), c*c), vec3(c*C2.g, c*c, pow(c, 16.0-scale)), pattern );
    float CT = TIME * colorCycle;
    col.rgb = mix(col.rgb, col2.rgb, smoothstep(.2, .8, sin(CT*cos(abs(colorCycle)))*.5 + .5)); // 
	col.rgb += C1.rgb*(c2*c2*c2 - c*c*c)*(3.+colorCycle);
	col.rgb += (length(hash22(uv + CT))*.05 - .025)*C2.rgb;
	if (invert) { col.rgb = col.gbr; } 
    gl_FragColor = sqrt(max(col, 0.0)-0.2+gamma);
}
*/