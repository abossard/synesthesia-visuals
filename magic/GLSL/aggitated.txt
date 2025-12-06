// By @paulofalcao
// Blobs
// modded by @simesgreen
// revealed by @psonice_cw

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// returns distance to point
float makePoint(vec2 x, vec2 f, vec2 s, float t){
   vec2 p = vec2(sin(t*f.x), cos(t*f.y)) * s;
   return 
	   length(p - x);
}

vec2 minDist(vec2 mind, float i, float d)
{
   return min(mind, d);
   //return (d < mind.x) ? vec2(d, i) : mind;
}

void main( void ) {

   vec2 p=(gl_FragCoord.xy/resolution.x)*2.5-vec2(1.0,resolution.y/resolution.x);

   float t = time*0.3;
   //float t = 10.0;

   vec2 a = vec2(1e10, 0);
   a = minDist(a, 1.0, makePoint(p, vec2(sin(t + 10.0),2.9), vec2(0.1,0.1), t));
   a += minDist(a, 2.0, makePoint(p, vec2(1.9,2.0), vec2(0.4,0.4), t));
   a *= minDist(a, 3.0, makePoint(p, vec2(0.8,sin(t)), vec2(sin(t),0.5), t));
   a += minDist(a, 4.0, makePoint(p, vec2(2.3,sin(t)), vec2(0.6,0.3), t));
   a *= minDist(a, 5.0, makePoint(p, vec2(0.8,1.7), vec2(0.5,0.4), t));
   a += minDist(a, 6.0, makePoint(p, vec2(sin(t + 5.0),1.0), vec2(sin(t + 3.0),cos(t)), t));
   a *= minDist(a, 7.0, makePoint(p, vec2(1.4,1.7), vec2(0.4,0.5), t));
   a += minDist(a, 8.0, makePoint(p, vec2(sin(t),2.1), vec2(0.6,0.3), t));
   a *= minDist(a, 9.0, makePoint(p, vec2(1.8,1.7), vec2(0.5,0.4), t));     

   float i = a.x * 10.0;
	
   vec3 colour = vec3(1.0, 0.5 * i, 1.0 * i);
   gl_FragColor = vec4(3.0 - colour, 1.0);
}