// 
// by @hektor41 
// 21/06/12
// v.2
// 


#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;


float f(float x, float y) {
	//x = (mouse.x*10.0)*x; //Interactive
	
	float nx = x + cos(time*x);
	float ny = y + sin(time*y);
	
	float formula = 4.0/( cos( x + time ) - y );
	
	float formula_effects = 1.0/(( cos( x*0.03 + time )- y*0.03 ))-formula;
	float formula_effects_plus = formula_effects/sqrt(ny);
	
	return formula_effects_plus;
}



void main( void ) {
	
	// CONTROLS
	 float zoom =50.0;
	 float cameraX = (zoom*5.0)/10.0;
	 float cameraY = (zoom*3.0)/10.0-0.5;
	 
	// ^ ^ ^ ^ 
	
	zoom += 0.5;
	vec2 p = ( gl_FragCoord.xy /(resolution.x * 1.0/zoom));
	float x = p.x - cameraX;
	float y = p.y - cameraY;

	float a = f(x,y);
	float b = f(x*x,x*y);
	
	gl_FragColor = vec4(sqrt(b)/10.0,  sqrt(a)/10.0,  sqrt(a)/10.0,  1.0);

}