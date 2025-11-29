/*{
  "CREDIT": "by mojovideotech",
  "CATEGORIES" : [
    "generator",
    "Truchet"
  ],
  "DESCRIPTION" : "",
  "INPUTS" : [
    {
        "NAME" :      "spin",
        "TYPE" :      "point2D",
        "DEFAULT" :   [ 0.2, 0.1 ],
        "MAX" :       [ 1.0, 1.0 ],
        "MIN" :       [ 0.0, 0.0 ]
    },
    {
        "NAME":       "seedX",
        "TYPE":       "float",
        "DEFAULT":    91.45,
        "MIN":        11.0,
        "MAX":        433.0
    },
    {
        "NAME":       "seedY",
        "TYPE":       "float",
        "DEFAULT":    243.21,
        "MIN":        17.0,
        "MAX":        439.0
    },
    {
        "NAME":       "grid",
        "TYPE":       "float",
        "DEFAULT":    6.0,
        "MIN":        0.1,
        "MAX":        10.0
    },
    {
        "NAME":       "spotlight",
        "TYPE":       "float",
        "DEFAULT":    0.85,
        "MIN":        0.0,
        "MAX":        1.0
    },
    {
        "NAME":       "edge",
        "TYPE":       "float",
        "DEFAULT":    7.5,
        "MIN":        1.0,
        "MAX":        12.0
    },
    {
        "NAME":       "glow",
        "TYPE":       "float",
        "DEFAULT":    21.0,
        "MIN":        1.0,
        "MAX":        24.0
    },
    {
        "NAME":       "fill",
        "TYPE":       "float",
        "DEFAULT":    0.3,
        "MIN":        0.0,
        "MAX":        0.5
    },    
    {
        "NAME":       "freq",
        "TYPE":       "float",
        "DEFAULT":    0.99,
        "MIN":        0.9,
        "MAX":        1.0
    },
    {
        "NAME":       "pulse",
        "TYPE":       "float",
        "DEFAULT":    1.3,
        "MIN":        0.5,
        "MAX":        2.0
    },
    {
        "NAME":       "pulserate",
        "TYPE":       "float",
        "DEFAULT":    1.5,
        "MIN":        0.1,
        "MAX":        5.0
    },
    {
        "NAME":       "thickness",
        "TYPE":       "float",
        "DEFAULT":    1.2,
        "MIN":        -5.0,
        "MAX":        5.0
    },
    {
        "NAME":       "scale",
        "TYPE":       "float",
        "DEFAULT":    0.3,
        "MIN":        0.01,
        "MAX":         1.0
    },
    {
        "NAME":       "rate",
        "TYPE":       "float",
        "DEFAULT":    3.0,
        "MIN":        1.0,
        "MAX":        5.0
    }
  ],
   "ISFVSN" :   "2.0"
}
*/


////////////////////////////////////////////////////////////////////
// TruchetDualLevelSpin  by mojovideotech
//
// based on :
// shadertoy.com\/view\/ltcfz2 by Shane
//
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////////////



#define     twpi    6.2831853   // two pi, 2*pi

vec2 hash22(vec2 p) { 
    return fract(sin(vec2(262144, 32768))*sin(dot(p*vec2(seedX,seedY), vec2(57, 27))));
}
 
vec2 rot( vec2 p ) {
    float c = cos(TIME*spin.x), s = sin(TIME*spin.y);
    mat2  m = mat2(c,-s,s,c);
    return vec2(m*p.xy);
}

void main() 
{
    float T = TIME * rate;             
    float iRy = min(RENDERSIZE.y, 600.0);
    vec2 uv = (gl_FragCoord.xy - RENDERSIZE.xy*0.5)/iRy;
    uv = rot(uv); 
    vec2 oP = uv*12.0 + vec2(0.5, T*0.5);
    vec2 d = vec2(1e5), rndTh = vec2(freq, 1.0);
    float dim = scale;    
    for(int k=0; k<2; k++) {
		vec2 ip = floor(oP*dim);
        vec2 rnd = hash22(ip);
        if(rnd.x<rndTh[k]) {
        	float hd = 0.5/dim;
            vec2 p = oP - (ip + 0.5)/dim;
 		    d.y = abs(max(abs(p.x), abs(p.y)) - hd) - 0.333/grid;
            p.y *= rnd.y>0.5? 1.0 : -1.0;
            float aw = 0.5/3.0/dim;
            p = p.x>-p.y? p : -p.yx;
            d.x = abs(length(p - hd) - hd) - aw;
            d.x *= k==1? -1.0 : 1.0;
            d.x = min(d.x, (length(abs(p) - hd) - aw));
            d.x -= 0.05*thickness;
            d.x -= (sin(TIME*pulserate)*0.075*pulse);
            break;
        } 
        dim *= 2.0;
    }
    
    vec3 col = vec3(0.0);
    float fo = (10.1-grid)/iRy;
    col = mix(col, vec3(0.0), (1.0 - smoothstep(0.0, fo*5.0, d.y - 0.1))*0.15); 
    col = mix(col, vec3(1.0), (1.0 - smoothstep(0.0, fo, d.y))*0.15);
    fo = glow/iRy/sqrt(dim);
    float sh = max(0.75 - d.x*edge, 0.0); 
    sh *= clamp(-sin(d.x*twpi*edge) + 1.0, 0.25, 1.0) + 0.0025; 
    col = mix(col, vec3(0.0), (1.0 - smoothstep(0.0, fo*5.0, d.x))*0.5); 
    col = mix(col, vec3(0.0), 1.0 - smoothstep(0.0, fo, d.x));    
    col = mix(col, vec3(0.3)*sh, 1.0 - smoothstep(0.0, fo, d.x + 0.51-fill)); 
    col = mix(col, vec3(0.2, 0.3, 0.9)*sh, 1.0 - smoothstep(0.0, fo, abs(d.x + 0.12) - 0.02));
    col = mix(col, col.gbr, uv.y*0.5 + 0.5);
    col = mix(col, col*max(1.1 - length(uv)*0.95, 0.0), spotlight);
    
    gl_FragColor = vec4(sqrt(max(col, 0.0)), 1.0);
}
