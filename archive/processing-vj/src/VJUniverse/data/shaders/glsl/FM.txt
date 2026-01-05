// 
// by @hektor41 
// 21/06/12
// v.1


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
	
	float formula = 1.0/(cos( x + cos(time*x*4.0) ) - y );
	float formula_effects = (formula*abs(nx)+ny);
	
	return formula_effects;
}



void main( void ) {
	
	// CONTROLS
	 float zoom = 40.0;
	 float cameraX = (zoom*5.0)/10.0;
	 float cameraY = (zoom*3.0)/10.0-0.5;
	 
	// ^ ^ ^ ^ 
	
	zoom += 0.5;
	vec2 p = ( gl_FragCoord.xy /(resolution.x * 1.0/zoom));
	float x = p.x - cameraX;
	float y = p.y - cameraY;

	float a = f(x,y);
	
	gl_FragColor = vec4(sqrt(a)/10.0,  sqrt(a)/8.0,  sqrt(a)/5.0,  1.0);

}