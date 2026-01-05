#ifdef GL_ES
precision mediump float;
#endif
// dashxdr was here 20130301
// http://www.xdr.com/dash/blog/index.php?entry=entry121018-015739
// Want to show a sphere with squares tiling it
// work in progress, just a red sphere with some lighting
// horizontal stripes sliding down...
// spiral going down. Wow that's cool...
// got rid of unexpected lines in background... Fatter stripes
// tweak in lighting direction
// got some tilting action going... damned seam ruins it...
// ahhh. That's what I was after. Got rid of the spiral though...oh well.
// Got rid of seam at 12:00
// Added SCALE tunable, squares 2x bigger

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

void main( void ) {

	vec2 position = ( (2.0 * gl_FragCoord.xy - resolution.xy) / resolution.yy );

#define RADIUS .9
#define SCALE (5.0929581*0.5)
	position *= (1.0 / RADIUS);
	float r = length(position);
	vec3 color = vec3(1.0, 0.0, 0.0);
	float spec = 0.0;
	float diffuse = 0.0;
	if(r <= 1.0)
	{
		float z = sqrt(1.0 - r*r);
		vec3 norm = vec3(position, z);
		vec3 fix = norm;
		float tilt = 1.0;
		vec2 mat = vec2(cos(tilt), sin(tilt));
		fix.y = dot(norm.yz, mat);
		fix.z = dot(norm.yz, vec2(-mat.y, mat.x));
		float lat = asin(fix.y);
		float lon = atan(fix.x, fix.z);
		float y = SCALE * log(1.0 / cos(lat) + tan(lat));
		float x = lon * SCALE;
		float t = fract(y + time);
		if(fract(x) < .5) t = 1.0 - t;
		if(t < .5) color.r = .5;
		vec3 lightpos = normalize(vec3(-1.0, 1.0, 0.5));
		diffuse = dot(norm, lightpos);
		diffuse = max(diffuse, 0.0) + .2;
		vec3 halfdir = normalize(lightpos + vec3(0.0, 0.0, 1.0));
		spec = dot(halfdir, norm);
		spec = pow(max(spec, 0.0), 60.0);
	}

	gl_FragColor = vec4( color*diffuse + vec3(1.0, 1.0, 1.0)*spec, 1.0 );

}