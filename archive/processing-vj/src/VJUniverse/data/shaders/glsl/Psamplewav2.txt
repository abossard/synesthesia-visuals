#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 resolution;

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(121.9898,78.233))) * 758.5453);
}

void main( void )
{
	vec2 pos = gl_FragCoord.xy / resolution.xy;
	vec2 uPos = pos;
	uPos.y -= 0.1;
	
	vec3 color = vec3(.0);
	float vertColor = 0.0;
	const float k = 9.0;
	for( float i = k; i > 1.; --i )
	{
		float t = time * (100.0);
	
		uPos.y += sin( uPos.x*exp(i) - t) * 0.015;
		float fTemp = abs(.50/(10.0*k) / uPos.y);
		vertColor += fTemp;
		color += vec3( fTemp*(i*0.9), fTemp*i/k, pow(fTemp,.93)*9.9 );
	}
	
	vec4 color_final = vec4(color, 9.0);
	gl_FragColor = color_final;
	float ft = fract(time);
	gl_FragColor.rgb += vec3( rand( pos +  7.+ ft ), 
				  rand( pos +  9.+ ft ),
        			  rand( pos + 11.+ ft ) ) / 320.0;
}
