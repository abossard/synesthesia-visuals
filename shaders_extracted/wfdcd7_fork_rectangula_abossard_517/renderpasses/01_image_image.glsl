/*
 * Rectangular domain coloring
 * Copyright 2019 Ricky Reusser. MIT License.
 *
 * See Common tab for cubehelix license: 
 * https://github.com/d3/d3-color
 * Copyright 2010-2016 Mike Bostock *
 * Features:
 *
 * Based on https://www.shadertoy.com/view/tlcGzf except with rectangular
 * domain coloring instead of polar.
 *
 */

// Available functions: cadd, csub, cmul, cdiv, cinv, csqr, cconj,
// csqrt, cexp, cpow, clog, csin, ccos, ctan, ccot, ccsc, csec, casin,
// cacos, catan, csinh, ccosh, ctanh, ccoth, ccsch, csech, casinh,
// cacosh, catanh
vec2 f (vec2 z, float t, vec2 mouse) {
    vec2 a = vec2(sin(t), 0.5 * sin(2.0 * t));
    vec2 b = vec2(cos(t), 0.5 * sin(2.0 * (t - HALF_PI)));
    vec2 m = mouse;

    // Try a different equation:
    // return csin((cmul(z - a, z - b, z - m)));

    return cdiv(cmul(z - a, m - b), cmul(z - b, m - a));

    z *= 0.6;
    z.x -= 0.5;
    vec2 sum = z;
    for (int i = 0; i < 10; i++) {
        sum = csqr(sum) + z;
    }
    return sum;
}
const bool animate = true;
const bool grid = true; // (when not animating)

const int octaves = 4;

// Grid lines:
const float lineWidth = 1.0;
const float lineFeather = 1.0;
const vec3 gridColor = vec3(0);

// Power of contrast ramp function

vec2 pixelToXY (vec2 point) {
  	vec2 aspect = vec2(1, iResolution.y / iResolution.x);
    return (point / iResolution.xy - 0.5) * aspect * 5.0;
}

// Select an animation state
float selector (float time) {
    const float period = 10.0;
    float t = fract(time / period);
    return smoothstep(0.4, 0.5, t) * smoothstep(1.0, 0.9, t);
}

vec3 colorscale (float phase) {
    return rainbow(phase / 2.0 - 0.25);
}

vec2 complexContouringGridFunction (vec2 x) {
  return 2.0 * abs(fract(x - 0.5) - 0.5);
}

float checkerboard (vec2 xy) {
  vec2 f = fract(xy * 0.5) * 2.0 - 1.0;
  return f.x * f.y > 0.0 ? 1.0 : 0.0;
}

vec4 rectangularDomainColoring (vec4 f_df,
                     vec2 steps,
                     vec2 baseScale,
                     vec2 gridOpacity,
                     float shadingOpacity,
                     float lineWidth,
                     float lineFeather,
                     vec3 gridColor,
                     float phaseColoring
) {
  float cmagRecip = 1.0 / hypot(f_df.xy);
  baseScale *= 10.0;

  vec2 znorm = f_df.xy * cmagRecip;
  float cmagGradientMag = hypot(vec2(dot(znorm, f_df.zw), dot(vec2(znorm.y, -znorm.x), f_df.zw)));

  float xContinuousScale = log2(cmagGradientMag) / log2(steps.x);
  float xDiscreteScale = floor(xContinuousScale);
  float xScalePosition = 1.0 - (xContinuousScale - xDiscreteScale);

  float yContinuousScale = log2(cmagGradientMag) / log2(steps.y);
  float yDiscreteScale = floor(yContinuousScale);
  float yScalePosition = 1.0 - (yContinuousScale - yDiscreteScale);

  vec2 scalePosition = 1.0 - vec2(xContinuousScale, yContinuousScale) + vec2(xDiscreteScale, yDiscreteScale);
  vec2 scaleBase = vec2(pow(steps.x, -xDiscreteScale), pow(steps.y, -yDiscreteScale)) / baseScale;

  float width1 = max(0.0, lineWidth - lineFeather);
  float width2 = lineWidth + lineFeather;

  float totalWeight = 0.0;
  float shading = 0.0;
  vec2 invSteps = 1.0 / steps;
  vec2 octaveScale = vec2(1.0);
  vec2 grid = vec2(0.0);
  vec2 gridScaleBase = vec2(
    pow(steps.x, xScalePosition),
    pow(steps.y, yScalePosition)
  );

  for(int i = 0; i < octaves; i++) {
    float w0 = i == 0 ? 1e-4 : 1.0 + float(i);
    float w1 = i == octaves - 1 ? 1e-4 : 1.0 + float(i + 1);
    float w = mix(w0, w1, xScalePosition);
    totalWeight += w;
    vec2 value = f_df.xy * scaleBase * octaveScale;

    vec2 gridSlope = baseScale * gridScaleBase / octaveScale / steps;
    //float t = 0.01;
    //float gridStrength = smoothstep(2.0 / t, 1.0 / t, 1.0 / value.x);
    vec2 xygrid = complexContouringGridFunction(value) * gridSlope;

    grid += w * vec2(smoothstep(width2, width1, xygrid.x), smoothstep(width2, width1, xygrid.y));

    shading += w * checkerboard(value);
    
    octaveScale *= invSteps;
  }

  shading = shading / totalWeight;
  grid /= totalWeight;
  grid *= gridOpacity;

  float carg = atan(f_df.y, f_df.x) * HALF_PI_INV * 2.0;
  vec3 color = mix(vec3(1.0), clamp(colorscale(carg), 0.0, 1.0), phaseColoring);

  const float gamma = 0.454;
  color.r = pow(color.r, gamma);
  color.g = pow(color.g, gamma);
  color.b = pow(color.b, gamma);
    
  color = mix(vec3(1), color, 0.97);

  float mixedGrid = max(grid.x, grid.y);
  float shade = mix(1.0, shading, shadingOpacity);
  vec3 result = clamp(mix(color * shade, gridColor, mixedGrid), vec3(0), vec3(1));

  result.r = pow(result.r, 1.0 / gamma);
  result.g = pow(result.g, 1.0 / gamma);
  result.b = pow(result.b, 1.0 / gamma);
  
  return vec4(result, 1);
}

void mainImage ( out vec4 fragColor, in vec2 fragCoord ) {
    vec2 xy = pixelToXY(fragCoord);
    vec2 mouse = pixelToXY(iMouse.xy);

    vec2 fz = f(xy, iTime * 0.2, mouse);
    
    // fwidth(fz) works, but it adds ugly anisotropy in the width of lines near zeros/poles.
    // Insead, we compute the magnitude of the derivatives separately.
    //
    // Also *NOTE* that this is a very important place in which we use `hypot` instead of an
    // algebraically equivalent built-in `length`. Floating point is limited and we lose lots
    // of our floating point domain if we're not careful about over/underflow.
    vec4 fdf = vec4(fz, vec2(hypot(dFdx(fz)), hypot(dFdy(fz))));

   	float select = animate ? selector(iTime) : (grid ? 1.0 : 0.0);

    fragColor = rectangularDomainColoring(
        fdf,
        vec2(8.0), // steps
        vec2(1.0), // scale
        mix(vec2(0.4), vec2(1.0), select), // grid opacity
        mix(0.2, 0.0, select),       // shading opacity
        lineWidth,
        lineFeather,
        gridColor,
        mix(1.0, 0.0, select)        // phase coloring
    );
}

