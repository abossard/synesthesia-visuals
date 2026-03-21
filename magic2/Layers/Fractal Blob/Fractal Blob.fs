/*
{
  "IMPORTED" : [

  ],
  "CATEGORIES" : [
    "Fractal"
  ],
  "DESCRIPTION" : "Automatically converted from https:\/\/www.shadertoy.com\/view\/wdc3zX by leon.  An example on how to render stereoscopic anaglyph image.\nIt will be the theme of https:\/\/2019.cookie.paris\/\nAnd the content of the 3rd issue of https:\/\/fanzine.cookie.paris\/",
  "INPUTS" : [
    {
      "NAME" : "iMouse",
      "TYPE" : "point2D"
    },
    {
        "NAME" :    "speed",
        "TYPE" :    "float",
        "DEFAULT" : 0.4
    },
    {
        "NAME" :    "radius",
        "TYPE" :    "float",
        "DEFAULT" : 0.3
    },
    {
        "NAME" :    "falloff",
        "TYPE" :    "float",
        "DEFAULT" : 0.0
    },
    {
        "NAME" :    "divergence",
        "TYPE" :    "float",
        "DEFAULT" : 0.1
    }
  ]
}
*/


// Anaglyph Quick Sketch
// An example on how to render stereoscopic anaglyph image
// It will be the theme of https://2019.cookie.paris/
// And the content of the 3rd issue of https://fanzine.cookie.paris/
// Leon Denise 2019.09.20
// Licensed under hippie love conspiracy

// Using code from
// Inigo Quilez
// Morgan McGuire

const int count = 5;
const float range = 1.;
const float blend = 1.5;
const float balance = 1.5;
const float grain = .01;
const float fieldOfView = 1.5;

float random(vec2 p) { return fract(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x)))); }
mat2 rot(float a) { float c=cos(a),s=sin(a); return mat2(c,-s,s,c); }
float smoothmin (float a, float b, float r) { float h = clamp(.5+.5*(b-a)/r, 0., 1.); return mix(b, a, h)-r*h*(1.-h); }
vec3 look (vec3 eye, vec3 target, vec2 anchor, float fov) {
    vec3 forward = normalize(target-eye);
    vec3 right = normalize(cross(forward, vec3(0,1,0)));
    vec3 up = normalize(cross(right, forward));
    return normalize(forward * fov + right * anchor.x + up * anchor.y);
}

vec3 camera (vec3 eye) {
    vec2 mouse = iMouse.xy/RENDERSIZE.xy*2.-1.;
    if (iMouse.x > 0.5) {
        eye.yz *= rot(mouse.y*3.1415);
        eye.xz *= rot(mouse.x*3.1415);
    } else {
        eye.yz *= rot(-3.1415/4.);
        eye.xz *= rot(-3.1415/2.);
    }
    return eye;
}

float geometry (vec3 pos) {
    pos = camera(pos);
    float a = 1.0;
    float scene = 1.;
    float t = speed * (3.141);
    float wave = 1.0+0.2*sin(t*8.-length(pos)*2.);
    //t = floor(t)+pow(fract(t),.5);
    for (int i = count; i > 0; --i) {
        pos.xy *= rot(cos(t));
        pos.zy *= rot(sin(t));
        pos.zx *= rot(sin(t));
        pos = abs(pos)-range*a*wave;
        scene = smoothmin(scene, length(pos)-radius*a, blend*a);
        a /= (1.9 + falloff * 2.);
    }
    return scene;
}

float raymarch ( vec3 eye, vec3 ray ) {
    float dither = random(ray.xy + TIME);
    float total = dither;
    const int count = 30;
    for (int index = count; index > 0; --index) {
        float dist = geometry(eye+ray*total);
        dist *= 0.9+.1*dither;
        total += dist;
        if (dist < 0.001 * total)
            return float(index)/float(count);
    }
    return 0.;
}

void main() {



    vec2 uv = 2.*(gl_FragCoord.xy-0.5*RENDERSIZE.xy)/RENDERSIZE.y;
    vec3 eyeLeft = vec3(-divergence,0,5.);
    vec3 eyeRight = vec3(divergence,0,5.);
    vec3 rayLeft = look(eyeLeft, vec3(0), uv, fieldOfView);
    float red = raymarch(eyeLeft, rayLeft);
    gl_FragColor = vec4(red,red,red,1);
}
