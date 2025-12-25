/*{
  "DESCRIPTION": "Tilt-shift blur effect that creates a miniature/toy-like appearance by selectively blurring areas based on distance from a focus band. Simulates shallow depth of field typical of tilt-shift photography.",
  "CREDIT": "Based on techniques from grapefrukt, fubax-shaders, and Godot shaders community",
  "ISFVSN": "2.0",
  "CATEGORIES": ["FILTER", "BLUR"],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image",
      "LABEL": "Input Image"
    },
    {
      "NAME": "focusPosition",
      "TYPE": "float",
      "DEFAULT": 0.5,
      "MIN": 0.0,
      "MAX": 1.0,
      "LABEL": "Focus Position"
    },
    {
      "NAME": "focusWidth",
      "TYPE": "float",
      "DEFAULT": 0.2,
      "MIN": 0.01,
      "MAX": 0.5,
      "LABEL": "Focus Band Width"
    },
    {
      "NAME": "blurAmount",
      "TYPE": "float",
      "DEFAULT": 3.0,
      "MIN": 0.0,
      "MAX": 10.0,
      "LABEL": "Blur Amount"
    },
    {
      "NAME": "blurQuality",
      "TYPE": "float",
      "DEFAULT": 4.0,
      "MIN": 2.0,
      "MAX": 8.0,
      "LABEL": "Blur Quality (Samples)"
    },
    {
      "NAME": "tiltAngle",
      "TYPE": "float",
      "DEFAULT": 0.0,
      "MIN": -90.0,
      "MAX": 90.0,
      "LABEL": "Tilt Angle (degrees)"
    },
    {
      "NAME": "falloffCurve",
      "TYPE": "float",
      "DEFAULT": 2.0,
      "MIN": 0.5,
      "MAX": 5.0,
      "LABEL": "Falloff Curve"
    },
    {
      "NAME": "aspectRatioCorrect",
      "TYPE": "bool",
      "DEFAULT": true,
      "LABEL": "Correct Aspect Ratio"
    },
    {
      "NAME": "showFocusLine",
      "TYPE": "bool",
      "DEFAULT": false,
      "LABEL": "Show Focus Line"
    },
    {
      "NAME": "focusLineColor",
      "TYPE": "color",
      "DEFAULT": [1.0, 0.0, 0.0, 0.5],
      "LABEL": "Focus Line Color"
    }
  ]
}*/

// Gaussian weight function for smooth blur falloff
float gaussianWeight(float offset, float sigma) {
    float sigmaSq = sigma * sigma;
    return exp(-(offset * offset) / (2.0 * sigmaSq)) / (sqrt(2.0 * 3.14159265) * sigma);
}

// Calculate the distance from the focus band, considering tilt angle
float calculateFocusDistance(vec2 uv, float focusPos, float angle) {
    // Convert angle to radians
    float radAngle = radians(angle);

    // Center coordinates
    vec2 centered = uv - vec2(0.5);

    // Rotate coordinates by tilt angle
    float cosA = cos(radAngle);
    float sinA = sin(radAngle);
    vec2 rotated;
    rotated.x = centered.x * cosA - centered.y * sinA;
    rotated.y = centered.x * sinA + centered.y * cosA;

    // Adjust focus position to centered coordinates
    float adjustedFocus = focusPos - 0.5;

    // Return vertical distance from focus line in rotated space
    return abs(rotated.y - adjustedFocus);
}

// Main blur function with dynamic sample count
vec4 tiltShiftBlur(vec2 uv, float blurRadius, float quality) {
    if (blurRadius <= 0.0) {
        return IMG_NORM_PIXEL(inputImage, uv);
    }

    vec4 color = vec4(0.0);
    float totalWeight = 0.0;

    // Calculate step size based on resolution
    vec2 texelSize = 1.0 / RENDERSIZE;

    // Correct for aspect ratio if enabled
    vec2 blurScale = texelSize * blurRadius;
    if (aspectRatioCorrect) {
        float aspectRatio = RENDERSIZE.x / RENDERSIZE.y;
        blurScale.x *= aspectRatio;
    }

    // Sample in a circular pattern for better quality
    int samples = int(quality);
    float angleStep = 6.28318530718 / float(samples); // 2*PI / samples

    // Radial samples at different distances
    for (int ring = 0; ring <= samples; ring++) {
        float ringRadius = float(ring) / float(samples);
        float ringWeight = gaussianWeight(ringRadius, 0.4);

        if (ring == 0) {
            // Center sample
            vec4 sampleColor = IMG_NORM_PIXEL(inputImage, uv);
            color += sampleColor * ringWeight;
            totalWeight += ringWeight;
        } else {
            // Samples around the ring
            int ringSamples = samples * ring;
            float sampleAngleStep = 6.28318530718 / float(ringSamples);

            for (int s = 0; s < ringSamples; s++) {
                float angle = float(s) * sampleAngleStep;
                vec2 offset = vec2(cos(angle), sin(angle)) * ringRadius * blurScale;
                vec2 sampleUV = clamp(uv + offset, 0.0, 1.0);

                vec4 sampleColor = IMG_NORM_PIXEL(inputImage, sampleUV);
                color += sampleColor * ringWeight;
                totalWeight += ringWeight;
            }
        }
    }

    return color / totalWeight;
}

void main() {
    vec2 uv = isf_FragNormCoord;

    // Calculate distance from focus band
    float focusDist = calculateFocusDistance(uv, focusPosition, tiltAngle);

    // Calculate blur intensity based on distance from focus band
    // Using smoothstep for gradual transition with customizable falloff
    float normalizedDist = focusDist / (focusWidth * 0.5);
    float blurIntensity = pow(smoothstep(0.0, 1.0, normalizedDist), 1.0 / falloffCurve);

    // Calculate actual blur radius
    float blurRadius = blurAmount * blurIntensity;

    // Apply tilt-shift blur
    vec4 blurredColor = tiltShiftBlur(uv, blurRadius, blurQuality);

    // Optional: Show focus line for debugging/visualization
    if (showFocusLine) {
        float lineThickness = 0.005;
        float lineIntensity = 1.0 - smoothstep(0.0, lineThickness, focusDist);

        // Also show the focus band edges
        float bandEdgeDist = abs(focusDist - focusWidth * 0.5);
        float bandEdgeIntensity = 1.0 - smoothstep(0.0, lineThickness * 0.5, bandEdgeDist);

        float totalLineIntensity = max(lineIntensity, bandEdgeIntensity * 0.5);
        blurredColor = mix(blurredColor, focusLineColor, totalLineIntensity * focusLineColor.a);
    }

    gl_FragColor = blurredColor;
}
