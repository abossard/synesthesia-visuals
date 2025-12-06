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

uniform vec2 grid;
uniform float density;
uniform float rate;
uniform float seed1;
uniform float seed2;
uniform float seed3;
uniform float offset1;
uniform float offset2;

#define TIME max(time, 0.001)
#define RENDERSIZE resolution
#define isf_FragNormCoord (gl_FragCoord.xy / resolution)
#define FRAMEINDEX int(time * 60.0)

///////////////////////////////////////////
// BitStreamer  by mojovideotech
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
//
// based on :
// www.patriciogonzalezvivo.com/2015/thebookofshaders/10/ikeda-03.frag
//
// from :
// thebookofshaders.com  by Patricio Gonzalez Vivo
///////////////////////////////////////////
 
float ranf(in float x) {
    return fract(sin(x)*1e4);
}

float rant(in vec2 st) { 
    return fract(sin(dot(st.xy, vec2(seed1,seed2)))*seed3);
}

float pattern(vec2 st, vec2 v, float t) {
    vec2 p = floor(st+v);
    return step(t, rant(100.+p*.000001)+ranf(p.x)*0.5 );
}

void main() {
    vec2 st = gl_FragCoord.xy/RENDERSIZE.xy;
    st.x *= RENDERSIZE.x/RENDERSIZE.y;
    st *= grid;
    
    vec2 ipos = floor(st);  
    vec2 fpos = fract(st);  
    vec2 vel = vec2(TIME*rate*max(grid.x,grid.y)); 
    vel *= vec2(-1.,0.0) * ranf(1.0+ipos.y); 
    vec2 off1 = vec2(offset1,0.);
    vec2 off2 = vec2(offset2,0.);
    vec3 color = vec3(0.);
    color.r = pattern(st+off1,vel,0.5+density/RENDERSIZE.x);
    color.g = pattern(st,vel,0.5+density/RENDERSIZE.x);
    color.b = pattern(st-off2,vel,0.5+density/RENDERSIZE.x); 
    color *= step(0.2,fpos.y);

    gl_FragColor = vec4(color,1.0);
}
