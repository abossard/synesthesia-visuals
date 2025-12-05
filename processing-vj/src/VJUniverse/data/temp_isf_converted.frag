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

uniform float scale;
uniform float rate;
uniform float loops;
uniform float density;
uniform float depth;
uniform float detail;
uniform float Xr;
uniform float Yr;
uniform float Zr;
uniform float R;
uniform float G;
uniform float B;
uniform vec2 lightpos;

// Flip Y coordinate to match ISF expectations (Y=0 at bottom)
vec2 isf_FragCoord = vec2(gl_FragCoord.x, resolution.y - gl_FragCoord.y);
#define TIME time
#define RENDERSIZE resolution
#define isf_FragNormCoord (isf_FragCoord / resolution)
#define FRAMEINDEX int(time * 60.0)

////////////////////////////////////////////////////////////
// FractilianSpongeOfDoom   by mojovideotech
//
// based on 
// shadertoy.com\/MdKyRw  by wyatt
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////


vec4 light;
float T;
mat2 m,n,nn;

float map (vec3 p) {
    float t = 2.5, d = length(p-light.xyz)-light.w;
    d = min(d,max(10.0-p.z, 0.0));
    for (int i = 0; i < 20; i++) {
    	if (float (i) >depth) break;
        t = t*0.66;
        p.xy = m*p.xy;
        p.yz = n*p.yz;
        p.zx = nn*p.zx;
        p.xz = abs(p.xz) - t;
    }
    d = min(d,length(p)-density*t);
    return d;
}

vec3 norm (vec3 p) {
    vec2 e = vec2 (detail, 0.0);
    return normalize(vec3(
        map(p+e.xyy) - map(p-e.xyy),
        map(p+e.yxy) - map(p-e.yxy),
        map(p+e.yyx) - map(p-e.yyx)));
}

vec3 ray (vec3 r, vec3 d) {
    for (int i = 0; i < 40; i++) {
        if (float (i) >loops) break;
        r += d*map(r);
    }
    return r;
}

mat2 rot (float s) { return mat2(sin(s),cos(s),-cos(s),sin(s)); }

void main() 
{
    vec2 v = (isf_FragCoord.xy/RENDERSIZE.xy*2.0-1.0)*scale;
	v.x *= RENDERSIZE.x/RENDERSIZE.y;
    T = rate*TIME*10.0;
    m = rot(Xr*T);
    n = rot(Yr*T);
    nn = rot(Zr*T);
    vec3 r = vec3(0.0,0.0,-15.0+2.0*sin(0.01*T));
    light = vec4(10.0*sin(0.01*T),lightpos.xy,1.0);
    vec3 d = normalize(vec3(v,5.0));
    vec3 p = ray(r,d);
    d = normalize(light.xyz-p);
    vec3 no = norm(p);
    vec3 col = vec3(R,G,B)+0.25;
    vec3 bounce = ray(p+0.01*d,d);
    col = mix(col,vec3(0.0),dot(no, normalize(light.xyz-p)));
    if (length(bounce-light.xyz) > light.w+0.1) col *= 0.2;
    gl_FragColor = vec4(col,1.0);
}
