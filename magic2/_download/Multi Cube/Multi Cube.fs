/*{
    "DESCRIPTION": "Wireframe cube effect shader converted to ISF format with separate float inputs.",
    "CATEGORIES": ["GLSL", "Wireframe"],
    "INPUTS": [
        {
            "NAME": "pitch",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "yaw",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "scale",
            "TYPE": "float",
            "DEFAULT": 0.8,
            "MIN": 0.1,
            "MAX": 0.8
        },
        {
            "NAME": "zoom",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "color",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "brightness",
            "TYPE": "float",
            "DEFAULT": 0.1,
            "MIN": 0.08,
            "MAX": 0.16
        },
        {
            "NAME": "perspective_toggle",
            "TYPE": "bool",
            "DEFAULT": false
        }
    ]
}*/

// Fork from https://www.shadertoy.com/view/lclXzH

#define H(a) (cos(radians(vec3(-30, 60, 150))+(a)*6.2832)*0.5+0.5)  // hue
#define A(v) mat2(cos((v*3.1416) + vec4(0, -1.5708, 1.5708, 0)))  // rotate
#define s(a, b) c = max(c, 0.01 / abs(L(u, K(a, v, h), K(b, v, h)) + 0.02) * k * 10.0 * brightness); // segment

// Line segment function
float L(vec2 p, vec3 A, vec3 B) {
    vec2 a = A.xy, 
         b = B.xy - a;
    p -= a;
    float h = clamp(dot(p, b) / dot(b, b), 0.0, 1.0);
    return length(p - b * h) + 0.01 * mix(A.z, B.z, h);
}

// Camera transformation function
vec3 K(vec3 p, mat2 v, mat2 h) {
    p.zy *= v; // pitch
    p.zx *= h; // yaw
    if (!perspective_toggle) // Toggle for perspective view
        p *= 4.0 / (p.z + 4.0); // perspective view
    return p;
}

void main() {
    vec2 R = RENDERSIZE;
    vec2 U = gl_FragCoord.xy;
    vec2 u = (U + U - R) / R.y * (0. + 3.0 - zoom * 2.);
    
    vec2 m = vec2(0.0);

    float t = TIME / 60.0;
    
    //m = sin(t*6.2832 + vec2(0, 1.5708)), // move in circles
    //m.x *= 2.; // stretch mouse x (circle to ellipse)
     m = vec2(pitch*6.2832, yaw * 2.);
    
    float l = 15.0;  // loop size
    float j = 1.0 / l; // increment size
    float r = scale;   // scale size
    float o = brightness; // brightness
    float i = 0.0;   // starting increment

    mat2 v = A(m.y); // pitch
    mat2 h; // yaw (set in loop)

    vec3 p = vec3(0, 1, -1);    // cube coordinates
    vec3 c = vec3(0.0);
    vec3 k; // cube color (set in loop)

    // Cubes

	for (float i = 0.; i < 1.0; i+=0.06) {
        k = H(i + color) + 0.2; // cube color
        h = A(m.x + i); // rotate
        p *= r; // scale
        s(p.yyz, p.yzz);
        s(p.zyz, p.zzz);
        s(p.zyy, p.zzy);
        s(p.yyy, p.yzy);
        s(p.yyy, p.zyy);
        s(p.yzy, p.zzy);
        s(p.yyz, p.zyz);
        s(p.yzz, p.zzz);
        s(p.zzz, p.zzy);
        s(p.zyz, p.zyy);
        s(p.yzz, p.yzy);
        s(p.yyz, p.yyy);
    }
    

    gl_FragColor = vec4(clamp(c * c * 3.0, 0.0, 1.0), 1.0);
}
