// by @mnstrmnch

#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

float barWidth = 0.05;
float PI = 3.14159265;

vec3 c0 = vec3( 255.0, 215.0, 0.0 ) / vec3( 255.0 );
vec3 c1 = vec3( 1.0, 0.0, 0.0 );

void main( void ) 
{
	vec2 p = ( gl_FragCoord.xy / resolution.xx ) * 2.0 - vec2( 1.0, resolution.y / resolution.x );

	vec3 color = vec3( 0.0 );

	for( int i = 23; i >= 0; i-- )
	{
		float barY = sin( time * 1.324 + float( i ) * 0.1 + p.x ) * 0.33 + sin( time * 1.194 + p.x * 0.5 ) * 0.1;

		if( p.y > barY - barWidth * 0.5 && p.y < barY + barWidth * 0.5 )
		{
			float angle = ( ( p.y - ( barY - barWidth * 0.5 ) ) / barWidth );
			color = mix( c0.zyx, c1.zyx, float( i ) / 23.0 ) * vec3( sin( angle * PI ) );
		}
	}

	for( int i = 47; i >= 0; i-- )
	{
		float barX = sin( time * 1.1347 + float( i ) * 0.1 + p.y * 0.25 ) * 0.25 + sin( time * 1. + float( i ) * 0.1 ) * 0.25;

		if( p.y < ( float( i ) / 47.0 ) * 2.0 - 1.0  && p.x > barX - barWidth * 0.5 && p.x < barX + barWidth * 0.5 )
		{
			float angle = ( ( p.x - ( barX - barWidth * 0.5 ) ) / barWidth );
			color = mix( c0, c1, float( i ) / 47.0 ) * vec3( sin( angle * PI ) );
		}
	}


	gl_FragColor = vec4( color, 1.0 );

}