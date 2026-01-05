#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

//simple brick scene
//intended to be scaled with nearest neighbour filtering
//mattdesl - http://devmatt.wordpress.com/

float rand(vec2 co){
    return fract(sin(dot(co, vec2(12.9898,78.233))) * 43758.5453);
}

void main( void ) {
	float bw = 26.0;
	float bh = 12.0;
	float lw = 1.0;
	float x = gl_FragCoord.x;
	float y = gl_FragCoord.y;
	x += mouse.x * 100.0;
	y += mouse.y * 25.0;
	float bx = mod(y, bh*2.0) < bh ? x + bw/2.0 : x;
	
	float xbw = mod(bx, bw);
	float ybh = mod(y, bh);
	float TW = resolution.x/bw+1.0;
	float TH = resolution.y/bh+1.0;
	
	vec3 normals = vec3(0.0, 0.0, 1.0);
	
	//bit of faux randomization
	float xpos = floor(mod(floor(bx/bw), TW));
	float ypos = floor(mod(floor(y/bh), TH));
	vec3 color = vec3(.25 + rand(vec2(xpos, ypos))*.25);
	
	normals.x = ((xbw/bw)*2.0-1.0)*.25;
	normals.y = ((ybh/bh)*2.0-1.0)*.25;
	
	//adapted from a software solution.. lots of ifs and shit
	if ( xbw >= bw-2.0)
		normals.x += 0.25;
	else if ( xbw <= 2.0)
		normals.x -= 0.5;
	else if ( ybh >= bh-3.0)
		normals.y += 0.25;
	if ( ybh <= 2.0)
		normals.y -= 0.25;
	
	color.r += .08;
		
	//mortar
	if ( mod(y+lw, bh) < lw || mod(bx, bw) < lw ) {
		color = vec3(0.85);	
		normals = vec3(0.0, 0.0, 1.0);
	} 
	
	//floor
	if ( (y)/bh < 4.0 ) {
		color = vec3(0.5);
		normals = vec3(0.0, 1.0, 1.0);
	}
	float r = rand(vec2(x, y));
	color += (r*2.0-1.0)*.03;
	normals.x += (r*2.0-1.0)*.10;
	normals.y += (r*2.0-1.0)*.05;
	
	vec3 lightPos =  vec3(mouse.xy - (gl_FragCoord.xy/resolution.xy), 0.2); //vec3(mouse - vec2(0.5, 0.5), 0.5);
	vec3 L = normalize(lightPos);
	vec3 N = normalize(normals);
	
	float dist = sqrt(dot(lightPos, lightPos));
	vec3 att = vec3(2.3,-16.,37.5);
	
	float lambert = clamp(dot(N, L), 0.0, 1.0);
	float shadow = 1.0/(att.x + (att.y*dist) + (att.z*dist*dist));
	vec3 finalColor = vec3(0.0);
	
	finalColor += color * (lambert * shadow);

	finalColor += rand(vec2(x, y)+time)*0.1;
	
	gl_FragColor = vec4(finalColor, 1.0);
}