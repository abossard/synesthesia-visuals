/*{
  "CREDIT": "by zoidberg",
  "CATEGORIES": [
    "Color Adjustment"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "bright",
      "TYPE": "float",
      "MIN": -1,
      "MAX": 1,
      "DEFAULT": 0
    },
    {
      "NAME": "contrast",
      "TYPE": "float",
      "MIN": -4,
      "MAX": 4,
      "DEFAULT": 1
    },
    {
      "NAME": "hue",
      "TYPE": "float",
      "MIN": -1,
      "MAX": 1,
      "DEFAULT": 0
    },
    {
      "NAME": "saturation",
      "TYPE": "float",
      "MIN": 0,
      "MAX": 4,
      "DEFAULT": 1
    }
  ]
}*/

vec3 rgb2hsv(vec3 c);
vec3 hsv2rgb(vec3 c);

void main() {
    vec4 tmpColorA = IMG_THIS_PIXEL(inputImage);
    vec4 tmpColorB;
    
    // Precompute constants
    const vec3 halfVec= vec3(0.5);
    const vec3 two = vec3(2.0);
    
    // Apply brightness adjustment
    tmpColorB = tmpColorA + vec4(bright, bright, bright, 0.0);
    
    // Apply contrast adjustment (reduce operations)
    tmpColorA.rgb = ((tmpColorB.rgb - halfVec) * contrast + halfVec);
    tmpColorA.a = ((tmpColorB.a - 0.5) * abs(contrast) + 0.5);
    
    // Convert RGB to HSV
    tmpColorB.xyz = rgb2hsv(clamp(tmpColorA.rgb, 0.0, 1.0));
    tmpColorB.a = tmpColorA.a;
    
    // Apply hue adjustment
    tmpColorB.x = mod(tmpColorB.x + hue, 1.0);
    
    // Apply saturation adjustment (avoid unnecessary multiplications)
    tmpColorB.y *= saturation;
    
    // Convert HSV back to RGB
    tmpColorA.rgb = hsv2rgb(clamp(tmpColorB.xyz, 0.0, 1.0));
    tmpColorA.a = tmpColorB.a;
    
    // Output the final color
    gl_FragColor = clamp(tmpColorA, 0.0, 1.0);
}

vec3 rgb2hsv(vec3 c) {
    float minC = min(c.r, min(c.g, c.b));
    float maxC = max(c.r, max(c.g, c.b));
    float delta = maxC - minC;

    vec3 hsv;

    if (delta < 0.0001) {
        hsv.x = 0.0;
    } else if (maxC == c.r) {
        hsv.x = (c.g - c.b) / delta;
    } else if (maxC == c.g) {
        hsv.x = (c.b - c.r) / delta + 2.0;
    } else {
        hsv.x = (c.r - c.g) / delta + 4.0;
    }

    hsv.x = mod(hsv.x / 6.0, 1.0);
    hsv.y = (maxC > 0.0) ? (delta / maxC) : 0.0;
    hsv.z = maxC;

    return hsv;
}

vec3 hsv2rgb(vec3 c) {
    float h = c.x * 6.0;
    float f = h - floor(h);
    float p = c.z * (1.0 - c.y);
    float q = c.z * (1.0 - f * c.y);
    float t = c.z * (1.0 - (1.0 - f) * c.y);

    if (h < 1.0) return vec3(c.z, t, p);
    if (h < 2.0) return vec3(q, c.z, p);
    if (h < 3.0) return vec3(p, c.z, t);
    if (h < 4.0) return vec3(p, q, c.z);
    if (h < 5.0) return vec3(t, p, c.z);
    return vec3(c.z, p, q);
}
