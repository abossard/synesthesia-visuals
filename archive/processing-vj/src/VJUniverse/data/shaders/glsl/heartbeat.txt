#ifdef GL_ES
precision highp float;
#endif

//The heart from shadertoy with 2 bytes added.
//Can you find them?

uniform float time;
uniform vec2 resolution;
uniform vec4 mouse;

void main(void)
{
    vec2 p = (2.0*gl_FragCoord.xy-resolution)/resolution.y;

	p.y -= 0.35;
    // animate
    float tt = mod(time,2.0)/2.0;
    float ss = pow(tt,.2)*0.5 + 0.5;
    ss -= ss*0.2*sin(tt*6.2831*5.0)*exp(-tt*6.0);
    p *= vec2(0.5,1.5) + ss*vec2(0.5,-0.5);

    
    float a = atan(p.x,p.y)/3.141593;
    float r = length(p);

    // shape
    float h = abs(a);
    float d = (18.0*h - 26.*h*h + 10.0*h*h*h*h)/(7.0-5.0*h);

    // color
    float f = step(r,d) * pow(1.0-r/d,0.25);

    gl_FragColor = vec4(f,0.0,0.0,1.0);
}