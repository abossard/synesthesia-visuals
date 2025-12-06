#ifdef GL_ES
precision mediump float;
#endif

/* weird blue worms by @neave */

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void )
{
	float scale = 16.0;
	float amplitude = 2.0;
	float wavelength = 0.8;
	float thickness = 0.02;
	float speed = 0.5;
	float glow = 4.0;
	
	vec2 p = ( gl_FragCoord.xy / resolution.xy * scale );
	
	p.y -= 0.5 * scale;
	
	float c = 0.0;
	for ( float i = 0.0; i < 16.0; i++ )
	{
		float t = time * i * speed;
		p.y += sin( p.x * wavelength + t ) * amplitude;
		c += abs( thickness / p.y );
	}
	
	gl_FragColor = vec4( c, c, c * glow, 1.0 );
}