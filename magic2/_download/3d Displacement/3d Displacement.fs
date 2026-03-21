/*{
    "DESCRIPTION": "Texture 3d displacement",
    "CREDIT": "Rhythmic Visions",
    "ISFVSN": "2",
    "INPUTS": [
        {
            "NAME": "inputImage",
            "TYPE": "image"
        },
        {
            "NAME": "rotationY",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "rotationZ",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1
        },
        {
            "NAME": "zoom",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1
        },
        {
            "NAME": "depth",
            "TYPE": "float",
            "DEFAULT": 0.15,
            "MIN": 0.03,
            "MAX": 1
        },
        {
            "NAME": "treshold",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1
        }
    ]
}*/
#define TAU 6.283185
#define PI 3.141592
#define MAX_STEPS 100
#define MAX_DIST 4.
#define SURF_DIST .001
#define AA 2

// Displacement function using the texture to determine height
vec4 GetImagePlane(vec3 p)
{
    float ratio = (RENDERSIZE.y / RENDERSIZE.x);
    vec2 uv = p.xy / 2.;
    uv.y /= ratio;
    uv.x *= -1.;
    uv += 0.5;
    vec3 tex = IMG_NORM_PIXEL(inputImage, uv).rgb;
    float luma = dot(tex, vec3(0.299, 0.587, 0.114)) * 2.;
    return vec4(tex * luma / 2., (1.0 - luma * treshold * 2.) * depth);
}


float smin( float a, float b, float k ) {
    float h = clamp( 0.5+0.5*(b-a)/k, 0., 1. );
    return mix( b, a, h ) - k*h*(1.0-h);
}

float sdBox(vec3 p, vec3 s) {
    p = abs(p)-s;
	return length(max(p, 0.))+min(max(p.x, max(p.y, p.z)), 0.);
}

float GetBox(vec3 p) {
    float ratio = (RENDERSIZE.y / RENDERSIZE.x);
    float box = sdBox(p, vec3(1.0, ratio, depth));
    return box;
}

float GetDist(vec3 p) {
    float box = GetBox(p);
    float image = GetImagePlane(p).a * 0.043;
    return smin(image, box, -0.03);
}


mat2 Rot(float a) {
    float s=sin(a), c=cos(a);
    return mat2(c, -s, s, c);
}

vec3 GetRayDir(vec2 uv, vec3 p, vec3 l, float z) {
    vec3 
        f = normalize(l-p),
        r = normalize(cross(vec3(0,1,0), f)),
        u = cross(f,r),
        c = f*z,
        i = c + uv.x*r + uv.y*u;
    return normalize(i);
}


float RayMarch(vec3 ro, vec3 rd) {
	float dO=0.;
    
    for(int i=0; i<MAX_STEPS; i++) {
    	vec3 p = ro + rd*dO;
        float dS = GetDist(p);
        dO += dS;
        if(dO>MAX_DIST || abs(dS)<SURF_DIST) break;
    }
    
    return dO;
}


vec3 GetNormal(vec3 p) {
    vec2 e = vec2(.001, 0);
    vec3 n = GetDist(p) - 
        vec3(GetDist(p-e.xyy), GetDist(p-e.yxy),GetDist(p-e.yyx));

    return normalize(n);
}


// Main rendering function
void main() {
    // Camera setup with rotation parameters
    float timePos = TIME * 0.5;
    
    vec3 col = vec3(0.0);
    vec3 ro = vec3(0, 0, -1)*2.;
    ro.yz *= Rot((-0.5 + rotationY) * PI );
    ro.xz *= Rot((1. - rotationZ) * TAU);

    for(int x=0; x<AA; x++) {
        for(int y=0; y<AA; y++) {
            vec2 offs = vec2(x, y)/float(AA) -.5;
            vec2 uv = (gl_FragCoord.xy+offs-.5*RENDERSIZE.xy)/RENDERSIZE.y;
            vec3 rd = GetRayDir(uv, ro, vec3(0, 0, 0), 0.5 + zoom * 1.5);
        
            float d = RayMarch(ro, rd);
        
            if(d<MAX_DIST) {
                vec3 p = ro + rd * d;
                vec3 n = GetNormal(p);
                vec3 r = reflect(rd, n);
        
                float dif = dot(n, normalize(vec3(1,2,3)))*.5+.5;
                col += mix(col, GetImagePlane(p).rgb, 0.5) * dif;
            }
        }
    }
    col /= float(AA*AA);

    col = pow(col, vec3(.4545));	// gamma correction

    gl_FragColor = vec4(col, 1.0);
}
