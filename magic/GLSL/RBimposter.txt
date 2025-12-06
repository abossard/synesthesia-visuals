#ifdef GL_ES
precision highp float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

const float LINES = 2.0;

void main( void ) 
{  
	vec2 uPos = ( gl_FragCoord.xy / resolution.y ); 	// normalize wrt y axis
	uPos -= vec2((resolution.x/resolution.y)/0.5, 0.5);	// shift origin to center
	
	//uPos.x -= mouse.x;
	//uPos.y -= mouse.y;
	
	float vertColor = 0.0;
	for(float i = 0.0; i < LINES; i++)
	{
		float t = time * 0.5;
		
		uPos.y += sin( t + uPos.x * 6.0) * 0.45;
		uPos.x += sin(-t + uPos.y * 3.0) * 0.25;
		
		float value = sin(uPos.y * 2.5) + sin(uPos.x * 10.0 );
		float stripColor = 1.0/sqrt(abs(value));
		
		vertColor += stripColor / 14.0;
	}
	
	// Limit to a circle
	vec2 midpoint = resolution * 0.5;
	
	midpoint.y *= cos(time * 1.0) * 0.3;
	midpoint.x *= sin(time * 1.0) * 0.3;
	
	midpoint.y += resolution.y *0.5;
	midpoint.x += resolution.x *0.5;
	
	midpoint = mouse + resolution * 0.5;
	
	// Circle dimensions
	float radius = min(resolution.x, resolution.y) * 0.25;
	float dist = length(gl_FragCoord.xy - midpoint);
	
	// Is this texel inside the circle?
	float inside = smoothstep(radius+1.0, radius-1.0, dist);
	float outside = smoothstep(radius-1.0, radius+1.0, dist);
	
	vec3 color = vec3(vertColor * outside, 
			  vertColor  * inside, 
			  vertColor * inside * 2.0);	
	
	
	color *= color;
	gl_FragColor = vec4(color, 1.0);
}