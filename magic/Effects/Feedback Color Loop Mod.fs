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
      "NAME" : "light",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "contrast",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME": "hueShift",
      "TYPE": "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "saturation",
      "TYPE" : "float",
      "DEFAULT": 0.5
    },
    {
      "NAME" : "biasAmount",
      "TYPE" : "float",
      "DEFAULT": 0.25
    }
  ],
  "ISFVSN" : "2"
}
*/

vec3 cheapHueShift(vec3 color, float amount) {
    // Rotate color channels
    float angle = amount * 6.28318; // amount in [0,1] -> radians
    float s = sin(angle);
    float c = cos(angle);

    mat3 hueRotation = mat3(
        vec3(0.299 + 0.701 * c + 0.168 * s, 0.587 - 0.587 * c + 0.330 * s, 0.114 - 0.114 * c - 0.497 * s),
        vec3(0.299 - 0.299 * c - 0.328 * s, 0.587 + 0.413 * c + 0.035 * s, 0.114 - 0.114 * c + 0.292 * s),
        vec3(0.299 - 0.3 * c + 1.25  * s,   0.587 - 0.588 * c - 1.05 * s,   0.114 + 0.886 * c - 0.203 * s)
    );

    return clamp(hueRotation * color, 0.0, 1.0);
}

 
float minorShift(float amount) {
    float bias = 0.2 * biasAmount;
    return (amount - 0.5) * 2.0 * bias; // Optimized math
}

vec3 adjustSaturation(vec3 color, float saturation) {
    float gray = dot(color, vec3(0.299, 0.587, 0.114)); // Luminance (grayscale)
    return mix(vec3(gray), color, saturation); // Saturation >1.0 pushes colors beyond original
}

void main() {
	vec3 color = IMG_THIS_PIXEL(inputImage).rgb;
    float gray = dot(color, vec3(0.299, 0.587, 0.114)); 
    vec3 original = color;
    color.rgb = cheapHueShift(color.rgb, 1.0 + minorShift(hueShift) * 2.);

    color.rgb += minorShift(light);
    float contrastFactor = 1.0 + minorShift(contrast);
    color.rgb = (color.rgb - 0.5) * contrastFactor + 0.5;
    color.rgb = adjustSaturation(color.rgb, 1.0 + minorShift(saturation) * 2.);
	color = clamp(color, 0.0, 1.0);
	
	gl_FragColor = vec4(gray > 0.1 ? color : original, 1.0);
}
