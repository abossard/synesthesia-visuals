#ifdef GL_ES
precision mediump float;
#endif

uniform float time;
uniform vec2 mouse;
uniform vec2 resolution;

// color by @hintz

struct Camera											// A camera struct that holds all relevant camera parameters
{
	vec3 position;
	vec3 lookAt;
	vec3 rayDir;
	vec3 forward, up, left;
};

void rotate(inout vec2 v, float angle)
{
	v = vec2(cos(angle)*v.x+sin(angle)*v.y,-sin(angle)*v.x+cos(angle)*v.y);
}

float PI = atan(1.0)*4.0;

float scene(vec3 p) 
{
	float  a =0.;
	float b = 0.;
	float polyfoldOrder = 5.0;
	float R1 = 5.;
	float R2 = 0.8;
	float R3 = 2.0;
	float mobius = (a+b/polyfoldOrder) + atan(p.y,p.x);
	p.x = length(p.xy)-R1;
	rotate(p.xz,mobius);	
	float m = polyfoldOrder/(2.*PI);
	float angle = floor(.5+m*(PI/2.-atan(p.x,p.z)))/m;
	rotate(p.xz,angle);
	p.x =p.x - R3;
	
	return length(p.xz)-R2;
}

void main(void)
{
	vec2 vPos = 2.0 * ( gl_FragCoord.xy / resolution.xy ) - 1.0;
	float ratio = resolution.x / resolution.y;
	vec3 color =  vec3(vPos.x, vPos.y, 0.5);
	float t = time;
	//Camera setup
	Camera cam;
  	cam.lookAt = vec3(0,0,0);								// The point the camera is looking at
	cam.position = vec3(sin(t)*7.0, sin(t) * 7.0, cos(t)*7.0);						// The position of the camera
	cam.up = vec3(0,1,0);									// The up vector, change to make the camera roll, in world space
  	cam.forward = normalize(cam.lookAt-cam.position);					// The camera forward vector, pointing directly at the lookat point
  	cam.left = cross(cam.forward, cam.up);							// The left vector, which is perpendicular to both forward and up
 	cam.up = cross(cam.left, cam.forward);	
	
						// The recalculated up vector, in camera space
 
	vec3 screenOrigin = (cam.position+cam.forward); 					// Position in 3d space of the center of the screen
	vec3 screenHit = screenOrigin + vPos.x*cam.left*ratio + vPos.y*cam.up; 	// Position in 3d space where the camera ray intersects the screen
  
	cam.rayDir = normalize(screenHit-cam.position);	
	// Ray marching
	const float MIN_DISTANCE = 0.0001;								// Distance to scene that we will count as a hit
	const float MAX_DEPTH=400.0;								// Distance from camera that we will count as a miss
	const int MAX_STEPS = 50;								// Maxmimum amount of ray marching steps before counting the ray as a miss
	
  	float dScene = 1.0;								// Initial distance to scene, should be initialized as 1
	float dCam = 0.0;								// The ray starts at the camera, so 0
	
  	vec3 rpos;
	for (int i = 0; i < MAX_STEPS; i++)
	{
		if(abs(dScene) < MIN_DISTANCE || dCam > MAX_DEPTH) break;
		dCam += dScene * 0.8;
		rpos = cam.position + cam.rayDir*dCam;
		dScene = scene(rpos);
	}
	
	if (dCam < MAX_DEPTH)
	{
		vec3 e = vec3(0.001, 0.0, .0);
		vec3 n = normalize(vec3(dScene - scene(rpos + e.xyy),
					dScene - scene(rpos + e.yxy),
					dScene - scene(rpos + e.yyx))); 
		vec3 diffuse = n+0.5;
		float l = max(dot(n, cam.rayDir),0.);
		vec3 spec = pow(l,95.0)*2.5 * vec3(1.0);
		color = diffuse * l + spec;
	}
	
	gl_FragColor = vec4(color, 1.0);
}