/*
{
  "IMPORTED" : [],
  "CATEGORIES" : [
    "raymarching",
    "cube",
    "4d",
    "rotating",
    "tesseract",
    "hypercube",
    "Automatically Converted"
  ],
  "DESCRIPTION" : "Automatically converted from https:\/\/www.shadertoy.com\/view\/MldXW7 by Vortex_. A 4D Cube rendered as a \"3D shadow\". Using 4D matrices to rotate the Tesseract in the 4th dimension.",
  "INPUTS" : [
    {
      "NAME": "rotX",
      "TYPE": "float",
      "DEFAULT": 0.0
    },
    {
      "NAME": "rotY",
      "TYPE": "float",
      "DEFAULT": 0.0
    },
    {
      "NAME": "rotationSpeed",
      "TYPE": "float",
      "DEFAULT": 0.1
    },
    {
      "NAME": "zoom",
      "TYPE": "float",
      "DEFAULT": 0.4
    },
    {
      "NAME": "lightIntensity",
      "TYPE": "float",
      "DEFAULT": 0.2
    },
    {
      "NAME": "foldStrength",
      "TYPE": "float",
      "DEFAULT": 0.3
    }
  ]
}
*/

// Hash functions
float hash13(vec3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 hash33(vec3 p3) {
    p3 = fract(p3 * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xxy + p3.yxx) * p3.zyx);
}

// Box SDF
float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// Rotation matrix
mat2 rot(float a) {
    return mat2(cos(a), -sin(a), sin(a), cos(a));
}

// Map function
float map(vec3 p, float TIME, float foldStrength) {
    vec3 pp = p;
    float t = TIME;
    vec3 angle = vec3(14.0, 13.0, 18.0) + p * 0.5;
    angle.z += t * 0.5;
    
    const int count = 6; // Reduced iteration count for performance
    float a = 1.0;
    float scene = 300.0;
    float shape = 300.0;
    
    // SDF loop
    for (int index = 0; index < count; ++index) {
        // Fold
        p.x = abs(p.x) - foldStrength * a;

        // Rotate
        p.xz *= rot(angle.y / a);
        p.yz *= rot(angle.x / a);
        p.yx *= rot(angle.z / a);

        // Box shape (SDF)
        shape = sdBox(p, vec3(0.3, 0.01, 0.3) * a);
        
        // Add to scene
        scene = min(scene, shape);

        // Falloff
        a /= 1.2;
    }
        
    return scene;
}

// Main image function
void main() {
    vec4 fragColor = vec4(0.0);
    
    // Camera coordinates
    vec2 uv = (gl_FragCoord.xy - RENDERSIZE.xy * 0.5) / RENDERSIZE.y;
    vec3 eye = vec3(0.0, 0.0, -zoom * 5.0);  // Adjust the zoom level here
    
    // Handling camera rotation with mouse input
    vec2 mouse = vec2(rotX, rotY);
    eye.xz *= rot(0.4 + mouse.x * 3.0);
    eye.xy *= rot(0.6 - mouse.y * 3.0);

    vec3 z = normalize(-eye);
    vec3 x = normalize(cross(z, vec3(0.0, 1.0, 0.0)));
    vec3 y = normalize(cross(x, z));
    vec3 ray = normalize(vec3(z * 1.0 + uv.x * x + uv.y * y));
    vec3 pos = eye + ray * 0.1;

    // White noise RNG
    vec3 seed = vec3(gl_FragCoord.xy, TIME);
    float rng = hash13(seed);

    // Raymarching loop
    const int steps = 10; // Reduced steps for performance
    for (int index = steps; index > 0; --index) {
        float dist = map(pos, TIME, foldStrength);
        
        if (dist < 0.01) {
            float shade = float(index) / float(steps);

            // Normal calculation (by NuSan)
            vec2 off = vec2(0.001, 0.0);
            vec3 normal = normalize(map(pos, TIME, foldStrength) - vec3(map(pos - off.xyy, TIME, foldStrength), map(pos - off.yxy, TIME, foldStrength), map(pos - off.yyx, TIME, foldStrength)));

            // Color palette (Inigo Quilez)
            float material = float(index);
            vec3 tint = vec3(0.5) + vec3(0.5) * cos(vec3(1.0, 2.0, 3.0) + material * 0.2 + length(pos) * 4.0);

            // Specular lighting
            float ld = dot(reflect(ray, normal), vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5;
            vec3 light = vec3(0.196, 0.925, 0.914) * pow(ld, 2.0) * (1.0 + lightIntensity);

            // Pixel color
            fragColor = vec4((tint + light) * shade * (1.0 + lightIntensity * 3.), 1.0);
            break;
        }

        // Dithering
        dist *= 0.7 + 0.1 * rng;

        // Raymarching step
        pos += ray * dist;
    }

    // Set the output color
    gl_FragColor = vec4(fragColor.rgb, 1.0);
}
