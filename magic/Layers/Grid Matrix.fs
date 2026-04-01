/*{
    "DESCRIPTION": "Optimized ISF shader with parameters for speed, color modulation, and tunnel deformation.",
    "CREDIT": "Shadertoy",
    "ISFVSN": "2",
    "INPUTS": [
        {
            "NAME": "speed",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.1,
            "MAX": 5.5,
            "LABEL": "Speed"
        },
        {
            "NAME": "colorMod",
            "TYPE": "color",
            "LABEL": "Color Modulation"
        }
    ]
}*/

// Forked and based from 
// https://www.shadertoy.com/view/NlsXDH


float det = .001, t, boxhit;
vec3 adv, boxp;

float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

mat2 rot(float a) {
    float s = sin(a), c = cos(a);
    return mat2(c, s, -s, c);
}

vec3 path(float t) {
    vec2 pathOffset = vec2(sin(t * 0.1), cos(t * 0.05)) * 10.0;
    float xOffset = smoothstep(0.0, 0.5, abs(0.5 - fract(t * 0.02))) * 10.0;
    return vec3(pathOffset.x + xOffset, pathOffset.y, t);
}

float fractal(vec2 p) {
    p = abs(5.0 - mod(p * 0.2, 10.0)) - 5.0;
    float ot = 1000.0;
    for (int i = 0; i < 7; i++) {
        p = abs(p) / clamp(p.x * p.y, 0.25, 2.0) - 1.0;
        if (i > 0) {
            float fractValue = fract(abs(p.y) * 0.05 + t * 0.05 + float(i) * 0.3);
            ot = min(ot, abs(p.x) + 0.7 * fractValue);
        }
    }
    return exp(-10.0 * ot);
}

float box(vec3 p, vec3 l) {
    vec3 c = abs(p) - l;
    return length(max(vec3(0.0), c)) + min(0.0, max(c.x, max(c.y, c.z)));
}

float de(vec3 p) {
    boxhit = 0.0;
    vec3 p2 = p - adv;
    p2.xz *= rot(sin(t * 0.5)); // Adding tunnel deformation
    p.xy -= path(p.z).xy;
    p.y = -abs(p.y) - 3.0 ;
    p.z = mod(p.z, 20.0) - 10.0;

    for (int i = 0; i < 5; i++) {
        p = abs(p) - 1.0;
        p.xz *= rot(radians(-45.0));
        p.yz *= rot(radians(90.0));
    }

    float f = -box(p, vec3(5.0, 5.0, 10.0));
    return f * 0.8;
}

vec3 march(vec3 from, vec3 dir) {
    vec3 g = vec3(0.0);
    float td = 0.0;

    for (int i = 0; i < 20; i++) {
        vec3 p = from + td * dir;
        float d = de(p); // * (1.0 - hash(gl_FragCoord.xy + t) * 0.3);
        if (d < det && boxhit < 0.5) break;
        td += max(det, abs(d));

        // Aggregate fractal calculations
        float fractalSum = fractal(p.xy) + fractal(p.xz) + fractal(p.yz);
        float boxFractalSum = fractal(boxp.xy) + fractal(boxp.xz) + fractal(boxp.yz);

        vec3 colf = vec3(fractalSum) * colorMod.rgb;

        g += colf / (3.0 + d * d * 2.0) * exp(-0.0002 * td * td) * step(5.0, td) * 0.5 * (1.0 - boxhit);
    }

    return g;
}

mat3 lookat(vec3 dir, vec3 up) {
    dir = normalize(dir);
    vec3 rt = normalize(cross(dir, normalize(up)));
    return mat3(rt, cross(rt, dir), dir);
}

void main() {
    vec2 uv = (gl_FragCoord.xy - RENDERSIZE.xy * 0.5) / RENDERSIZE.y;
    t = TIME * 7.0 * speed; // Adjusted time with speed parameter
    vec3 from = path(t);
    adv = path(t + 6.0 + sin(t * 0.1) * 3.0);
    vec3 dir = normalize(vec3(uv, 0.7));
    dir = lookat(adv - from, vec3(0.0, 1.0, 0.0)) * dir;
    vec3 col = march(from, dir);
    gl_FragColor = vec4(col, 1.0);
}
