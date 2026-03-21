/*{
  "CREDIT": "by You",
  "DESCRIPTION": "",
  "CATEGORIES": ["Distortion"],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "treshold",
      "TYPE": "float",
      "DEFAULT": 0.15,
      "MIN": 0.03,
      "MAX": 0.8
    },
    {
      "NAME": "rotation",
      "TYPE": "float",
      "DEFAULT": 0.5,
      "MIN": 0,
      "MAX": 1
    },
    {
      "NAME": "zoom",
      "TYPE": "float",
      "DEFAULT": 0.5,
      "MIN": 0.03,
      "MAX": 1
    },
    {
      "NAME": "iterations",
      "TYPE": "float",
      "DEFAULT": 30,
      "MIN": 15,
      "MAX": 30
    }
  ]
}*/

const int MAX_ITER = 30;

float height(float x, float y) {
    vec2 tex_space = (vec2(x * RENDERSIZE.y / RENDERSIZE.x, y) / 1.5 + 0.5);
    if (tex_space.x < 0.0 || tex_space.x > 1.0 || tex_space.y < 0.0 || tex_space.y > 1.0)
        return 0.0;
        
    return IMG_NORM_PIXEL(inputImage, tex_space).r * treshold;
}

// Box SDF
float sdBox(vec3 p, vec3 b) {
    vec3 d = abs(p) - b;
    return min(max(d.x, max(d.y, d.z)), 0.0) + length(max(d, 0.0));
}

// Rotation Matrix
mat3 RotationMatrix(vec3 axis, float angle) {
    axis = normalize(axis);
    float s = sin(angle);
    float c = cos(angle);
    float oc = 1.0 - c;
    
    return mat3(oc * axis.x * axis.x + c, oc * axis.x * axis.y - axis.z * s, oc * axis.z * axis.x + axis.y * s,
                oc * axis.x * axis.y + axis.z * s, oc * axis.y * axis.y + c, oc * axis.y * axis.z - axis.x * s,
                oc * axis.z * axis.x - axis.y * s, oc * axis.y * axis.z + axis.x * s, oc * axis.z * axis.z + c);
}

// Distance to bounding box with image-based extrusion
float DistToBoundingBox(in vec3 p) {
    p = p * RotationMatrix(vec3(0., 1., 0.), (3.14) + rotation * 3.14 * 2.);
    
    vec2 texCoord = (p.xy + 1.0) * 0.5;  // Normalize coordinates
    if (texCoord.x < 0.0 || texCoord.x > 1.0 || texCoord.y < 0.0 || texCoord.y > 1.0)
        return 99999.0;  // Out of bounds
    
    float heightValue = IMG_NORM_PIXEL(inputImage, texCoord).r * treshold;  // Luminance
    float extrusion = heightValue * 1.0;  // Control extrusion

    return sdBox(p, vec3(1.0, 1.0, 0.2 + extrusion));  // Extrude based on height
}


// Estimate the normal using finite differences
vec3 estimateNormal(vec3 p) {
    float eps = 0.001;  // Small step size for finite difference
    return normalize(vec3(
        DistToBoundingBox(p + vec3(eps, 0.0, 0.0)) - DistToBoundingBox(p - vec3(eps, 0.0, 0.0)),
        DistToBoundingBox(p + vec3(0.0, eps, 0.0)) - DistToBoundingBox(p - vec3(0.0, eps, 0.0)),
        DistToBoundingBox(p + vec3(0.0, 0.0, eps)) - DistToBoundingBox(p - vec3(0.0, 0.0, eps))
    ));
}
// Raymarching function
vec3 intersect(vec3 rayOrigin, vec3 rayDir) {
    float total_dist = 0.0;
    vec3 p = rayOrigin;
    float d = 1.0;
    float iter = 0.0;
    int maxIter = int(iterations);
    bool hit = false;
    
    for (int i = 0; i < MAX_ITER; i++) {
        if (i > maxIter) break;
        p += d * rayDir;
        d = DistToBoundingBox(p);
        if (d < 0.001) {
            hit = true;
            break;
        }
        total_dist += d;
        iter++;
    }

    if (!hit) {
        return vec3(0.0);  // Light gray for background
    }

    // Estimate the normal
    vec3 normal = estimateNormal(p);

    // Simple diffuse lighting
    vec3 lightDir = normalize(vec3(0.5, 1.0, 0.75));
    float diff = max(dot(normal, lightDir), 0.0) * 1.5;  // Diffuse lighting

    vec3 baseColor = vec3(1.0);  // White base color
    return baseColor * diff;  // Apply lighting
}

void main() {
    vec3 camera = vec3(0., 0., 2.);  // Camera position
    vec2 screenPos = -1.0 + 2.0 * isf_FragNormCoord.xy;
    screenPos.x *= RENDERSIZE.x / RENDERSIZE.y;  // Aspect ratio correction
    
    vec3 ray = normalize(vec3(screenPos, -2.5 * zoom));  // Ray direction

    // Calculate fragment color based on intersection
    gl_FragColor = vec4(intersect(camera, ray), 1.0);
}
