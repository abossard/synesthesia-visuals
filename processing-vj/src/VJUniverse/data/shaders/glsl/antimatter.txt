// By @paulofalcao
// Blobs
// modded by @simesgreen
// revealed by @psonice_cw

// @rotwang: @mod+ hsv color change  

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

vec3 hsv2rgb(float h,float s,float v) {
	return mix(vec3(1.),clamp((abs(fract(h+vec3(3.,2.,1.)/3.)*6.-3.)-1.),0.,1.),s)*v;
}

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

   vec2 p=(gl_FragCoord.xy/resolution.x)*2.0-vec2(1.0,resolution.y/resolution.x);

   float t = time*0.2;
   //float t = 10.0;

   vec2 a = vec2(1e10, 0);
   a = minDist(a, 1.0, makePoint(p, vec2(9.3,2.9), vec2(0.1,0.1), t));
   a = minDist(a, 2.0, makePoint(p, vec2(1.9,2.0), vec2(0.4,0.4), t));
   a = minDist(a, 3.0, makePoint(p, vec2(0.8,0.7), vec2(0.4,0.5), t));
   a = minDist(a, 4.0, makePoint(p, vec2(2.3,0.1), vec2(0.6,0.3), t));
   a = minDist(a, 5.0, makePoint(p, vec2(0.8,1.7), vec2(0.5,0.4), t));
   a = minDist(a, 6.0, makePoint(p, vec2(0.3,1.0), vec2(0.4,0.4), t));
   a = minDist(a, 7.0, makePoint(p, vec2(1.4,1.7), vec2(0.4,0.5), t));
   a = minDist(a, 8.0, makePoint(p, vec2(1.3,2.1), vec2(0.6,0.3), t));
   a = minDist(a, 9.0, makePoint(p, vec2(1.8,1.7), vec2(0.5,0.4), t));     

   float i = a.x * 20.0;
	
	vec3 rgb = hsv2rgb( atan(i,p.x),0.9,0.8);
	
   gl_FragColor = vec4(rgb, 1.0);
}