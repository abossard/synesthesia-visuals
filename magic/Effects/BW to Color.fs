/*{
  "CREDIT": "RV",
  "DESCRIPTION": "Black & White (0) → Neutral (0.5) → Vibrant (1)",
  "CATEGORIES": [
    "Color Adjustment",
    "Color Effect"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "intensity",
      "TYPE": "float",
      "MIN": 0.0,
      "MAX": 1.0,
      "DEFAULT": 0.5
    }
  ]
}*/

const vec3 lumcoeff = vec3(0.3, 0.7, 0.1);

void main() {
    vec4 color = IMG_THIS_PIXEL(inputImage);

    // Grayscale
    float gray = dot(color.rgb, lumcoeff);
    vec3 desat = vec3(gray);

    // 0–0.5 range → blend towards grayscale
    float desatAmount = clamp(1.0 - intensity * 2.0, 0.0, 1.0);
    vec3 mixed = mix(color.rgb, desat, desatAmount);

    // 0.5–1.0 range → boost vibrancy
    float vibrancy = clamp((intensity - 0.5) * 2.0, 0.0, 1.0);
    float avg = (mixed.r + mixed.g + mixed.b) / 3.0;
    float mx = max(mixed.r, max(mixed.g, mixed.b));
    float amount = (mx - avg) * vibrancy * 15.0;
    vec3 vibrant = mixed - (mx - mixed) * amount;

    gl_FragColor = vec4(vibrant, color.a);
}
