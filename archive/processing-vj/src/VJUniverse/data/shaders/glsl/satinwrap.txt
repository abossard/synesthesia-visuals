#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


vec2 R = resolution;
vec2 Offset;
vec2 Scale=vec2(0.01,0.01);
float Saturation = 0.3; // 0 - 1;


vec3 lungth(vec2 x,vec3 c){
       return vec3(length(x+c.r),length(x+c.g),length(x+c.b));
}

void main( void ) {
    Offset = mouse.xy;
    vec2 x = gl_FragCoord.xy;
    vec4 c=vec4(0,0,0,0);
    x=x*Scale*R/R.x+Offset;
    x+=sin(x.yx*sqrt(vec2(13,9)))/5.;
    c.rgb=lungth(sin(x*sqrt(vec2(33,43))),vec3(5,6,7)*Saturation);
    x+=sin(x.yx*sqrt(vec2(73,53)))/5.;
    c.rgb=2.*lungth(sin(time+x*sqrt(vec2(33.,23.))),c.rgb/9.);
    x+=sin(x.yx*sqrt(vec2(93,73)))/2.;
    c.rgb=lungth(sin(x*sqrt(vec2(13.,1.))),c.rgb/2.0);
    c=.5+.5*sin(c*8.);
    c.a=1.;
    gl_FragColor = c;
}