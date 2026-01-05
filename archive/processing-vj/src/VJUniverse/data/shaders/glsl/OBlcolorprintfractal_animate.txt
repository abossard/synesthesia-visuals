#ifdef GL_ES
precision mediump float;
#endif
 
uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;
const float cutoff = 2048.0;

// Trippy julia fractal zoom by Kabuto

// Zoom to a point p at which p²+c=p -> p²-p+c = 0 -> p = 0.5+/-sqrt(0.25-c))

// Mouse in upper half: zoom to outer corner of fractal
// Mouse in lower half: zoom into vortex / solid

vec2 c = (mouse - 0.5) * 2.5;

float cx = 0.25-c.x;
float cy = -c.y;
float ca = sqrt(cx*cx+cy*cy);
float zoom = exp(cos(time*0.2)*4.0-2.0);
vec2 zoomTo = vec2(0.5-sign(cy)*sqrt((ca+cx)*0.5),-sign(cy)*sign(cy)*sqrt((ca-cx)*0.5));

float round(float a){
	if(a<0.5)
		return 0.;
	return 1.;
}

vec3 frctl(vec2 a){
	a = a * 6.;
	a = vec2(a.x - 3.0, a.y - 1.6);
	
	a = a * zoom+zoomTo;
	
	vec2 z = a;
	
	float r = 1.0, g = 1.0,b = 1.0, g2=1.0, b2=1.0;
	float i2 = 512.0;
	for(float i = 0.0; i < 128.0; i++ ){
		//vec2 z0 = vec2(z.x * z.x - z.y * z.y, z.y * z.x + z.x * z.y);
		//z = vec2(z0.x * z.x - z0.y * z.y, z0.y * z.x + z0.x * z.y);
		vec2 zold = z;
		z = vec2(z.x * z.x - z.y * z.y, z.y * z.x + z.x * z.y);
		z = vec2(z.x + c.x,z.y + c.y);
		if((z.x * z.x + z.y * z.y) > cutoff*cutoff){
			i2 = i;
			r = i / 256.0;
			g = z.x;
			b = z.y;
			g2 = zold.x;
			b2 = zold.y;
			break;
		}
	}
	r = pow(r, 0.5);
	float q1 = log(log(g*g+b*b)/(2.0*log(cutoff)))/log(2.0);
	float d1 = sqrt(-sin(time*5.0+atan(b,g))*0.5+0.5);
	float q2 = log(log(g2*g2+b2*b2)/(2.0*log(cutoff)))/log(2.0);
	float d2 = sqrt(-sin(time*5.0+atan(b2,g2))*0.5+0.5);
	float blend = -q2/(q1-q2);
	blend = ((6.0*blend-15.0)*blend+10.0)*blend*blend*blend;
	float e1 = pow(blend,2.0)*d1;
	float e2 = pow(1.0-blend,2.0)*d2;
	float d = max(e1,e2);

	return vec3(d,d*d*d*d,r);
}

void halftone( void ) {
	vec2 position = ( gl_FragCoord.xy / resolution.xy );
	position.x *= resolution.x / resolution.y;


	float a = 1.0;
	float sc = 37.3;
	vec2 p = position * sc * mat2(cos(a), -sin(a), sin(a), cos(a));
	p.x += time;
	p = mod(p, 1.0) - 0.5;
	gl_FragColor.r = length(p) * 15.0 - 10.0 + 6.0 * gl_FragColor.r;

	a = 3.0;
	sc = 43.7;
	p = position * sc * mat2(cos(a), -sin(a), sin(a), cos(a));
	p.x += time * 1.69858;
	p = mod(p, 1.0) - 0.5;
	gl_FragColor.g = length(p) * 15.0 - 10.0 + 6.0 * gl_FragColor.g;

	a = 5.0;
	sc = 46.3;
	p = position * sc * mat2(cos(a), -sin(a), sin(a), cos(a));
	p.x += time * 1.3523;
	p = mod(p, 1.0) - 0.5;
	gl_FragColor.b = length(p) * 15.0 - 10.0 + 6.0 * gl_FragColor.b;
		
	gl_FragColor.a = 1.0;
}
void main( void ) {
	vec2 position = ( gl_FragCoord.xy / resolution.xx );
	vec3 color = frctl(position);

	gl_FragColor = vec4(color, 1.0 );
	halftone();
}

