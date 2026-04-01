/*{
  "DESCRIPTION": "LIDAR",
  "CREDIT": "NIKHARRON and Rhythmic Visions",
  "CATEGORIES": [
    "Stylize",
    "Glitch"
  ],
  "INPUTS": [
    {
      "NAME": "inputImage",
      "TYPE": "image"
    },
    {
      "NAME": "DEPTH",
      "TYPE": "float",
      "DEFAULT": 90,
      "MAX": 100,
      "MIN": 5
    },
    {
      "NAME": "EXTRUSION",
      "TYPE": "float",
      "DEFAULT": -0.23,
      "MAX": 1,
      "MIN": -1
    },
    {
      "NAME": "ZOFFSET",
      "TYPE": "float",
      "DEFAULT": -0.3,
      "MAX": 1,
      "MIN": -1
    },
    {
      "NAME": "SAMPLERADIUS",
      "TYPE": "float",
      "DEFAULT": 16,
      "MAX": 20,
      "MIN": 0
    },
    {
      "NAME": "CHUNKINESS",
      "TYPE": "float",
      "DEFAULT": -8,
      "MAX": 20,
      "MIN": -20
    },
    {
      "NAME": "WARPFACTORA",
      "TYPE": "float",
      "DEFAULT": 1.0,
      "MAX": 2,
      "MIN": 0.025
    },
    {
      "NAME": "WARPFACTORB",
      "TYPE": "float",
      "DEFAULT": 0.8,
      "MAX": 2,
      "MIN": 0
    },
    {
      "NAME": "GAMMA",
      "TYPE": "float",
      "DEFAULT": 2.2,
      "MAX": 10,
      "MIN": 0
    }
  ]
}*/

const float tau = 6.28318530717958647692;

vec3 ToLinear(in vec3 col) {
    return pow(col, vec3(GAMMA));
}

vec3 ToGamma(in vec3 col) {
    return pow(col, vec3(1.0 / GAMMA));
}
float GetLuma(vec2 uvPos) {
    vec3 col = IMG_NORM_PIXEL(inputImage, uvPos).rgb;
    return dot(col, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
    vec3 ray;
    ray.xy = 10.0 * (gl_FragCoord.xy - RENDERSIZE.xy * 0.5) / RENDERSIZE.xy;
    ray.z = 1.0;

    vec3 col = vec3(0);
    vec3 stp = ray / max(abs(ray.x), abs(ray.y));

    vec3 pos = stp * 1.0 + 0.5;
    vec3 c = vec3(0); 

    for (int i = 0; i < 48; i++) {
        vec2 uvPos = 0.5 + (pos.xy / RENDERSIZE.x * SAMPLERADIUS);
        
        float luma = GetLuma(uvPos);
        if (uvPos.x < 0.0 || uvPos.y < 0.0 || uvPos.x > 1.0 || uvPos.y > 1.0 ) {
            pos += stp; 
            break;
        }
        
        float z =  luma * EXTRUSION - ZOFFSET;
        float d = DEPTH * z - pos.z;

		float w = pow(max(0.0,1.0+CHUNKINESS*length(fract(pos.xy)-.5)),2.0);
        
        c = max(vec3(0), vec3(
            1.0 - abs(d + WARPFACTORB * 0.5) / WARPFACTORA,
            1.0 - abs(d) / WARPFACTORA,
            1.0 - abs(d - WARPFACTORB * 0.5) / WARPFACTORA
        ));

        col += 1.5 * (1.0 - z) * c * w * (luma > 0.15 ? 1.0 : luma / 0.15);

        pos += stp; 
    }

    gl_FragColor = vec4(ToGamma(col), 1.0);
}
