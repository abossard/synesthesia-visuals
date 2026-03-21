/*
{
  "CATEGORIES" : [
    "Feedback"
  ],
  "DESCRIPTION" : "Optimized shader with rotation and hue shift.",
  "INPUTS" : [
    {
      "NAME" : "inputImage",
      "TYPE" : "image"
    },
    {
      "NAME" : "zoom",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "rotate",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "width",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "height",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "x",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "y",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "biasAmount",
      "TYPE" : "float",
      "DEFAULT": 0.2
    }
  ],
  "ISFVSN" : "2"
}
*/

vec2 rotated(float angle, vec2 uv) {
    float aspect = RENDERSIZE.x / RENDERSIZE.y; 
    float angleRad = angle * 6.28318; // Convert amount (0-1) to radians
    float s = sin(angleRad);
    float c = cos(angleRad);

    // Normalize UV and apply aspect ratio correction
    uv = (uv - 0.5) * vec2(aspect, 1.0);

    // Apply 2D rotation
    uv = vec2(
        uv.x * c - uv.y * s,
        uv.x * s + uv.y * c
    );

    // Undo aspect ratio scaling and recenter
    return uv * vec2(1.0 / aspect, 1.0) + 0.5;
}

float minorShift(float amount) {
    float bias = 0.1 * biasAmount;
    return (amount - 0.5) * 2.0 * bias; // Optimized math
}

void main() {
    vec2 uv = isf_FragNormCoord.xy * 2.0 - 1.0; // Convert to [-1,1] range
    vec2 scale = vec2(1.0 - minorShift(width), 1.0 - minorShift(height));
    uv *= scale * (1.0 - minorShift(zoom)); // Combine scaling steps
    uv = uv * 0.5 + 0.5; // Normalize back to [0,1]

    uv -= vec2(minorShift(x) * 0.5, minorShift(y) * -0.5); // Apply shifts
    uv = rotated(minorShift(rotate) * 0.25, uv); // Apply rotation

    gl_FragColor = IMG_NORM_PIXEL(inputImage, uv);
}
