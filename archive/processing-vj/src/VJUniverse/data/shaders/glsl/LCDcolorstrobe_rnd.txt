#ifdef GL_ES
precision mediump float;
#endif

#define AUDIO_RATIO 25.0

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	float lowFreq = sin(time);
	float midFreq = cos(time);
	float highFreq = tan(time);

  vec2 position = ( gl_FragCoord.xy / resolution.xy );

  float sync = tan(time * 0.75) * 10.0 + 2.0;
  if(sync < 1.0) sync = -sync;


  vec3 col = vec3(
                  cos(time * 0.5),
                  sin(time * sync * (lowFreq * AUDIO_RATIO)),
                  mod(floor(position.x * 20.0) + floor(position.y * 20.0), sync * (lowFreq * AUDIO_RATIO))
                 );

  if((lowFreq * AUDIO_RATIO) > 0.75){
      col = vec3(
                  cos(time * 0.5),
                  sin(time * sync * (lowFreq * AUDIO_RATIO)),

                  mod(
                    floor(position.x * ((midFreq * AUDIO_RATIO) * 20.0)) +
                    floor(position.y * ((highFreq * AUDIO_RATIO) * 20.0)),
                    sync * (lowFreq * AUDIO_RATIO))
                  );
    }


  if((lowFreq * AUDIO_RATIO)< 0.15){
     col = vec3(
                  sin(time * 0.625),
                  cos(time  * 0.25),
                  mod(floor(position.x * 10.0) + floor(position.y * 10.0), sync * (lowFreq * AUDIO_RATIO))
                 );
  }


  gl_FragColor = vec4(col * 1.5, 1.0);
  gl_FragColor *= mod(gl_FragCoord.y, 2.0) + sin(gl_FragCoord.y * 0.05 + (time * 5.0)) * 0.05;
  gl_FragColor *= mod(gl_FragCoord.x, 2.0);

}