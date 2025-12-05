#ifdef GL_ES
precision highp float;
precision highp int;
#endif

uniform float time;
uniform vec2 resolution;
uniform float bass;
uniform float mid;
uniform float treble;
uniform float level;
uniform float beat;

uniform vec2 spin;
uniform float seedX;
uniform float seedY;
uniform float grid;
uniform float spotlight;
uniform float edge;
uniform float glow;
uniform float fill;
uniform float freq;
uniform float pulse;
uniform float pulserate;
uniform float thickness;
uniform float scale;
uniform float rate;

#define TIME time
#define RENDERSIZE resolution
#define isf_FragNormCoord (gl_FragCoord.xy / resolution)
#define FRAMEINDEX int(time * 60.0)

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
