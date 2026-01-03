#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

   vec2 pos = -1.0 + 2.0*gl_FragCoord.xy / resolution.xy;
   float energy = 0.01;
   
   for (float i=0.0; i<16.0; i+=1.0) {
      vec2 starPos = vec2( 0.4*sin(i + time), 0.4*cos(i*i + time) );
      energy += pow( cos( distance ( pos, starPos ) ), 64.0 );
   }
   
   gl_FragColor = vec4( energy/2.0, energy/2.0, energy, 1.0 );
}