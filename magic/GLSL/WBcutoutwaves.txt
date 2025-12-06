#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void drawFormula( float left, float right, float res, vec3 color )
{	
	if ( ( left - right ) > 0.0 ) {
		gl_FragColor = vec4( color, 1.0 );	
	}
}

void main( void )
{
	// Settings/preparations
	vec2 min = vec2(-floor( resolution.x / 64.0 ), -floor( resolution.y / 64.0 ));
	vec2 max = vec2(floor( resolution.x / 64.0 ), floor( resolution.y / 64.0 ));
	float x = (gl_FragCoord.x/resolution.x)*(max.x-min.x)+min.y;
	float y = (gl_FragCoord.y/resolution.y)*(max.y-min.y)+min.y;
	float res = 2.0/(resolution.x+resolution.y);
	
	// White background
	gl_FragColor = vec4( 1.0, 1.0, 1.0, 1.0 );
	
	drawFormula( sin(x - time), y + cos( time ) * 0.5 - 0.5, res*5.0, vec3( 0.7, 0.9, 1.0 ) );
	drawFormula( cos(x - time * 2.0), y + sin( time ), res*5.0, vec3( 0.2, 0.7, 1.0 ) );
}