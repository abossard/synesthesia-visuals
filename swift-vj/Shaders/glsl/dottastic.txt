#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
//
void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) + mouse / 4.0;

	float color = 0.0;
	color += sin( position.x * cos( time / 15.0 ) * 80.0 ) + cos( position.y * cos( time / 15.0 ) * 10.0 );
	color += sin( position.y * sin( time / 10.0 ) * 40.0 ) + cos( position.x * sin( time / 25.0 ) * 40.0 );
	color += sin( position.x * sin( time / 5.0 ) * 10.0 ) + sin( position.y * sin( time / 35.0 ) * 80.0 );
	color *= sin( time / 10.0 ) * 0.5;
	
	vec4 pixel = vec4( vec3( color + 0.1, color * 0.5, sin( color + time / 3.0 ) * 0.75 ), 1.0 );
	//pixel = vec4(0.9,1.0,1.0,1.0);
	pixel = clamp(pixel, 0.0, 1.0);
	
	float pixelWhite = min(min(pixel.r, pixel.g), pixel.b);
	float pixelColour = max(max(pixel.r, pixel.g), pixel.b) - pixelWhite;

	vec4 pixelHue;
	if (pixelColour > 0.0)
		pixelHue = ( pixel - pixelWhite ) / pixelColour;
	else
		pixelHue = vec4(0.0,0.0,0.0,1.0);
	pixelHue.a = 1.0;
	vec2 pixelPos = gl_FragCoord.xy / resolution.xy;
	float dist = length( fract( pixelPos * 25.0 ) - 0.5 ) * 2.0;
	dist = dist * dist;

	if (dist < pixelColour ) gl_FragColor = pixelHue;
	else if (dist < (pixelColour + pixelWhite)) gl_FragColor = vec4(1.0,1.0,1.0,1.0);
	else gl_FragColor = vec4(0.0,0.0,0.0,1.0);//dist * (1.0 - pixel);
}