#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

//mromgwtf

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}
void main( void ) {

	vec2 position = ( gl_FragCoord.xy / resolution.xy ) * 2.0 - 1.0;
	position.x *= resolution.x / resolution.y;
	position *= 3.0;

	float color = 0.7;
	for(float i = 0.0; i < 50.0; i++)
	{
		vec2 randCoord = vec2(rand(vec2(i, i)), rand(vec2(i, i+10.0)));
		randCoord.x += sin(time/2.0 + randCoord.y * randCoord.y);
		randCoord.y += sin(time + randCoord.x * 2.0);
		
		randCoord = randCoord * 2.0 - 1.0;
		color += 1.0 / distance(position, randCoord) * 0.6;
	}
	color *= 0.02;
	color = pow(color, 0.9);
	gl_FragColor = vec4( vec3(color + rand(position) * (1.0 / 128.0)), 0.3);
	gl_FragColor = pow(gl_FragColor, vec4(1.5, time*time,0.86, 0.3));

}