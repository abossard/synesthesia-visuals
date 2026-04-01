/*
{
  "CATEGORIES": [
    "Fractal"
  ],
  "INPUTS" : [
    {
      "NAME" : "Ball",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 1,
      "MIN" : 0
    },
    {
      "NAME" : "RotationIntensityX",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0,
      "MIN" : 0
    },
    {
      "NAME" : "RotationIntensityY",
      "TYPE" : "float",
      "MAX" : 1,
      "DEFAULT" : 0,
      "MIN" : 0
    },
    {
      "MAX" : 1,
      "NAME" : "RotationSpeed1",
      "TYPE" : "float",
      "DEFAULT" : 1,
      "MIN" : 0
    },
    {
      "MAX" : 1,
      "NAME" : "RotationSpeed2",
      "TYPE" : "float",
      "DEFAULT" : 1
    },
    {
      "NAME" : "SizeReductionRate",
      "TYPE" : "float"
    },
    {
      "MAX" : 10,
      "NAME" : "RotationOffset1",
      "TYPE" : "float",
      "MIN" : 0
    },
    {
      "MAX" : 10,
      "NAME" : "RotationOffset2",
      "TYPE" : "float",
      "DEFAULT" : 0.3,
      "MIN" : 0
    },
    {
      "NAME" : "PlaneFoldFactor1",
      "TYPE" : "float",
      "DEFAULT" : 0.3
    },
    {
      "NAME" : "PlaneFoldFactor2",
      "TYPE" : "float",
      "DEFAULT" : 0.1
    },
    {
      "NAME" : "CameraZOffset",
      "TYPE" : "float",
      "MAX" : 15,
      "DEFAULT" : 10,
      "MIN" : 0
    },
    {
      "NAME" : "CameraXOffset",
      "TYPE" : "float",
      "MAX" : 20,
      "DEFAULT" : 10,
      "MIN" : 0
    },
    {
      "NAME" : "CameraYOffset",
      "TYPE" : "float",
      "MAX" : 10,
      "DEFAULT" : 5,
      "MIN" : 0
    }
  ],
  "ISFVSN" : "2"
}
*/

// Code by Flopine
// Thanks to wsmind, leon, XT95, lsdlive, lamogui, Coyhot, Alkama and YX for teaching me
// Thanks LJ for giving me the love of shadercoding :3

// Thanks to the Cookie Collective, which build a cozy and safe environment for me 
// and other to sprout :)  https://twitter.com/CookieDemoparty

// Mods by @rhythmic.visions

// Code by Flopine
// Thanks to wsmind, leon, XT95, lsdlive, lamogui, Coyhot, Alkama and YX for teaching me
// Thanks LJ for giving me the love of shadercoding :3

// Thanks to the Cookie Collective, which build a cozy and safe environment for me 
// and other to sprout :)  https://twitter.com/CookieDemoparty

// Mods by @rhythmic.visions

// Hash function optimized for performance
float hash21(vec2 x) {
    return fract(sin(dot(x, vec2(54.4, 62.1))) * 457.5);
}

// Rotation matrix computation
mat2 rot(float a) {
    float ca = cos(a);
    float sa = sin(a);
    return mat2(ca, sa * RotationIntensityX, -sa * RotationIntensityY, ca);
}

// 2D mirror operations
void mo(inout vec2 p, vec2 d) {
    p = abs(p) - d;
    if (p.y > p.x) p = p.yx;
}

// Plane distance function
float plane(vec3 p, vec3 n) {
    return dot(p, normalize(n));
}

// Cut shape distance
float cut_ps(vec3 p, float s) {
    p *= s;
    mo(p.xy, vec2(1.0));
    mo(p.yz, vec2(0.6 * PlaneFoldFactor1 + PlaneFoldFactor2));
    mo(p.xz, vec2(0.1 * PlaneFoldFactor1 + PlaneFoldFactor2));
    return plane(p, vec3(1.0, 1.0, 4.0)) / s;
}

// Primitive shape distance
float prim1(vec3 p, float s) {
    float pos = cos(TIME * RotationSpeed1 + RotationOffset1) * 0.4;
    p.xz *= rot(pos);
    return cut_ps(p, s);
}

// Fractal distance function
float fractal(vec3 p) {
    float size = 1.0;
    float d = prim1(p, size - SizeReductionRate);
    for (int i = 1; i < 5; i++) {
        float ratio = float(i) / 2.5;
        float pos = cos(TIME * ratio * RotationSpeed2 + RotationOffset2) * 0.4;
        p.yz *= rot(pos);
        size -= 0.2;
        d = min(d, prim1(p, size + SizeReductionRate));
    }
    return d;
}

// Signed Distance Function (SDF) with accumulation and optimizations
float SDF(vec3 p) {
    float noise = hash21(p.xy * 0.1 + TIME) * 0.01;
    float sphe = length(p) - (0.8 + noise) * Ball * 2.0;
    float sdfValue = max(-length(p + vec3(0.0, 0.0, 4.5)) + 0.8, min(sphe, fractal(p)));

    // Accumulate contribution to g1
    float dist = 0.1 / (0.1 + sphe * sphe);
    return sdfValue;
}

void main() {
    vec2 uv = (gl_FragCoord.xy - RENDERSIZE.xy * 0.5) / RENDERSIZE.y;
    float dither = hash21(uv);

    vec3 ro = vec3(10.0 - CameraXOffset, 5.0 - CameraYOffset, -4.5 - CameraZOffset);
    vec3 rd = normalize(vec3(uv, 0.8));
    vec3 p = ro;
    vec3 col = vec3(0.0);

    float shad = 0.0;
    bool hit = false;

    // Reduced loop iterations and use early exit for optimization
    for (float i = 0.0; i < 32.0; i++) {  // Reduced iteration count from 64 to 16
        float d = SDF(p);
        if (d < 0.001) {
            hit = true;
            shad = i / 32.0;  // Update shading calculation based on new loop count
            break;
        }
        d *= 0.8 + dither * 0.1;
        p += d * rd;
    }

    if (hit) {
        col = vec3(1.0 - shad) + vec3(0.15, 0.0, 0.1) * 0.5;  // Replaced g1 with fixed color contribution
    }

    gl_FragColor = vec4(col, 1.0);
}