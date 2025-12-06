// 
// by @hektor41 
// 21/06/12
// v.1

//MOD + :)


#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;


float f(float x, float y,float z) {
	x+=x+sin(x*3.0);
	y+=y+sin(y*3.0);
	
	float formula = 1.0/( sin( x + time*0.1*z ) * 2. - y ) / cos(time + (y*x)) * 15.;
	float formula_effects = formula;///sqrt(ny);
	
	return formula_effects;
}



void main( void ) {
	
	// CONTROLS
	 float zoom = 5.0;
	 float cameraX = 2.5;
	 float cameraY = (zoom*3.0)/10.0-0.5;
	 
	// ^ ^ ^ ^ 
	
	zoom += 0.5;
	vec2 p = ( gl_FragCoord.xy /(resolution.x * 1.0/zoom));
	float x = p.x - cameraX;
	float y = p.y - cameraY;

	float a = f(x+sin(-time*0.31),y+sin(time*0.55),20.0);
	float b = f(x+sin(-time*0.63),y+sin(time*0.94),10.0);
	float c = f(x+sin(-(time+a*0.1)*0.39),y+sin(time*0.22),10.0);
	
	gl_FragColor = (
			vec4(sqrt(abs(a))/10.0,  0.0,  abs(sqrt(abs(a)))/5.0,  1.0)+
			vec4(0.0,  0.0,  abs(sqrt(abs(b)))/10.0,  1.0)+
			vec4(0.0,  abs(sqrt(abs(c)))/5.0,  abs(sqrt(abs(c)))/10.0,  1.0)
		)/2.0;

}