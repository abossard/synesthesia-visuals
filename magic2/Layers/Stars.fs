/*
{
  "CATEGORIES": [
    "Feedback"
  ],
  "DESCRIPTION": "A kaleidoscope effect that creates a star-like pattern using a 2D texture.",
  "INPUTS": [
    {
      "NAME": "opacity",
      "TYPE": "float",
      "DEFAULT": 1.0
    },
    {
      "NAME": "color",
      "TYPE": "color",
      "DEFAULT": [0.0, 0.5, 1.0, 1.0]
    },
    {
      "NAME": "speed",
      "TYPE": "float",
      "MIN": -1.0,
      "MAX": 1.0,
      "DEFAULT": 0.5
    }
  ],
  "PASSES": [
    {
      "TARGET": "BufferA",
      "PERSISTENT": false
    },
    {
      "TARGET": "BufferB"
    }
  ],
  "ISFVSN": "2"
}
*/


float star(vec2 uv, float scale, float seed, float size) {
    uv *= scale;
    vec2 s = floor(uv);
    vec2 f = fract(uv);
    vec2 p;
    float k = 3.0, d;
    
    p = 0.5 + 0.440 * sin(11.0 * fract(sin((s + seed) * mat2(7.5, 3.3, 6.2, 5.4)) * 55.0)) - f;
    d = length(p) + 0.01 * scale * 0.5;
    k = min(d, k);
    
    k = smoothstep(0.0, k, 0.025 * size);
    return k * k * k;
}

void main() {
    const float layers = 7.0;
    
    vec2 uv = isf_FragNormCoord.xy;
    vec2 size = RENDERSIZE;
    
    // Calculate zoom based on time
    float zoom = mod(TIME * speed, 1.0);
    
    // Scale and offset UV coordinates for kaleidoscope effect
    uv = ((uv * size) * 2.0 - size) / min(size.x, size.y);
    float c = 0.0;
    
    // Accumulate the star pattern based on the number of layers
    for (float i = 0.0; i < 7.0; i += 1.0) {
        c += star(uv, mod(layers + i - zoom * layers, layers), i * 6.1, opacity);
    }

    // Combine original color with the generated star pattern and modulate with modcolor
    // Set the fragment color
    gl_FragColor = vec4(vec3(c) * color.rgb, c);;
}
