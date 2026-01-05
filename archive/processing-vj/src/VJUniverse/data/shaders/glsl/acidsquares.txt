//cool warping

#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// HSL/RGB coversion stuff, ripped off the internet
float hue2rgb(float p, float q, float t)
{
	if(t < 0.0) t += 1.0;
	if(t > 1.0) t -= 1.0;
	if(t < 1.0/6.0) return p + (q - p) * 6.0 * t;
	if(t < 1.0/2.0) return q;
	if(t < 2.0/3.0) return p + (q - p) * (2.0/3.0 - t) * 6.0;
	return p;
}
vec3 hslToRgb(float h, float s, float l)
{
	float r, g, b;
	
	if(s == 0.0)
	{
		r = g = b = l; // achromatic
	}
	else
	{
		float q;
		if( l < 0.5 )
			q = l * (1.0 + s);
		else
			q = l + s - l * s;
		float p = 2.0 * l - q;
		r = hue2rgb(p, q, h + 1.0/3.0);
		g = hue2rgb(p, q, h);
		b = hue2rgb(p, q, h - 1.0/3.0);
	}
	return vec3(r, g, b);
}


//coord mutatie thingy
vec2 mutate(float x, float y, float b)
{
	return vec2(  sin(x/32.0)*b+x+cos(y/32.0)
		    , cos(y/32.0)*b+y+sin(x/32.0));
}

// main
void main( void ) {

	vec2 op = vec2( gl_FragCoord.x, gl_FragCoord.y  );
	
	vec2 mut = mutate(op.x, op.y, sin(time));
	
	float hue = mod(mut.x, 1.0); //0~1
	float vel = mod(mut.y, 1.0); //etc
	//float vel = 
	
	
	gl_FragColor = vec4( hslToRgb(hue, 1.0, vel), 1.0 );

}