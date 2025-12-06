#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
float sinRand(float seed);
float sinTime(float speed);

void main( void ) {
	vec2 op = vec2(gl_FragCoord.x,gl_FragCoord.y);
	vec2 opPercent = vec2(op.x/resolution.x,op.y/resolution.y);
	
	float r = 1.0;
	float g = 1.0;
	float b = 1.0;
	float a = 1.0;
	
	//r = opPercent.x;
	g = opPercent.x;
	b = opPercent.y*0.3;
	
	float len = 75.0;
	for(float i = 1.0; i < 75.0; i+=1.0){
		vec3 p = vec3(sinRand(i*0.1*(time+100000.0)*0.01),sinRand(time/i),0.01 + (i/(5.0*len)*sinTime(0.4)));
		float dx = p.x - opPercent.x;
		float dy = p.y - opPercent.y;
		float dist = sqrt(dx*dx+dy*dy);
		if(dist < p.z){
			//a = dist*1.0;
			r += 1.0 - dist*(12.0-(3.0*sinTime(1.0)));
			g += 1.0 - dist*(30.0-(2.0*sinTime(3.0)));
			b = 1.0 - dist*(18.0-(7.0*sinTime(2.0)));
		}
	}
	
	
	vec3 rgb = vec3(r,g,b);
	gl_FragColor = vec4( rgb, a );

}

float sinRand(float seed){
	return (sin(seed)+1.0) /2.0;
}

float sinTime(float speed){
	return ((sin(time)*speed)+1.0) /2.0;
}