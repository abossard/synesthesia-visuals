/*{
  "CREDIT": "by You",
  "DESCRIPTION": "",
  "CATEGORIES": [],
  "INPUTS": [
    {
      "NAME": "SCALE",
      "TYPE": "float",
      "MIN": -3.5,
      "MAX": -0.8,
      "DEFAULT": -2
    },
    {
      "NAME": "dthresh",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": 0,
      "MAX": 5
    },
    {
      "NAME": "fixedRad2",
      "TYPE": "float",
      "MIN": 1.4,
      "MAX": 3,
      "DEFAULT": 2
    },
    {
      "NAME": "foldingLimit",
      "TYPE": "float",
      "MIN": 0.5,
      "MAX": 1.4,
      "DEFAULT": 1
    },
    {
      "NAME": "minRad2",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": 0,
      "MAX": 1
    },
    {
      "NAME": "dhue",
      "TYPE": "float",
      "DEFAULT": 0.82,
      "MIN": 0,
      "MAX": 1
    },
    {
      "NAME": "zoom",
      "TYPE": "float",
      "MIN": 1,
      "MAX": 8,
      "DEFAULT": 3
    },
    {
      "NAME": "x",
      "TYPE": "float",
      "MIN": -1,
      "MAX": 1,
      "DEFAULT": 1
    },
    {
      "NAME": "y",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": -1,
      "MAX": 1
    },
    {
      "NAME": "z",
      "TYPE": "float",
      "DEFAULT": 0,
      "MIN": -1,
      "MAX": 1
    }
  ]
}*/

#define MAX_ITER 35

#define MAX_ORBIT 10

float THRESH =  1. / exp(dthresh);
vec4 scale = vec4(SCALE, SCALE, SCALE, abs(SCALE)) / minRad2;


void sphereFold(inout vec3 z, inout float dz) {

	float fixedRadius2 = fixedRad2;
	float minRadius2  = minRad2;

	float r2 = dot(z,z);
	if (r2 < minRadius2) { 
		// linear inner scaling
		float temp = (fixedRadius2/minRadius2);
		z *= temp;
		dz*= temp;
	} else if (r2 < fixedRadius2) { 
		// this is the actual sphere inversion
		float temp =(fixedRadius2/r2);
		z *= temp;
		dz*= temp;
	}
}
 
void boxFold(inout vec3 z, inout float dz) {
	float foldingLimit = foldingLimit;
	z = clamp(z, -foldingLimit, foldingLimit) * 2.0 - z;
}

vec2 DE(vec3 z)
{
	vec3 offset = z;
	float dr = 1.0;

	float Scale = SCALE;
	float iter = 0.0;

	for (int n = 0; n < MAX_ORBIT; n++) {
		boxFold(z,dr);       // Reflect
		sphereFold(z,dr);    // Sphere Inversion
 		
        z=Scale*z + offset;  // Scale & Translate
        dr = dr*abs(Scale)+1.0;
        iter++;
        if (abs(dr) > 1000000.)
        	break;
	}
	float r = length(z);

	return vec2(iter, r/abs(dr));
}


//----------------------------------------------------------------------------------------
float Map(vec3 pos) 
{

	return DE(pos).y;

}

vec3 hsv(in float h, in float s, in float v) {
	return mix(vec3(1.0), clamp((abs(fract(h + vec3(3, 2, 1) / 3.0) * 6.0 - 3.0) - 1.0), 0.0 , 1.0), s) * v;
}

mat3 RotationMatrix(vec3 axis, float angle)
{
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return mat3(oc * axis.x * axis.x + c,           oc * axis.x * axis.y - axis.z * s,  oc * axis.z * axis.x + axis.y * s,
                oc * axis.x * axis.y + axis.z * s,  oc * axis.y * axis.y + c,           oc * axis.y * axis.z - axis.x * s,
                oc * axis.z * axis.x - axis.y * s,  oc * axis.y * axis.z + axis.x * s,  oc * axis.z * axis.z + c);
}

vec3 CameraPath( float t )
{
    vec3 p = vec3(-.81 + 3. * sin(2.14*t),.05+2.5 * sin(.942*t+1.3),.05 + 3.5 * cos(3.594*t) );
	return p * zoom;
} 

mat3 lookAt(vec3 eye, vec3 center, vec3 up)
{
    vec3 zaxis = normalize(center - eye);
    vec3 xaxis = normalize(cross(up, zaxis));
    vec3 yaxis = cross(zaxis, xaxis);

    mat3 matrix;
    //Column Major
    matrix[0][0] = xaxis.x;
    matrix[1][0] = yaxis.x;
    matrix[2][0] = zaxis.x;

    matrix[0][1] = xaxis.y;
    matrix[1][1] = yaxis.y;
    matrix[2][1] = zaxis.y;

    matrix[0][2] = xaxis.z;
    matrix[1][2] = yaxis.z;
    matrix[2][2] = zaxis.z;

    return matrix;
}

void main() {
	
	vec2 xy = gl_FragCoord.xy / RENDERSIZE - 0.5;
	float aspect = RENDERSIZE.x / RENDERSIZE.y;
	xy = vec2(aspect, 1.0) * xy * 2.; 


	float t = 0.;
	
	vec3 p;
	vec3 camPos = vec3(x,y,z) * zoom;
		
	vec3 forward = camPos; 

	vec3 ray = normalize(vec3(xy, 1.0));
	//mat3 rot_cam = RotationMatrix(vec3(1., 1., 0.), 0.);
	mat3 rot_cam = lookAt(normalize(camPos), vec3(0.0,0.0,0.0), vec3(0.0,1.0, 0.0));


	ray = rot_cam * ray;
	
	float iter = 0.;
	bool hit = false;
    float last_t = 0.;

	for (int i = 0; i < MAX_ITER; i++) {
		p = t * ray + camPos;
		float d = Map(p);
		float thr = exp ( t * dthresh)/ pow(10.0, 3.4) ;
		if (d < thr){

			hit = true;
			break;
		}
		last_t = t;
		t += d ;//max(thr, d);
		iter++;
	}
	
	
	float d = 1.0 - iter / float(MAX_ITER);
	
	vec3 color = hsv(d/3. + dhue,1.,d);
	
    if(dhue == 0.0)
		color = vec3(d);

	gl_FragColor = vec4(color, 1.0);
}