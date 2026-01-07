#include "lygia/color/vibrance.glsl"
#include "lygia/sdf/capsuleSDF.glsl"
#include "lygia/sdf/tetrahedronSDF.glsl"
#include "lygia/sdf/icosahedronSDF.glsl"

// --- Constants ---
const int MAX_RAY_STEPS = 100;
const float NORMAL_EPSILON = 0.1;
const float MIN_OBJECT_DISTANCE = 0.004;
const float SHAPE_REPEAT_SPACING = 2.5;
const float HALF_SHAPE_REPEAT_SPACING = SHAPE_REPEAT_SPACING / 2.0;
const float CAMERA_SPHERE_RADIUS = 1.05;
float glow1 = 0.0;
float glow2 = 0.0;
float glow3 = 0.0;
float cameraSphereDistance = 0.0;

// --- Utility Functions ---
// Color Palette function
vec3 spectrum(float n, int paletteIndex) {
    // Define color palettes based on index
    if (paletteIndex == 0) return _palette( n, vec3(0.5), vec3(0.5), vec3(1.0) * Color_Frequency, vec3(0.0, 0.33, 0.67)); // Neon Spectrum Fusion
    if (paletteIndex == 1) return _palette( n, vec3(0.5, clamp(0.35, 0.69, syn_BassLevel * (length(_uvc) * 2.0) + 0.5), clamp(0.35, 0.69, syn_BassLevel * (length(_uvc) * 2.0) + 0.5) + 0.5), vec3(0.5), vec3(1.0, 2.0, 1.0) * Color_Frequency, vec3(0.5, _nsin(syn_BassTime * 0.25 + TIME * 0.2) * 0.5, _nsin(syn_BassTime * 0.25 + TIME * 0.2) * 0.5 + 0.5)); // Midnight Aurora
    if (paletteIndex == 2) return _palette( n, vec3(0.5), vec3(0.5), vec3(1.0, 1.0, 2.0) * Color_Frequency, vec3(TIME * 0.0025, 0.5, TIME * 0.05 + syn_BassTime * 0.15)); // Electric Symphony
    if (paletteIndex == 3) return _palette( n, vec3(((syn_BassHits) * (length(_uvc) * 2.0)) * syn_BassPresence + 0.5, 0.5,((syn_BassHits) * (length(_uvc) * 2.0)) * syn_BassPresence + 0.5), vec3(0.5), vec3(2.0, _nsin(syn_BassTime * 0.5 + TIME * 0.2), 1.0) * Color_Frequency, vec3(0.0, 0.5, 1.0)); // Psychedelic Bass Pulse
    if (paletteIndex == 4) return _palette( n, vec3(0.5), vec3(0.5), vec3(0.5) * Color_Frequency, vec3(_ncos(syn_BassTime * 0.25 + TIME * 0.2) * 0.5 + 0.5 , _nsin(syn_BassTime * 0.25 + TIME * 0.2) * 0.5 + 0.5 , 0.75)); // Melodic Prism Shift
    if (paletteIndex == 5) return _palette( n, vec3(0.5), vec3(0.5), vec3(3., 1.5, 1.5) * Color_Frequency, vec3(0.25, 0.5, 1.0)); // Vibrant Pulse
    if (paletteIndex == 6) return _palette( n, vec3(0.885, 0.5, 0.5), vec3(0.5), vec3(2.0, 1.0, 1.0) * Color_Frequency, vec3(0.5, 0.5, 1.0)); // Vivid Spectrum Surge
    if (paletteIndex == 7) return _palette( n, vec3(0.869, 0.515, 0.515), vec3(0.500), vec3(1.000, 1.000, 0.715)  * Color_Frequency, vec3(0.738, 0.000, 0.500)); // ZoeZoe
    if (paletteIndex == 8) return _palette( n, vec3(0.95), vec3(0.5), vec3(1.0) * Color_Frequency, vec3(0.5)); // Black & White
    
    return vec3(1.0);
}

float fOpIntersectionRound(float a, float b, float r) {
	vec2 u = max(vec2(r + a,r + b), vec2(0));
	return min(-r, max (a, b)) + length(u);
}

// float spectrumTime = _fbm(syn_BassTime * 0.06 + TIME * 0.14, 1.0);

// 2D rotation function
mat2 rot2D(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

// Retrieve variables from the previous frame
vec4 getState() {
    return texelFetch(State, ivec2(0.0), 0); //texture(State, vec2(0.0));
}

// Fog function
vec3 fog(vec3 color, float rayLength, vec3 fogColor, float fogDensity) {
    float fogFactor = 1.0 - exp(-pow(rayLength, 3) * fogDensity);
    return mix(color, fogColor, fogFactor);
}

// // Averaged feedback sampling
// vec4 getAveragedFeedback(sampler2D tex, vec2 uv, float offset) {
//     vec4 sum = texture(tex, uv);
//     /*sum += texture(tex, uv + vec2(0.0, offset));
//     sum += texture(tex, uv + vec2(0.0, -offset));
//     sum += texture(tex, uv + vec2(offset, 0.0));
//     sum += texture(tex, uv + vec2(-offset, 0.0));*/
//     sum += texture(tex, uv + vec2(offset, offset));
//     sum += texture(tex, uv + vec2(offset, -offset));
//     sum += texture(tex, uv + vec2(-offset, offset));
//     sum += texture(tex, uv + vec2(-offset, -offset));
//     return sum / 5.0;
// }

// Averaged feedback sampling using texelFetch. Based on PSYBERNAUTICS feedback
vec4 getAveragedFeedback(sampler2D tex, vec2 uv, float offset) {
    ivec2 pixelUV = ivec2(_xy); // Convert uv to pixel coordinates
    vec4 sum = texelFetch(tex, pixelUV, 0); // Fetch central pixel
    /*sum += texelFetch(tex, pixelUV + ivec2(0, offset), 0);
    sum += texelFetch(tex, pixelUV + ivec2(0, -offset), 0);
    sum += texelFetch(tex, pixelUV + ivec2(offset, 0), 0);
    sum += texelFetch(tex, pixelUV + ivec2(-offset, 0), 0);*/
    sum += texelFetch(tex, pixelUV + ivec2(offset, offset), 0);
    sum += texelFetch(tex, pixelUV + ivec2(offset, -offset), 0);
    sum += texelFetch(tex, pixelUV + ivec2(-offset, offset), 0);
    sum += texelFetch(tex, pixelUV + ivec2(-offset, -offset), 0);
    return sum / 5.0;
}


// --- SDF Shapes ---
// Equations originally sourced and modified from https://github.com/jwf23/Equation-Based-Lattice-Structure-Dataset
float schwarz(vec3 p) { return (abs(dot(cos(p), vec3(1.)))); }
float gyroid(vec3 p) { return (abs(dot(sin(p), cos(p.zxy))) - .01); }
float diamond(vec3 p) {  p *= 1.05; return abs(sin(p.x) * sin(p.y) * sin(p.z) + sin(p.x) * cos(p.y) * cos(p.z) + cos(p.x) * sin(p.y) * cos(p.z) + cos(p.x) * cos(p.y) * sin(p.z)) + 0.25 * (1 - Invert_Shapes); }
float splitP(vec3 p) { p *= 0.75; return abs(1.1 * (sin(1.75 * p.x) * sin(p.z) * cos(p.y) + sin(1.75 * p.y) * sin(p.x) * cos(p.z) + sin(1.75 * p.z) * sin(p.y) * cos(p.x))-0.2 * (cos(1.75 * p.x) * cos(1.75 * p.y) + cos(1.75 * p.y) * cos(1.75 * p.z) + cos(1.75 * p.z) * cos(1.75 * p.x))-0.9 * (cos(1.75 * p.x) + cos(1.75 * p.y) + cos(1.75 * p.z))); }
float neovius(vec3 p) { return  abs(3 * (cos(p.x) + cos(p.y) + cos(p.z)) + 4 * cos(p.x) * cos(p.y) * cos(p.z)) + 0.25 * (1 - Invert_Shapes); }
float lidinoid(vec3 p) { p *= 0.85; return abs(sin(1.2 * p.x) * cos(p.y) * sin(p.z) + sin(1.2 * p.y) * cos(p.z) * sin(p.x) + sin(1.2 * p.z) * cos(p.x) * sin(p.y) - cos(1.2 * p.x) * cos(1.2 * p.y) - cos(1.2 * p.y) * cos(1.2 * p.z) - cos(1.2 * p.z) * cos(1.2 * p.x)); }
float complementaryY(vec3 p) { p *= 0.85; return abs(-sin(p.x) * sin(p.y) * sin(p.z) + sin(p.y * 2.) * sin(p.y) + sin(p.y * 2.) * sin(p.z) + sin(p.x) * sin(p.z * 2.) -cos(p.y) * cos(p.y) * cos(p.z) + sin(p.y * 2.) * cos(p.z) + cos(p.y) * sin(p.y * 2.) + cos(p.y) * sin(p.z * 2.)); }
float complementaryD(vec3 p) { p *= 0.4; return abs(cos(3 * p.x + p.y) * cos(p.z) - sin(3 * p.x) * sin(p.y) * sin(p.z) + cos(p.x) * cos(3* p.y) * cos(p.z) - sin(p.x) * sin(3 * p.y) * sin(p.z) + cos(p.x) * cos(p.y) * cos(3 * p.z) - sin(p.x) * sin(p.y) * sin(3 * p.z)) + 0.35  * (1 - Invert_Shapes); }
float complementaryS(vec3 p) { p *= 0.5; return abs((cos(2 * p.x) + cos(2 * p.y) + cos(2 * p.z)) + 2 * (sin(3 * p.x) * sin(2 * p.y) * cos(p.z) + cos(p.x) * sin(3 * p.y) * sin(2 * p.z) + sin(2 * p.x) * cos(p.y) * sin(3 * p.z)) + 2 * (sin(2 * p.x) * cos(3 * p.y) * sin(p.z) + sin(p.x) * sin(2 * p.y) * cos(3 * p.z) + cos(3 * p.x) * sin(p.y) * sin(2 * p.z))); }
float complementaryI2YStarStar(vec3 p) { p *= 0.5; return abs(2 * (sin(2. * p.x) * cos(p.y) * sin(p.z) + sin(p.x) * sin(2. * p.y) * cos(p.z) + cos(p.x) * sin(p.y) * sin(2. * p.z)) + (cos(2. * p.x) * cos(2. * p.y) + cos(2. * p.y) * cos(2. * p.z) + cos(2. * p.x) * cos(2. * p.z))); }
float d1(vec3 p) { p *= 0.5; return abs(0.5 * (cos(p.x) * cos(p.y) * cos(p.z) + cos(p.x) * sin(p.y) * sin(p.z) + sin(p.x)* cos(p.y) * sin(p.z) + sin(p.x) * sin(p.y) * cos(p.z)) - 0.5 * (sin(2 * p.x) * sin(2 * p.y) + sin(2 * p.y) * sin(2 * p.z) + sin(2 * p.z) * sin(2 * p.x)) - 0.2) + 0.7 * (1 - Invert_Shapes) + 0.3 * Invert_Shapes; }
float iWP(vec3 p) { return abs(2 * (cos(p.x) * cos(p.y) + cos(p.y) * cos(p.z) + cos(p.z) * cos(p.x)) - (cos(2 * p.x) + cos(2 * (p.y)) + cos(2 * (p.z)))) - 0.15 - 0.5  * (Invert_Shapes); }
float oCTO(vec3 p) { p *= 0.9; return abs(0.6 * (cos(p.x) * cos(p.y) + cos(p.y) * cos(p.z) + cos(p.z) * cos(p.x)) - 0.4 * (cos(p.x) + cos(p.y) + cos(p.z)) + 0.25) + 0.65 * (1. - Invert_Shapes) + 0.4 * Invert_Shapes; }
float pCP(vec3 p) { return abs(0.3 * (cos(p.x) * cos(p.y) * cos(p.z)) + 0.2 * (cos(p.x) + cos(p.y) + cos(p.z)) + 0.1 * (cos(2 * p.x) * cos(2 * p.y) * cos(2 * p.z)) + 0.1 * (cos(2 * p.x) + cos(2 * p.y) + cos(2 * p.z)) + 0.05 * (cos(3 * p.x) + cos(3 * p.y) + cos(3 * p.z)) + 0.1 * (cos(p.x) * cos(p.y) + cos(p.y) * cos(p.z) + cos(p.z) * cos(p.x))) + 0.75 * (1. - Invert_Shapes) + (0.35 * Invert_Shapes); }
float qStar(vec3 p) { p *= 0.75; return abs((cos(p.x) - 2 * cos(p.y)) * cos(p.z) - sqrt(3) * sin(p.z) * (cos(p.x - p.y) - cos(p.x)) + cos(p.x - p.y) * cos(p.z)); }
float fKS(vec3 p) { p *= 0.45; return abs(cos(2 * p.x) * sin(p.y) * cos(p.z) + cos(p.x) * cos(2 * p.y) * sin(p.z) + sin(p.x) * cos(p.y) * cos(2 * p.z)) + 0.25; }
float fKY(vec3 p) { p *= 0.5; return abs(cos(p.x) * cos(p.y) * cos(p.z) + sin(p.x) * sin(p.y) * sin(p.z) + (sin(2 * p.x) * sin(p.y) + sin(2 * p.y) * sin(p.z) + sin(p.x) * sin(2 * p.z)) + (cos(p.x) * sin(2 * p.y) + cos(p.y) * sin(2 * p.z) + sin(2 * p.x) * cos(p.z))) + 0.5 * (1- Invert_Shapes); }
float sdOctahedron( vec3 p, float s)
{
  p = abs(p);
  return (p.x+p.y+p.z-s)*0.57735027;
}

// --- SDF Retrieval ---
float getSDF(int shapeIndex, vec3 p) {
    if (shapeIndex == 0) return schwarz(p);
    if (shapeIndex == 1) return gyroid(p);
    if (shapeIndex == 2) return diamond(p);
    if (shapeIndex == 3) return splitP(p);
    if (shapeIndex == 4) return neovius(p);
    if (shapeIndex == 5) return lidinoid(p);
    if (shapeIndex == 6) return complementaryY(p);
    if (shapeIndex == 7) return complementaryD(p);
    if (shapeIndex == 8) return complementaryS(p);
    if (shapeIndex == 9) return complementaryI2YStarStar(p);
    if (shapeIndex == 10) return d1(p);
    if (shapeIndex == 11) return iWP(p);
    if (shapeIndex == 12) return oCTO(p);
    if (shapeIndex == 13) return pCP(p);
    if (shapeIndex == 14) return qStar(p);
    if (shapeIndex == 15) return fKS(p);
    if (shapeIndex == 16) return fKY(p);

    return 0.0;
}

// --- Space Modulo ---
vec3 mirroredMod(vec3 x, vec3 a) {
    return abs(mod(x + a, a * 2.0) - a);
}

// --- Scene Mapping Function ---
vec2 map(vec3 p, float shapeMix, vec3 ro) {

    // Make a copy of p for the safety sphere
    vec3 pp = p;
    
    // Apply depth movement
    float timeMod = syn_BassTime * 0.01 + TIME * 0.025;
    float zMovementFBM = _fbm(timeMod, 1.0) - 0.5;

    p.z += (0.1 * (zMovementFBM) * 2.0) + (script_time * 0.35);

    // Shift shapes before the fract
    p.xy += Shape_Shift;
    p.xy = mix(p.xy, p.xy + (vec2(cos(syn_BassTime * 0.1 + TIME * 0.15 *  .2), sin(syn_BassTime * 0.1 + TIME * 0.15 * .2))), Auto_Shape_Shift * (syn_BassPresence * syn_BassPresence));
    
    // Rotate the repetition
    p.xy = mix(p.xy, p.xy * rot2D(mod(-5.0 * sin(script_time_spin * 0.85), 2.0 * PI)), Rotate_Space);
    
    // Glow Worm
    vec3 glowWormPos = vec3(pp.xy,pp.z);
    glowWormPos.z -= (0.01 * (zMovementFBM) * 2.0) + (script_time * 0.035);
    
    // Shift shapes before the fract
    glowWormPos.xy -= Shape_Shift;
    glowWormPos.xy = mix(glowWormPos.xy, glowWormPos.xy - (vec2(cos(syn_BassTime * 0.1 + TIME * 0.15 *  .2), sin(syn_BassTime * 0.1 + TIME * 0.15 * .2))), Auto_Shape_Shift * (syn_BassPresence * syn_BassPresence));
    
    glowWormPos.xy = mix(glowWormPos.xy, glowWormPos.xy * rot2D(mod(1.0 * sin(script_time_spin * 0.85), 2.0 * PI)), Rotate_Space);
    
    vec4 buffAColor = texelFetch(BuffA, ivec2(_xy), 0);//texture(BuffA, _uv);
    float rayLength = buffAColor.w;
    float wormfbm = _fbm((0.125 * syn_BassTime + 0.5 * TIME, 1.5), 1.);
    
    float glowWorm = capsuleSDF(mirroredMod(glowWormPos, vec3(Glow_Worm_Repetition_Spacing * 5) * (1. + ((_fbm((0.0375 * syn_BassTime + 0.2 * TIME) * 0.25, 1.5) - 0.5)))),
        vec3(Glow_Worm_Distance * (1. + ((wormfbm - 0.5)))),
        vec3(4.5),
        0.01 * (1.0 + wormfbm * 0.25));
    
    
    // Space repetition
    p = mirroredMod(p, vec3(SHAPE_REPEAT_SPACING)) - (HALF_SHAPE_REPEAT_SPACING);
    
    // Rotate the spheres
    float rotationSpeed = 10.0 * sin(syn_BassTime * 0.01 + TIME * 0.015) + 10.0;
    p.xy *= rot2D(mod(rotationSpeed, 2 * PI) * Rotate_Spheres);
    p.xz *= rot2D(mod(rotationSpeed, 2 * PI) * Rotate_Spheres);

    // Reactive Sphere
     float sphereSize = Sphere_Size + (0.5 * (_fbm((syn_BassTime * 0.1) + (TIME * 0.25), 0.5 * Reactive_Sphere) - 0.5)  * syn_Intensity * Reactive_Sphere);
    sphereSize = mix(sphereSize, sphereSize + (0.35 * ((cos(sin(2.0 * ((syn_BassTime * 0.1) + (TIME * 0.25))) + (TIME * 0.25))) * sin(2.0 * ((syn_BassTime * 0.1) + (TIME * 0.25))) + 0.35)), Reactive_Sphere * syn_Presence);

    // Assemble the shapes for the Dyspun Sphere
    vec3 pyramidPos = vec3(p.x, p.z + (sphereSize * 0.6) * 0.5, p.y);
    float outerPyramid = tetrahedronSDF(pyramidPos, sphereSize * 0.6);
    float innerPyramid = tetrahedronSDF(vec3(pyramidPos.x, pyramidPos.y - Sphere_Thickness, pyramidPos.z), (sphereSize * 0.6) - Sphere_Thickness);
    float hollowPyramid = max(outerPyramid, -innerPyramid);
    float outerCube = sdOctahedron(p, sphereSize * 1.25);
    float innerCube = sdOctahedron(vec3(p.x, p.y, p.z), (sphereSize * 1.25) - Sphere_Thickness);
    float hollowCube = max(outerCube, -innerCube);
    float outerIcosahedron = icosahedronSDF(p, sphereSize);
    float innerIcosahedron = icosahedronSDF(p, sphereSize - Sphere_Thickness);
    float hollowIcosahedron = max(outerIcosahedron, -innerIcosahedron);
    float outerSphere = length(p) - sphereSize;
    float innerSphere = length(p) - (sphereSize - Sphere_Thickness);
    float hollowSphere = max(outerSphere, -innerSphere);
    float sphereSelection = (Sphere_Type) / 3.;
    hollowSphere = _mix4(hollowSphere, hollowIcosahedron, hollowCube, hollowPyramid, sphereSelection);

     // Automatically morph the sphere based on the audio
    float sphereDistortConstant = Sphere_Morph_Amount * Sphere_Size;
    hollowSphere = mix(hollowSphere, hollowSphere - ((0.5 * _fbm(_xy * 0.0025 * (1.0 + (1.0 * sphereDistortConstant)) + ((syn_BassTime * 0.005) + (TIME * 0.02)), 1.0)) * 1.0) * sphereDistortConstant, mix(1.0, syn_BassPresence * syn_Intensity, _nclamp(Auto_Sphere_Morph)));

    // Creates a sphere on the camera to cut out the shapes
    float camSphere = length(pp-ro) - CAMERA_SPHERE_RADIUS;
    
    // Retrieve variables from the last frame
    vec4 state = getState();
    float sphereType = mix(getSDF(int(state.x), shapeMix * p), getSDF(int(state.y), shapeMix * p), state.z);

    // Invert the shapes
    sphereType = mix(sphereType, 1.0 - sphereType * 0.125, Invert_Shapes);
    
    float shapes = (0.95 - sphereType) / shapeMix;

    float noiseFactor = 1.0; 
    hollowSphere = mix( hollowSphere, hollowSphere - ((0.5 + (0.25 * syn_Hits)) * _fbm(/*p * 5.0*/_xy * 0.0085 + ((syn_BassTime * 0.0025) + (TIME * 0.01)), noiseFactor)), syn_BassLevel * syn_Intensity * syn_BassPresence * Bass_Noise);
    
    float dyspunSphere = fOpIntersectionRound(hollowSphere, shapes, 0.015);
    dyspunSphere = fOpIntersectionRound(dyspunSphere, -glowWorm * 0.8 + 0.15,  0.25);
    dyspunSphere = min(dyspunSphere, glowWorm * 0.8);
    dyspunSphere = fOpIntersectionRound(-camSphere, dyspunSphere, 0.25);
    
    // Accumulate glow
    if (abs(dyspunSphere) < 0.05) {
    glow1 += 0.1 / (0.1 + pow(abs(dyspunSphere), 64.0)); // Sphere Glow
    glow2 += 0.1 / (0.1 + pow(abs(dyspunSphere), 420.0)); // Contact Glow
    }
    
    if (abs(glowWorm) < 0.05) glow3 += (0.1 / (0.1 + pow(abs(glowWorm + 1.025), 64.0))); // Glow Worm Glow
    
    float final = dyspunSphere/* * 0.8*/;
    float materialIndex = (glowWorm < 0.10) ? 1.0 : 0.0;
    
    return vec2(final, materialIndex);
}

// --- Normal Calculation Function ---
vec3 calculateNormal(vec3 pos, float shapeMix, vec3 ro, float eps) {
    vec2 e = vec2(eps, 0.0);

    return normalize(vec3(
        map(pos + vec3(e.x, 0.0, 0.0), shapeMix, ro).x - map(pos - vec3(e.x, 0.0, 0.0), shapeMix, ro).x,
        map(pos + vec3(0.0, e.x, 0.0), shapeMix, ro).x - map(pos - vec3(0.0, e.x, 0.0), shapeMix, ro).x,
        map(pos + vec3(0.0, 0.0, e.x), shapeMix, ro).x - map(pos - vec3(0.0, 0.0, e.x), shapeMix, ro).x
    ));
}

// --- State Update Function ---
vec4 state() {
    // Retrieve variables from the last frame
    vec4 prev = getState(); //.x is current, .y is next, .z is the transition, .w is the time since last transition
    
    // Change shape Manually
    if (syn_Time - prev.w > 3.9) { // Deciding when to trigger the transition
        prev.x = prev.y; // Sets the current shape to the previous next shape
        prev.y = Shape_Type; // Sets the current shape to the new next shape
        prev.z = 0.0; // Resets the timer
        prev.w = syn_Time; // Counter for the transition
    }
    
    float elapsed = syn_Time - prev.w; // Time since the start of the transition
    float duration = 3.0; // Duration of the transitions

    prev.z = 1.0;
    if (elapsed < duration) 
        prev.z = smoothstep(0., duration, elapsed); // Sets the mix factor for the transition

    return prev;
}

// --- Raymarching and Lighting Function ---
vec4 renderBuffA() {
    vec4 fragColor = vec4(0.0);
    vec2 fragCoord = _xy;
    vec2 uv = _uvc;
    vec3 rayOrigin = vec3(0.0, 0.0, 3.0);
    float spectrumTime = _fbm(syn_BassTime * 0.06 + TIME * 0.14, 1.0);

    // Equirectangular distortion 
    float th = uv.y * PI;
    float ph = uv.x * PI * 2.0;
    float toastWarp = Equirectangular_Warp;
    th = mix(uv.y * PI * 0.45, th, toastWarp);
    ph = mix(uv.x * PI * 0.6, ph, toastWarp);

    vec3 warp = normalize(vec3(sin(ph) * cos(th), sin(th), cos(ph) * cos(th)));
    float autoWarp = _nclamp(Warp * (smoothstep(0.5, 1.0, (syn_BassPresence + syn_Intensity + syn_Presence) * 0.33) * syn_Intensity));
    float warpValue = 1.0 - mix(Warp, autoWarp, Auto_Warp);
    warp = mix(warp, normalize(vec3(_uvc, 1.0)), warpValue);

    // Establish the shape values based on the controls
     float shapeMix = mix(Shape_Complexity, Shape_Complexity + (Complexity_Growth_Factor * (syn_Presence + 0.25)), 0.5 * sin(syn_BassTime * 0.2 + TIME) + 0.5);

    // Initialize cycling value for the wiggling and rotation
    vec2 fiddlyDoodad = vec2(cos(syn_BassTime * 0.15 + TIME * 0.05 * .2), sin(syn_BassTime * 0.125 + TIME * 0.05 * .2));
    float wiggleIntensity = Wiggle_Intensity;
    float autoWiggleIntensity = mix(wiggleIntensity, wiggleIntensity * (1.0 + (syn_BassPresence * 0.4) + (syn_Presence * 0.7)), Auto_Wiggle_Intensity * syn_BassPresence);
    wiggleIntensity = mix(wiggleIntensity, autoWiggleIntensity, syn_BassPresence);

    // Add intensity movements to the cycling value
    fiddlyDoodad += vec2(wiggleIntensity);

    // Initialize the ray direction as a mix between the default and the warp
    vec3 rd = normalize(mix(vec3(_uvc, 1.0), vec3(warp.xy, warp.z - 0.5), 1.0 - warpValue));

    // Rotate Camera
    mat2 cameraRotation = rot2D(mod(0.001255 + (script_time_camera * 0.85), 2.0 * PI));
    mat2 cameraRotation2 = rot2D(mod(0.001255 + (-script_time_camera * 0.85), 2.0 * PI));
    rd.xz = mix(rd.xz, rd.xz * cameraRotation, Rotate_Camera);
    rd.yz = mix(rd.yz, rd.yz * cameraRotation2, Rotate_Camera);

    // Set the reactive depth
    float depth = 85.;//Depth + 60.0;
    
    // Set Color
    vec3 toastColor = vec3(1.0);

    float lastPassEdgeColor = Color_Palette;
    if (Color_Palette > 6) lastPassEdgeColor = 0;
    if (Color_Palette < 1) lastPassEdgeColor = 7;

    float rayLength = 0.0;
    vec3 col = vec3(0.0);
    
    // Lighting variables

    vec3 lightPos1 = rayOrigin;
    
    float lightIntensity = Light_Intensity + (Light_Intensity * 0.5) * smoothstep(0.0, 1.0, (syn_BassPresence + syn_Presence) * 0.5) * syn_Intensity;
    float ambientStrength = Light_Ambient;
    float specularStrength = Light_Specular;
    float specularShininess = Light_Shininess;
    float lightDropoff = 1.0;//Light_Dropoff;
    float attenuationFactor = 0.02;//Light_Attenuation;
    vec3 glowWormColor = vec3(3.0);
    
    // shared loop variables
    vec3 surfacePosition = vec3(0.0);
    bool collisionDetected = false;
    float objectDistanceAtCollision = 0.0;
    float objectDistance;
    float materialIndex;
    vec3 pp;
    float localCameraSphereDistance = 0.0;
    

    // Raymarch
    for (int stepNum = 0; stepNum < MAX_RAY_STEPS; stepNum++) {
        vec3 rayPos = rayOrigin + rayLength * rd;

        // Rotate and Wiggle the ray
        rayPos.xy = mix(rayPos.xy, rayPos.xy * rot2D(rayLength * 0.05 * sin(syn_BassTime * 0.025 + TIME * 0.075) * 2.0), Twist_Space);
        rayPos = mix(rayPos, rayPos + sin(rayLength * (fiddlyDoodad.y) * 0.5) * 0.9, Wiggle_Space * syn_Presence);
       
        // Calculate the distance
        vec2 mapResult = map(rayPos, shapeMix, rayOrigin);
        objectDistance = mapResult.x;
        materialIndex = mapResult.y;

        // Collision & Lighting logic
        if (objectDistance < abs(MIN_OBJECT_DISTANCE) && float(stepNum) < depth) {
            surfacePosition = rayPos;
            collisionDetected = true;
            objectDistanceAtCollision = objectDistance; // Save object distance
            pp = rayPos; // copy ray position here for safety sphere calcs

            break;  // Break the loop once you hit a surface and after applying lighting
        }
        
        if (float(stepNum) >= depth || objectDistance < abs(MIN_OBJECT_DISTANCE) || rayLength >= depth * 0.45) break;
        
        // March the ray
        float materialStepScale = 1.0; // Default scale

        if (materialIndex > 0.5) { // Example: Material 1 needs more precision
            materialStepScale = 1.0;  // Increase step size
        } else { // Example: Material 2 can use larger steps
            materialStepScale = 0.75; // Reduce step size for this material
        }

        rayLength += materialStepScale/*0.7*/ * abs(objectDistance);
    }
    
    // Calculate lighting outside of main loop if the collision was detected
    if (collisionDetected) {
        // Calculate Normal
        vec3 normal = calculateNormal(surfacePosition, shapeMix, rayOrigin, NORMAL_EPSILON);
        
        // Phong Lighting for Light 1
        vec3 lightDir1 = normalize(lightPos1 - surfacePosition);
        vec3 viewDir = normalize(rayOrigin - surfacePosition);
        vec3 reflectedDir1 = reflect(-lightDir1, normal);

        // Diffuse term for Light 1
        float diff1 = max(dot(normal, lightDir1), 0.0);

        // Specular term for Light 1
        float spec1 = pow(max(dot(viewDir, reflectedDir1), 0.0), specularShininess);

        // Attenuation for Light 1
        float distToLight1 = distance(surfacePosition, lightPos1);
        float attenuation1 = 1.0 / (1.0 + attenuationFactor * pow(distToLight1, lightDropoff));

        // Combine Ambient, Diffuse and Specular for Light 1
        vec3 light1Color = spectrum(-spectrumTime + length(_uv.x) * 0.5, int(Color_Palette));

        // Diffuse and Ambient
        vec3 diffuseAmbient = (ambientStrength + diff1 * lightIntensity) * attenuation1 * light1Color;
        
        // Specular (Separate Calculation and Coloring)
        // Apply a different color to the specular component
        vec3 specularColor = mix(vec3(1.0, 1.0, 1.0), light1Color, 0.5); // Example: White specular test1
        vec3 specular = specularStrength * spec1 * attenuation1 * specularColor;
        
        specular *= specularColor; // Multiply the specular by the specular color
        
        // Combine the components
        vec3 finalLight = diffuseAmbient + specular; // Add the now-colored specular to the rest of the lighting

        vec3 light1 = finalLight;
        
        // Coloring
        vec3 baseColor;
        if (materialIndex > 0.5) {
            baseColor = glowWormColor; // White for Glow Worms
            light1 = vec3(0); // Remove lighting on Worms
        } else {
            baseColor = spectrum(-spectrumTime * ((rayLength/* + 0.15 */) * 0.5), int(Color_Palette)) * 0.5 * mix(Base_Color_Intensity, syn_BassHits * 0.5 + Base_Color_Intensity, 1.);
            if (_isMediaActive() && rayLength > 2.5 && rayLength < 5.5) baseColor *= mix( vec3(1), _loadMedia().rgb * _loadMediaAsMask().rgb, smoothstep(0.0, 0.8, (syn_BassLevel) * (syn_BassPresence)));
        }
        
        col = baseColor;
        
        col = col + (light1); // Apply lighting
        
        localCameraSphereDistance = 1.0 - abs(length(pp - rayOrigin) - CAMERA_SPHERE_RADIUS) / (0.25 * (syn_BassLevel * 0.9 + 0.1));
 
    }

    // Fog
    vec3 fogColor = Fog_Color * (1.0 - length(_uvc));
    float fogDensity = Fog_Density * 0.0005;
    fogColor = mix(fogColor, spectrum(-spectrumTime + length(_uv.x) * 0.5, int(Color_Palette)), Palette_Fog);
    fogColor *= mix(vec3(1.0), spectrum(-spectrumTime * rayLength * 0.5, int(lastPassEdgeColor)) * rayLength * 0.5, Hypno_Fog);
    
    localCameraSphereDistance = 1.0 - abs(length(pp - rayOrigin) - CAMERA_SPHERE_RADIUS) / (0.25 * (syn_BassLevel * 0.9 + 0.1));

    // Glow
    col += glow1 * 0.0015 * (spectrum(-spectrumTime * rayLength * 0.5, int(Color_Palette)) * (rayLength * 0.5)) * (smoothstep(0.0, 1.0, syn_BassLevel) * 0.85 + 0.15) * (1 - smoothstep(0, (depth * 0.25) + (0.25 * depth * Hypno_Fog), rayLength)) * (1 + Light_Glow_Intensity * 10);
    col += glow2 * 1.0 * vec3(1) * (smoothstep(0.0, 1.0, syn_BassLevel) * 0.9 + 0.1) * smoothstep(0.01, 1.0, pow(localCameraSphereDistance + 0.25, 3.0)) * Camera_Contact_Glow;
    col += glow3 * 10. * glowWormColor;
    
    col = fog(col, rayLength, _nclamp(fogColor), fogDensity);
    fragColor = vec4(pow(col, vec3(0.5)), rayLength);

    return fragColor;
}

// --- Post Processing Function ---
vec4 renderBuffB() {
    vec4 fragColor = texelFetch(BuffA, ivec2(_xy), 0);//texture(BuffA, _uv);
    vec4 media = _loadMedia();
    vec4 mediaMask = _loadMediaAsMask();
    vec2 uv = _uv;
    float spectrumTime = _fbm(syn_BassTime * 0.06 + TIME * 0.14, 1.0);
    
    vec4 buffAColor = fragColor;
    float rayLength = buffAColor.w;
    
    // Mix in Raw media at a certain brightness interval
    float mediaMixThreshold = Media_Highlight_Threshold;
    if (_luminance(media) > mediaMixThreshold && _luminance(media) < mediaMixThreshold + 0.50 && rayLength > 2.5) {
        fragColor = _isMediaActive() ? mix(fragColor, vibrance(_nclamp((media /** (1.0 - _nclamp(Feedback_Fade - (Feedback_Fade * 0.5)))*/ * mediaMask) + (fragColor * (1.0 - mediaMask)) + (_edgeDetectSobelMedia() * media * 3.0)), syn_BassHits), smoothstep(0.0, 1.0, (syn_BassLevel) * (syn_BassPresence))) : fragColor;
    }
    
    float lastPassEdgeColor = Color_Palette;
    if (Color_Palette > 6) lastPassEdgeColor = 0;
    if (Color_Palette < 1) lastPassEdgeColor = 3;
    
    // Edge Detect Shapes
    vec4 lastPassEdge;
    float edgeAmount = (syn_BassLevel * 0.9) * syn_Intensity;
    lastPassEdge = mix(fragColor, _nclamp(fragColor + ((_edgeDetectSobel(BuffA)) * syn_Presence * mix(fragColor, vec4(spectrum((0.35 * length(_uvc)) + spectrumTime * 0.95, int(lastPassEdgeColor)), 1.0), 0.5))), edgeAmount);

    fragColor = _luminance(fragColor) < 0.95 ? mix(fragColor, lastPassEdge, Edge_Detect * syn_Presence) : fragColor;
    
    // Highlight Highlights
    vec4 highlightHighlights;
    highlightHighlights = mix(fragColor, _nclamp(fragColor * vec4(1.1)), syn_BassHits);
    if (_luminance(fragColor) < 0.5) fragColor = mix(fragColor, highlightHighlights, 1.0 * syn_Presence);
    
    fragColor = vibrance(fragColor, 0.75);
    
    // Mix in Vibrance
    fragColor = mix(fragColor, vibrance(fragColor, 1.0), (syn_BassHits * syn_BassPresence));
    
    // Mix in saturation
    fragColor = mix(fragColor, _saturation(fragColor, 1.1), (syn_Intensity * syn_Presence * (syn_BassPresence * syn_BassPresence) * 0.85)); // Intensity brightness
    
    return fragColor;
}

// --- Feedback Function --- Based on PSYBERNAUTICS feedback
vec4 renderFeedback() {
    vec4 fragColor = texelFetch(BuffB, ivec2(_xy), 0)/*texture(BuffB, _uv)*/; // Sample color from buffer B
    vec2 uv = _uv;
    float offset = 1.0 / RENDERSIZE.x;
    vec4 avgFeedback = getAveragedFeedback(syn_FinalPass, uv, offset);
    
    // Feedback Flow
    float feedbackFlow = Feedback_Flow;//mix(Feedback_Flow, 1.0, Auto_Feedback_Flow);
    float auto_Feedback_Flow = mix(feedbackFlow, feedbackFlow * syn_Hits * syn_Intensity/* * syn_Presence*/, Auto_Feedback_Flow);
    offset *= mix(1.0, 25.0, auto_Feedback_Flow);
    //offset = mix(offset, offset * ((randomBassHit - 0.5) * 2.0) * syn_ToggleOnBeat, Auto_Feedback_Flow);
    
    //vec4 avgFeedback = getAveragedFeedback(syn_FinalPass, uv, offset);

    // Feedback Pan
    vec2 feedbackPan = mix(Feedback_Pan, vec2((randomPan - 0.5) * 0.0075, (randomPan2 - 0.5) * 0.0075) * (syn_Intensity * syn_BassLevel), Auto_Feedback_Pan);
    feedbackPan *= mix(1.0, (1.0 - length(_uvc)), 0.235);
    vec2 feedbackUV = ((_uv - 0.5) / (1.0 + mix(-0.01, 0.01, Feedback_Zoom)) + 0.5 - feedbackPan);
    float feedbackIntensity = 1.0; // set feedback intensity to 1 to avoid unneeded variable
    float rand1 = (randomPan - 0.5) * feedbackIntensity * syn_ToggleOnBeat;
    float rand2 = (randomPan2 - 0.5) * feedbackIntensity * syn_ToggleOnBeat;
    float rand3 = (randomPan3 - 0.5) * feedbackIntensity * syn_ToggleOnBeat;
    
    avgFeedback.rgb = _mix3(avgFeedback.rgb, avgFeedback.gbr, avgFeedback.brg, syn_BPMSin4);
    
    feedbackUV.y += avgFeedback.r * offset * (1.0 + rand1 * 0.1);
    feedbackUV.y += avgFeedback.g * offset * (1.0 + rand2 * 0.1);
    feedbackUV.y -= avgFeedback.b * offset * (1.0 + rand3 * 0.1) * 0.5;
    
    feedbackUV.x += avgFeedback.g * offset * (1.0 + rand1 * 0.1);
    feedbackUV.x += avgFeedback.b * offset * (1.0 + rand2 * 0.1) * (2 * sin(syn_BassTime * 0.035 + TIME * 0.075) - 1.) * 0.5;
    feedbackUV.x -= avgFeedback.r * offset * (1.0 + rand3 * 0.1);

    // Feedback Threshold
    float threshold = mix((1.0 - Feedback_Threshold), Feedback_Threshold, Flip_Feedback);
    threshold = mix(threshold, threshold * (1.0 + (((syn_BassPresence + syn_BassLevel) * 0.5))) - (threshold * 0.5), Auto_Feedback_Threshold);

    float feedbackFade = 1 - Feedback_Fade;

    // Get the stored rayLength
    vec4 buffAColor = texelFetch(BuffA, ivec2(_xy), 0)/*texture(BuffA, _uv)*/;
    float rayLength = buffAColor.w;

    // Calculate a depth-based feedback control
    float feedbackDepthStart = 2.5; // Start applying feedback after rayLength 1.0
    float feedbackDepthEnd = max(0.0, (7.0 * (1.0 - (((syn_BassPresence + syn_BassLevel) * 0.5))) + feedbackDepthStart)); // Full feedback by rayLength 3.5
   
    float feedbackFactor = smoothstep(feedbackDepthStart, feedbackDepthEnd, rayLength); // Map ray length to [0,1] for feedback intensity
    
    
    bool conditionMet = false;

    if (Flip_Feedback > 0.5) {
        // Bright Feedback Condition
        conditionMet = (feedbackFactor > 0.0 && 
                       fragColor.r > threshold && 
                       fragColor.g > threshold && 
                       fragColor.b > threshold && 
                       fragColor.r < 0.975 && 
                       fragColor.g < 0.975 && 
                       fragColor.b < 0.975);
    } else {
        // Dark Feedback Condition
        conditionMet = (feedbackFactor > 0.0 &&
                       fragColor.r < threshold && 
                       fragColor.g < threshold && 
                       fragColor.b < threshold);
    }

    if (conditionMet) {
    
        vec4 feedbackCol = texture(syn_FinalPass, feedbackUV);

        feedbackCol = mix(feedbackCol, _nclamp(vibrance(feedbackCol, clamp(0.3 * length(_uvc), 0.00, 0.5))), (syn_Intensity * syn_Presence * pow(syn_BassPresence, 3.0) * 0.85)); // Feedback vibrance
        
        // Calculate Saturation
        float maxColor = max(feedbackCol.r, max(feedbackCol.g, feedbackCol.b));
        float minColor = min(feedbackCol.r, min(feedbackCol.g, feedbackCol.b));
        float saturation = (maxColor - minColor) / (maxColor + 0.0001); // Added small value to prevent div 0
		saturation = clamp(saturation, 0.0, 1.0);
		
		float maxColor2 = max(fragColor.r, max(fragColor.g, fragColor.b));
        float minColor2 = min(fragColor.r, min(fragColor.g, fragColor.b));
        float saturation2 = (maxColor2 - minColor2) / (maxColor2 + 0.0001); // Added small value to prevent div 0
		saturation2 = clamp(saturation2, 0.0, 1.0);
       
		// Adjust Fade Based on Saturation
        float adjustedFeedbackFade = mix(0.2, 1.0, saturation * 4) * mix(feedbackFade, feedbackFade * (syn_Intensity + syn_BassLevel) * 0.5, Auto_Feedback_Fade);
        
        /*if (_luminance(fragColor) < 0.015) */adjustedFeedbackFade *= mix( 1.0, mix(0.5,1, saturation2), Flip_Feedback);
       
        fragColor = mix(fragColor, feedbackCol, _nclamp(adjustedFeedbackFade) * feedbackFactor); // Apply feedback based on feedbackFactor
        fragColor = mix(fragColor, vibrance(fragColor, 1.0),  smoothstep( 0.15, 1.0, syn_Intensity  * syn_BassLevel * syn_Presence * pow(syn_BassPresence, 3.0) * 0.85)); // Apply feedback based on feedbackFactor
    }

    return fragColor;
}

// --- Main Render Function ---
vec4 renderMain() {
    if(PASSINDEX == 0){
        return state();
    }
    if(PASSINDEX == 1){
        return renderBuffA();
    }
    if(PASSINDEX == 2){
        return renderBuffB();
    }
    if(PASSINDEX == 3){
        return mix( renderFeedback(), renderFeedback() * ((syn_Intensity + syn_Level) * 0.5 + 0.01), Reactive_Brightness);//return renderFeedback();
    }
}