#ifdef GL_ES
precision mediump float;
#endif


uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {
	vec2  pos = gl_FragCoord.xy;
	vec2  cPos;
	float index = 0.0;
	
	float accum = 0.0;
	float tmp;
	float radius = min(resolution.x, resolution.y);
		
	vec2 center = resolution * 0.5;
	
	for( int i=0; i<5; i++) {
	  index += 0.51;
		
	  //vec2 sferePos = vec2(600.0+sin(time*index)*400.0-cos(time/index), 600.0+cos(time*(5.0-index))*400.0);
		
	  vec2 sferePos = vec2(center.x + sin(time*index) * cos(time*(3.0-index*1.23)) * radius * 0.3, 
			       center.y + cos(time*(5.0-index)) * radius * 0.3);
		
	  tmp = radius * 11.0/length(sferePos - gl_FragCoord.xy);
	  tmp *= tmp;
	  accum += tmp * 0.000075;
	}

		
	gl_FragColor = vec4(
		accum<0.35?0.0:1.0-accum*2.0+0.2,
		accum<0.47?0.0:1.0-accum+0.05,
		accum<0.70?0.0:1.0-accum*0.75+0.2, 1.0 );
}