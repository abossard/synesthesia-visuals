// see "Scalable Real-Time Animation of Rivers" https://hal.inria.fr/inria-00345903/

// noise-based variant: https://www.shadertoy.com/view/Xl3Gzj

#define r 1.5 // test distance      for efficiency, as small as it keep covering influencials river sides 
#define c 1.5 // boundary condition   < 1: slip condition   > 1 : no-slip condition

#define L(a,b) O+= 1e-3/length( clamp( dot(U-(a),v=b-(a))/dot(v,v), 0.,1.) *v - U+a ) // segments
    
float f(float d) { // interpolation function
    float t = 1.-d/r;
    return t<0. ? 0. :pow(d,-c)*(6.*t*t-15.*t+10.)*t*t*t;
}
void mainImage( out vec4 O, vec2 U )
{
	U /= iResolution.y;
    
    // --- interpolate stream function : add(distance to border, stream at border)
    float t = iTime,wf=0.,wT=0., w; 
#define add(d,phi)  w = f(d),  wf += w*phi,  wT += w;
    // river bed and obstacle geometry, + flux (diff of stream between river sides)
    add( length( U-vec2(.0+.2*sin(t) , .8)    ) -.3, 0.);   // rock1 stream=0.
    add( length( U-vec2(.3+.2*sin(t) , .5)    ) -.3, 0.);
    add( length( U-vec2(1.3, .8+.2*cos(2.*t)) ) -.5, .5);   // rock2 stream=.5
    add( length( U-vec2(.8+.2*cos(.5*t), -.2) ) -.4, 1.);   // rock3 stream=1.
    add( length( U-vec2(1.7, .15)             ) -.1,  .75); // rock4 stream=.75
    w = wf / wT;                               // stream field
    vec2 V = vec2(-dFdy(w), dFdx(w));          // velocity field
    
    // --- display
    if (w!=w) { O =  vec4(.5,0,0,0); return; } // in rocks   ( w!=w = NaN )
   	O = vec4(0,50.*length(V),sin(100.*w),0);   // draw |V| and iso-streams

    vec2 p = floor(U*30.+.5)/30., v;           // draw velocity vectors
    L ( p-V*2., p+V*2.);                               // L(vec2(.5,.5),p);
}
