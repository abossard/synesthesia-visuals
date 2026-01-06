#include "lygia/math/mmax.glsl"
#include "lygia/math/mmin.glsl"
#include "lygia/math/pow2.glsl"
#include "lygia/animation/easing/exponential.glsl"
#include "lygia/animation/easing/circular.glsl"
#include "lygia/animation/easing/sine.glsl"
#include "lygia/animation/easing/quadratic.glsl"
#include "lygia/draw/digits.glsl"
#include "lygia/draw/rect.glsl"
#include "lygia/space/mirrorTile.glsl"
#include "lygia/sdf/lineSDF.glsl"

// #define HQBLUR

#ifdef HQBLUR

#define SAMPLES 12
#define ANGLE_SAMPLES (3 * SAMPLES)
#define OFFSET_SAMPLES 7

#else

#define SAMPLES 9
#define ANGLE_SAMPLES (2 * SAMPLES)
#define OFFSET_SAMPLES 5

#endif

vec2 aspect(vec2 st, vec2 s) {
    st.x = st.x * (s.x / s.y);
    return st;
}

float sum( float v ) { return v; }
float sum( vec2 v ) { return v.x+v.y; }
float sum( vec3 v ) { return v.x+v.y+v.z; }
float sum( vec4 v ) { return v.x+v.y+v.z+v.w; }

float degs2rads(float degrees) {
    return degrees * 0.01745329251994329576923690768489;
}

vec2 rot2D(float offset, float angle) {
    angle = degs2rads(angle);
    return vec2(cos(angle) * offset, sin(angle) * offset);
}

vec4 bokehBlur(sampler2D sp, vec2 uv, vec2 scale) {
    if (dot(scale, vec2(0.5)) <= 1e-5) return texture(sp, uv);
    vec2 ps = (1.0 / RENDERSIZE.xy) * scale;
    vec3 col = vec3(0.0);
    float accum = 0.0;
    
    for (int a = 0; a < 360; a += 360 / ANGLE_SAMPLES) {
        for (int o = 0; o < OFFSET_SAMPLES; ++o) {
			col += texture(sp, uv + ps * rot2D(float(o), float(a))).rgb * float(o * o);
            accum += float(o * o);
        }
    }
    
    return vec4(col / accum*1.025, 1.);
}

float getRotationGradient(float dist, vec2 uv, float t) {
    float angle = atan(uv.x, uv.y);
	return fract(angle/(PI*2)-dist - t);
}

float getSquareStroke(vec2 uv, float pos, float width, float feather) {
    return stroke(mmax(abs(uv)), pos, width, feather);
}

float getSquareStroke(vec2 uv, float pos, float width) {
    return getSquareStroke(uv, pos, width, 0.);
}

float getSquareStroke(vec2 uv, float pos) {
    return getSquareStroke(uv, pos, 0.025, 0.);
}

float getAAGrid(vec2 uv, float size, float width) {
    return stroke(fract(uv.x*size), width+0.01, width) + stroke(fract(uv.y*size), width+0.01, width);
}

vec2 barrel_disto(vec2 p, float power, float speed, float freq, float time)
{   
    p *= vec2(1.0, RENDERSIZE.y/RENDERSIZE.x);
    float theta  = atan(p.y, p.x);
    float radius = length(p);
    radius = pow(radius, power*sin(radius*freq-time*speed)+1.0);

    p.x = radius * cos(theta);
    p.y = radius * sin(theta);

    return 0.5 * (p/vec2(1.0, RENDERSIZE.y/RENDERSIZE.x) + 1.0);
}

//TY for this one, meebs
vec2 getBarrelDistortion(vec2 uv) {
    float dPower = 0.2; // barrel power - (values between 0-1 work well)
    float dSpeed = 5.0;
    float dFrequency = 5.0;
    
    vec2 uvBarrel = uv*2.0-1.0;
	dPower = dPower*smoothstep(0.0, 0.1, distortion_pulse)*10.;
		//if power is 0, then don't call the distortion function since there's no reason to do it :)
	return barrel_disto(uvBarrel, dPower, dSpeed, dFrequency*(0.5 + 0.5*syn_BPMTri2*syn_BPMConfidence)*2., syn_BassTime*0.22);
}


float getGrid(vec2 fragCoord, float space, float gridWidth)
{
    vec2 p  = fragCoord - vec2(.5);
    vec2 size = vec2(gridWidth);
    
    vec2 a1 = mod(p - size, space);
    vec2 a2 = mod(p + size, space);
    vec2 a = a2 - a1;
       
    float g = min(a.x, a.y);
    return 1.0 - clamp(g, 0., 1.0);
}

vec4 getScaledGrid(vec2 uv, vec2 center, float masterScale) {
    vec2 originalUV = uv; 

    uv = (uv + center + vec2(scramble_elements, 0.5*scramble_elements)) * masterScale;
    
    vec2 uv1 = _pixelate(uv, 2. + noisy_grid);

    vec2 tile1 = sqTile(uv, 3.).xy;
    vec2 hash = _hash22(uv1);
    
    vec2 uv2 = _pixelate(uv*noisy_grid, 6.);
    vec2 tile2 = sqTile(uv*noisy_grid, 6.).xy;
    vec2 hash2 = _hash22(uv2);
    
    vec2 uv3 = _pixelate(uv*noisy_grid*noisy_grid, 9.);
    vec2 tile3 = sqTile(uv*noisy_grid*noisy_grid, 9.).xy;
    vec2 hash3 = _hash22(uv3);

    vec2 gridMixer = _pixelate(hash, 2. + noisy_grid);
    gridMixer  = _map(gridMixer, vec2(0.), vec2(0.66), vec2(0.), vec2(1.0));
    vec2 gridID = _mix3(hash, hash2, hash3, gridMixer.r);

    vec2 grid = _mix3(tile1, tile2, tile3, gridMixer.r);

    return vec4(grid, gridID.xy);
}


//Happy accident that makes a really jacked up looking grid
float getFracturedGrid(vec2 uv, float masterScale) {
    uv = abs(uv);
    vec2 uv1 = _pixelate(uv*masterScale, 2. + noisy_grid);
    vec2 uvN = _pixelate((uv + (uv - uv1 + vec2(0.0, 0.01)))*masterScale, 2. + noisy_grid);
    vec2 uvS = _pixelate((uv + (uv - uv1 + vec2(0.0, -0.01)))*masterScale, 2. + noisy_grid);
    vec2 uvE = _pixelate((uv + (uv - uv1 + vec2(0.01, 0.00)))*masterScale, 2. + noisy_grid);
    vec2 uvW = _pixelate((uv + (uv - uv1 + vec2(-0.01, 0.00)))*masterScale, 2. + noisy_grid);

    vec2 tile1 = abs(uv);
    vec2 hash = _hash22(uv1 + vec2(syn_BPMTri2*0.0005, syn_BPMSin4*0.001));
    
    vec2 hashN = _hash22(uvN);
    vec2 hashS = _hash22(uvS);
    vec2 hashE = _hash22(uvE);
    vec2 hashW = _hash22(uvW);
    
    vec2 neighbors = (hashN + hashS + hashE + hashW)/4.;

    vec2 gridMixer = _pixelate(hash, 2. + noisy_grid);
    gridMixer  = _map(gridMixer, vec2(0.), vec2(0.66), vec2(0.), vec2(1.0));

    return step(hash.x - neighbors.x, 0.2);
}


vec4 getMainElementGrid(vec2 uv, vec2 offset, float masterScale, vec2 sliderUv) {

    uv = aspect(uv, RENDERSIZE);

    vec2 uvOut = uv;
    float gridSize = 2. + noisy_grid;
    uv = (uv+offset)*masterScale;
    uv.x = mix(uv.x, mix(uv.x  + script_slider_time, uv.x  - script_slider_time,  _sqPulse(fract(uv.y - 1./gridSize), 1./gridSize,  1./gridSize)), sliderUv.x);
    uv.y = mix(uv.y, mix(uv.y  + script_slider_time, uv.y  - script_slider_time,  _sqPulse(fract(uv.x - 1./gridSize), 1./gridSize,  1./gridSize)), sliderUv.y);
    vec2 uv1 = _pixelate(uv, gridSize);
    vec2 hash = _hash22(uv1 + scramble_elements) ;
    
    float hasElement = _pixelate(fract(hash.x*0.75 + hash.y*1.5), gridSize*2.);
    hasElement = step(hasElement, _map(element_count*element_count, 0., 1., 0.3, 0.667));

    vec2 tile1 = mirrorTile(uv, gridSize).xy;
    
    return vec4(tile1.xy, hash.xy)*hasElement;
}

vec2 applyBorder(vec2 uv, float gap) {
        float wr = 1;
        float hr = 1.;
        uv = _map(uv, vec2(gap*hr, gap*wr), vec2(1.0 - gap*hr, 1.0 - gap*wr), vec2(0.), vec2(1.0))*_inRange(uv.x, gap*hr, 1.0 - gap*hr)*_inRange(uv.y, gap*wr, 1.0 - gap*wr);
    
    return uv;
}

float getRectangleBorder(vec2 uv, float width) {
    return stroke(abs(uv.x - 0.5), 0.5 - 0.00251, width) +
    stroke(abs(uv.y - 0.5), 0.5 - 0.00251, width);
}

float getRectangleBorder(vec2 uv, float width, float tolerance) {
    return stroke(abs(uv.x - 0.5), 0.5 - tolerance, width) +
    stroke(abs(uv.y - 0.5), 0.5 - tolerance, width);
}


float getRectangleBorder(vec2 uv) {
    return getRectangleBorder(uv, 0.005);
}

float sineElement(vec2 uv, float offset) {

    uv *= vec2(0.4772*2., 0.8*2.);

    uv = applyBorder(uv, 0.05);

    return stroke(uv.y + _nsin(uv.x*6. + syn_CurvedTime*0.3)*0.1 +_nsin(uv.x*20. + offset*10. + syn_Intensity*uv.x*8. + syn_BassPresence*uv.x*6. + _nsin(uv.x*6. + syn_CurvedTime*0.3)*5.
     + TIME*0.1 + syn_BassTime*0.6 + syn_Time*0.44 + syn_HighTime*0.5)*syn_Presence*0.45, 0.5 + syn_Presence*0.3, 0.03) + getRectangleBorder(uv);
}

vec4 spectrumElement(vec2 uv, float offset) {

    uv -= vec2(0., 0.18);
    uv *= vec2(0.5, 0.72)*2.;
    
    uv = applyBorder(uv, 0.03);

    vec4 spect = texture(syn_Spectrum, uv.x);
    
    float r = stroke(uv.y - spect.b*0.25 - spect.g*0.37 - spect.r*0.25, 0.05, 0.03);
    float g = stroke(uv.y - spect.b*0.25 - spect.g*0.35 - spect.r*0.28, 0.05, 0.03);
    float b = stroke(uv.y - spect.b*0.25 - spect.g*0.342 - spect.r*0.266, 0.05, 0.03);
    vec4 fragColor = vec4(r, g, b, r + g + b) + getRectangleBorder(uv);
    fragColor += stroke(uv.y, 0.1, 0.0029);
    fragColor += stroke(uv.y, 0.25, 0.0029);
    fragColor += stroke(uv.y, 0.4, 0.0029);
    fragColor += stroke(uv.y, 0.55, 0.0029);
    fragColor += stroke(uv.y, 0.7, 0.0029);
    fragColor += stroke(uv.y, 0.85, 0.0029);
    
    fragColor = _nclamp(fragColor);
    
    fragColor *= _inRange(uv.y, 0., 1.0);
    
    return fragColor;
}

float oscilloscopeElement(vec2 uv, float offset) {
    
    vec2 originalUV = uv;
    originalUV = applyBorder(originalUV, 0.02);
    uv = applyBorder(uv, 0.1);
    vec2 uvCopy = uv;

    _uv2uvc(uv);
    uv = _toPolar(uv);
    vec4 leveltrail = texture(syn_LevelTrail, uv.x);
    vec4 spect = texture(syn_Spectrum, uv.y/(0.5*PI));
    vec4 spectV = texture(syn_Spectrum, originalUV.y);

    float fragColor = stroke(uv.x + spect.a*0.3, 0.75, 0.1);
    fragColor *= getRotationGradient(0.66, uvCopy - 0.5, TIME*0.1 + syn_Time*(0.44));
        
    fragColor += stroke(uv.x*syn_MidHighPresence + leveltrail.a*0.6, 0.5, 0.044)*0.85*_inRange(uv.x, 0.02, 0.95); //highs
    fragColor += stroke(uv.x*syn_MidPresence + leveltrail.g*0.6, 0.25, 0.044)*0.85*_inRange(uv.x, 0.02, 0.95); //lows
    fragColor += stroke(uv.x*syn_BassPresence + leveltrail.b*0.6, 0.05, 0.044)*0.85*_inRange(uv.x, 0.02, 0.95); //lows
    
    float grid = getGrid(uvCopy*mmax(RENDERSIZE), RENDERSIZE.x/(RENDERSIZE.y) * 180., 2.)*_inRange(uvCopy, 0.005, 0.995)*0.5 + stroke(uvCopy.x, 0.5, 0.005) + stroke(uvCopy.y, 0.5, 0.005);
    
    float xScanner = stroke(originalUV.x, 0.04, 0.005)*0.33*_inRange(originalUV.y, 0.11, 0.847);
    xScanner += stroke(_map(originalUV.y, 0.11, 0.847, 0., 1.0), _ncos(script_knob_time + offset*10. + syn_BassTime*0.06), 0.006)*_inRange(originalUV.x, 0.02, 0.06);
    
    float yScanner = stroke(originalUV.y, 0.11, 0.005)*0.33*_inRange(originalUV.x, 0.08, 0.93);
    yScanner += stroke(_map(originalUV.x, 0.08, 0.93, 0., 1.0), _nsin(script_knob_time + offset*40. + syn_HighTime*0.04), 0.006)*_inRange(originalUV.y, 0.09, 0.13);
    
    uv = _toRect(uv);
    _uvc2uv(uv);
    return _nclamp(fragColor + getRectangleBorder(uv) + grid + xScanner + yScanner);
}

float xyScannerElement(vec2 uv, float offset) {
    vec2 borderUv = uv;
    vec2 outerUv = uv;
    borderUv -= vec2(0, -0.0833);
    borderUv  *= vec2(0.5, 0.425)*2.;

    outerUv = applyBorder(outerUv, 0.0575);
    uv = applyBorder(uv, 0.1);
    borderUv = applyBorder(borderUv, 0.015);
    borderUv *= _inRange(borderUv.y, 0., 0.925);
    
    float fragColor = 0.;
    float grid = getGrid(uv*mmax(RENDERSIZE), RENDERSIZE.x/(RENDERSIZE.y) * 90., 2.)*_inRange(uv, 0.005, 0.995)*0.5 + stroke(uv.x, 0.5, 0.005) + stroke(uv.y, 0.5, 0.005);
    vec2 centerPoint = vec2(_ncos(PI + script_knob_time + offset*17. + syn_RandomOnBeat*3. + 2.*syn_RandomOnBeat*offset), _nsin(TIME*0.05 + script_knob_time*0.85 + offset * 4. + syn_RandomOnBeat*1.5 + 2.*syn_ToggleOnBeat*offset));
    
    centerPoint = smoothstep(-0.15, 1.15, centerPoint);
    fragColor += stroke(length(uv - centerPoint), 0.001 + 0.05*syn_FadeInOut, 0.004)*_inRange(uv, 0.005, 0.995);
    fragColor += stroke(uv.x, centerPoint.x, 0.008);
    fragColor += stroke(uv.y, centerPoint.y, 0.008);
    float sdf = rectSDF(borderUv - vec2(-0.45, 0.), vec2(0.11, 1.67), mix(0., 0.003, step( 0.1, borderUv.x)) );
    float border = fill(sdf, 0.1)*_inRange(borderUv.x, 0.01, 0.055) + stroke(abs(borderUv.y- 0.5), 0.419, 0.005)*_inRange(borderUv.x, 0.04, 0.96) + stroke(borderUv.x, 0.96, 0.005)*_inRange(borderUv.y, 0.08, 0.92);

    vec2 bubbleUv = mirrorTile(borderUv + vec2(0., 0.0375), 30.).xy*_inRange(borderUv.x, 0.065, 0.939 );
    _uv2uvc(bubbleUv);
    
    float topBubbles = fill(length(bubbleUv), 0.59)*0.2 + fill(length(bubbleUv), 0.59)*0.76*_inRange(abs(borderUv.x - 0.5), 0., _pixelate(syn_HighHits, 30.)) + stroke(length(bubbleUv), 0.63, 0.1)*0.8;
    topBubbles *= _inRange(borderUv.y, 0.867, 0.891 );
    
    float bottomBubbles = fill(length(bubbleUv), 0.59)*0.2 + fill(length(bubbleUv), 0.59)*0.76*_inRange(abs(borderUv.x - 0.5), 0., _pixelate(syn_BassHits, 30.)) + stroke(length(bubbleUv), 0.63, 0.1)*0.8;
    bottomBubbles *= _inRange(borderUv.y, 0.1, 0.128 );
    
    
    return _nclamp(fragColor + getRectangleBorder(uv) + grid + border + topBubbles + bottomBubbles);
}

float BPMElement(vec2 uv, float offset) {
    float  fragColor = 0.;
    vec2 radialUv = uv;
    uv = applyBorder(uv, 0.1);
    radialUv = applyBorder(radialUv, 0.1);
    vec2 digitOffset = mix(vec2(0.42, 0.46), vec2(0.35, 0.456), step(99.95, syn_BPM));
    float bpmDigits = digits((uv - digitOffset)*0.25, syn_BPM, 0.)*(0.5 + 0.5*syn_BPMConfidence);
    
    //radial elements
    radialUv = _toPolarTrue(radialUv - 0.5);
    float xRep = 16.;
    float yRep = 44.;
    vec2 radialTileUv = mirrorTile(radialUv * vec2(xRep, yRep)).xy;
    
    float dialsSdf = rectSDF(radialTileUv - vec2(0.), vec2(0.65, 0.38), 0. );
    float innerDials = fill(dialsSdf, 0.6)*0.25;
    innerDials += fill(dialsSdf, 0.6)*_inRange(radialUv.y, 0., _pixelate(fract(syn_BPMTri + _pixelate(0.33, xRep)) + 0.03, yRep));
    innerDials *= _inRange(radialUv.x, 0.2, 0.26);
    
    float middleDials = fill(dialsSdf, 0.6)*0.25;
    middleDials += fill(dialsSdf, 0.6)*_inRange(fract(radialUv.y + 0.5), 0., _pixelate(fract(syn_BPMSin2 + 0.15) + 0.03, yRep));
    middleDials *= _inRange(radialUv.x, 0.262, 0.322);
    
    float middleOuterDials = fill(dialsSdf, 0.6)*0.25;
    middleOuterDials += fill(dialsSdf, 0.6)*_inRange(fract(radialUv.y +0.25), 0., _pixelate( syn_BPMTri2 + 0.03, yRep));
    middleOuterDials *= _inRange(radialUv.x, 0.324, 0.384);
    
    float OuterDials = fill(dialsSdf, 0.6)*0.25;
    OuterDials += fill(dialsSdf, 0.6)*_inRange(fract(radialUv.y +0.75), 0., _pixelate(syn_BPMSin4 + 0.03, yRep));
    OuterDials *= _inRange(radialUv.x, 0.386, 0.424);

    //corner buton
    float button = fill(length(abs(uv - 0.5)*2. - vec2(0.78, 0.8)), 0.01 + 0.075*fract(syn_BPMTwitcher*0.5 + 55.*_hash12(_pixelate(uv, 4.) + offset*20.)));
    button *= (0.5 + 0.5*syn_BPMConfidence);
    float border = getRectangleBorder(uv) + getRectangleBorder(uv, 0.03)*_inRange(abs(uv- 0.5)*2., 0.9 - 0.6*syn_BPMConfidence, 1.0);

    float dials = (innerDials + middleDials + middleOuterDials + OuterDials)*(0.5 + 0.5*syn_BPMConfidence);    
    return _nclamp(fragColor + bpmDigits + border + dials + button);
}

vec4 vertSpectElement(vec2 uv, float offset) {
    uv = uv.yx;
    
    vec4 fragColor = vec4(0.);

    vec2 innerUv = uv;
    uv = applyBorder(uv, 0.03);
    innerUv = applyBorder(innerUv, 0.09);
    
    float border = 0.;

    innerUv = applyBorder(innerUv, 0.03);
    vec2 gaugeUv = _map(innerUv, vec2(0.), vec2(1., 0.641), vec2(0.), vec2(1.))*_inRange(innerUv.y, 0.,  0.641)*_inRange(innerUv.x, 0.001,  1.);

    border += getRectangleBorder(_map(innerUv, vec2(0.), vec2(1., 0.641), vec2(0.), vec2(1.)))*_inRange(innerUv.y, 0.,  0.641)*_inRange(innerUv.x, 0.001,  1.);

    fragColor += border;

    innerUv = applyBorder(innerUv, 0.04);
    vec4 spect = texture(syn_Spectrum, gaugeUv.x);
    vec4 trail = texture(syn_LevelTrail, gaugeUv.x);
    vec4 trailMirror = texture(syn_LevelTrail, _mirror(gaugeUv.x-0.5));
    vec4 trailWhacky = texture(syn_LevelTrail, _mirror(abs(gaugeUv.x - 0.5) - _pixelate(_mirror(abs(gaugeUv.y - 0.5) - _pixelate(abs(gaugeUv.x - 0.5), 4.) - TIME*0.1), 4.)));
    float spectMix = trail.r*0.16 + trailMirror.r*0.13 + trailWhacky.r*0.11;
    float BassMix = trail.g*0.16 + trailMirror.g*0.16 + trailWhacky.g*0.12;
    float MidMix = trail.b*0.17 + trailMirror.b*0.16 + trailWhacky.b*0.11;
    float HighMix = trail.a*0.16 + trailMirror.a*0.17 + trailWhacky.a*0.11;
    fragColor += stroke(gaugeUv.y, 0.5, 0.01);
    fragColor += stroke(abs(gaugeUv.y - 0.5), spectMix, 0.02);
    fragColor += stroke(abs(gaugeUv.y - 0.5), BassMix, 0.01);
    fragColor += stroke(abs(gaugeUv.y - 0.5), MidMix, 0.01);
    fragColor += stroke(abs(gaugeUv.y - 0.5), HighMix, 0.01);
    
    return fragColor;
}

vec4 levelElement(vec2 uv, float offset) {
    uv = uv.yx;
    uv *= vec2(0.5, 0.625)*2.;

    vec4 fragColor = vec4(0.);
    vec2 innerUv = uv;

    uv = applyBorder(uv, 0.03);
    innerUv = applyBorder(innerUv, 0.09);

    float border = 0.;

    float bottomBorderSdf = rectSDF(innerUv - vec2(-0.447, -0.168), vec2(0.0063, 0.2479)*5., 0.);
    float bottomBorderSdfCutout = rectSDF(innerUv - vec2(-0.437, -0.168), vec2(0.0078, 0.2191)*5., 0.);
    border += fill(bottomBorderSdf, 0.1)*_inRange(innerUv.x, 0.00, 0.063)* (1.0 - fill(bottomBorderSdfCutout, 0.1)) *_inRange(innerUv.y, 0.00, 0.99);
    innerUv = applyBorder(innerUv, 0.03);
    border += getRectangleBorder(_map(innerUv, vec2(0.), vec2(1., 0.641), vec2(0.), vec2(1.)))*_inRange(innerUv.y, 0.,  0.641)*_inRange(innerUv.x, 0.001,  1.);

    innerUv = applyBorder(innerUv, 0.04);
    
    float dialNum = 12.;
    float bigDialNum = 9.;
    vec2 dialsUv = mirrorTile(innerUv, dialNum).xy;
    vec2 bigDialsUv = mirrorTile(innerUv * vec2(bigDialNum, 4.)).xy;
    
    float bigDialsSdf = rectSDF(bigDialsUv - vec2(0.), vec2(0.9, 0.95), 0. );
    float dialsSdf = rectSDF(dialsUv - vec2(0.), vec2(0.9, 0.95), 0. );
    fragColor += fill(dialsSdf, 0.6)*_inRange(innerUv.y, 0.25, 4./dialNum + 0.24)*0.25;
    fragColor += fill(bigDialsSdf, 0.6)*_inRange(innerUv.y, 0., 1./4. + 0.02)*0.25;
    fragColor += fill(bigDialsSdf, 0.6)*_inRange(innerUv.x, 0., _pixelate(syn_Level, bigDialNum))*_inRange(innerUv.y, 0., 1./4. + 0.02);
    fragColor += fill(dialsSdf, 0.6)*_inRange(innerUv.x, 0., _pixelate(syn_BassLevel, dialNum))*_inRange(innerUv.y, 0.25, 1./dialNum + 0.24);
    fragColor += fill(dialsSdf, 0.6)*_inRange(innerUv.x, 0., _pixelate(syn_MidLevel, dialNum))*_inRange(innerUv.y, 0.25 + 1./dialNum, 2./dialNum + 0.24); 
    fragColor += fill(dialsSdf, 0.6)*_inRange(innerUv.x, 0., _pixelate(syn_MidHighLevel, dialNum))*_inRange(innerUv.y, 0.25 + 2./dialNum, 3./dialNum + 0.24);
    fragColor += fill(dialsSdf, 0.6)*_inRange(innerUv.x, 0., _pixelate(syn_HighLevel, dialNum))*_inRange(innerUv.y, 0.25 + 3./dialNum, 4./dialNum + 0.24);
    
    fragColor += border;
    
    return fragColor;
}

vec4 twinklerElement(vec2 uv, float offset) {
    vec4 fragColor = vec4(0.);
        vec2 innerUv = uv;
    uv = applyBorder(uv, 0.03);
    innerUv = applyBorder(innerUv, 0.12);
    
    float majorMix = _pixelate(_hash11(_pixelate(innerUv.x - 0.5, 8.)), 3.);
    float minorMix = _pixelate(_hash11(_pixelate(innerUv.x*2., 42.)), 4.);
    float channel1 = _pulse(innerUv.y, fract(syn_ToggleOnBeat + minorMix*0.3), 0.03);
    float channel2 = _pulse(innerUv.y, quadraticInOut(_mirror(syn_BPMTwitcher*0.2 - minorMix*0.4)), 0.03);
    float channel3 = _pulse(innerUv.y, exponentialInOut(_mirror(syn_RandomOnBeat*2.)), 0.03);
    vec4 bpmBouncer = vec4(0.);
    bpmBouncer.rgb = vec3(_mix3(channel1, channel2, channel3, _map(majorMix, 0., 0.66, 0., 1.)));
    
    bpmBouncer.a = step(0.05, dot(bpmBouncer.rgb, vec3(1.)));
    
    fragColor += bpmBouncer*_inRange(innerUv.y, 0.61, 1.0);
    
    return fragColor;
}

vec4 areaMeshElement(vec2 uv, float offset) {
    
    uv -= vec2(0., 0.25);
    uv *= vec2(0.5, 1.)*2.;
    
    vec4 fragColor =  vec4(0.);
    uv = ((uv-vec2(0.3, 0.5))*0.402) + 0.5;
    uv = applyBorder(uv, 0.07);
    vec2 sqUv = uv;
    _uv2uvc(sqUv);
    
    float innerBorder = stroke(abs(sqUv.x), 0.5*0.5, 0.005) + stroke(abs(sqUv.y), 0.5, 0.005);
    innerBorder *= _inRange(abs(sqUv.x), 0., 0.5*0.5 )*_inRange(abs(sqUv.y), 0., 0.5025);
    fragColor += innerBorder;
    
    vec2 polarUv = _toPolar(sqUv*vec2(1., 0.66));
    vec2 polarUvCorrect = _toPolarTrue(sqUv*vec2(1., 0.66));
    vec2 areaUv = sqUv;
    float polarGrid = getGrid(polarUv*vec2(0.75*30., 0.155*40.) - vec2(syn_Time*0.03,0.), 5.*0.23, 0.05)*_inRange(abs(sqUv), 0., 0.5)*_inRange(abs(sqUv.x), 0., 0.25);
    fragColor += step(0.999,polarGrid)*0.25;
    
    
    vec2 primaryArea = vec2(0., _nsin(syn_Time*0.22));
    vec2 primaryAreaCurved = vec2(0., -_nsin(syn_CurvedTime*0.22));
    vec2 bassArea = _rotate(vec2(0., _nsin(syn_BassTime*0.25)), -0.45);
    vec2 bassAreaPolar = _toPolarTrue(bassArea);
    vec2 midArea = _rotate(vec2(0., _nsin(syn_MidTime*0.31)), 0.9*3.);
    vec2 midHighArea = _rotate(vec2(0., _nsin(syn_MidHighTime*0.29)), -0.9*3.);
    vec2 highArea = _rotate(vec2(0., _nsin(syn_HighTime*0.27)), 0.45);
    areaUv = _map(areaUv, vec2(0.), vec2(0.495), vec2(0.0), vec2(1.0));
    polarUv.x = _map(polarUv.x, 0., 0.495, 0.0, 1.0);
    //floating dots for area oscilators
    fragColor += fill(length(areaUv - primaryArea), 0.013);
    fragColor += fill(length(areaUv - primaryAreaCurved), 0.013);
    fragColor += fill(length(areaUv - bassArea), 0.013);
    fragColor += fill(length(areaUv - highArea), 0.013);
    fragColor += fill(length(areaUv - midArea), 0.013);
    fragColor += fill(length(areaUv - midHighArea), 0.013);
        
    //main lines between oscilators
    float line1 = lineSDF(areaUv, primaryArea, bassArea);
    float line2 = lineSDF(areaUv, bassArea, midHighArea);
    float line3 = lineSDF(areaUv, midHighArea, primaryAreaCurved);
    float line4 = lineSDF(areaUv, primaryAreaCurved, midArea);
    float line5 = lineSDF(areaUv, midArea, highArea);
    float line6 = lineSDF(areaUv, highArea, primaryArea );

    fragColor += fill(line1, 0.003);
    fragColor += fill(line2, 0.003);
    fragColor += fill(line3, 0.003);
    fragColor += fill(line4, 0.003);
    fragColor += fill(line5, 0.003);
    fragColor += fill(line6, 0.003);

    //halfway points
    vec2 halfway1 = mix(primaryArea, bassArea, 0.5)*0.66;
    vec2 halfway2 = mix(bassArea, midHighArea, 0.5)*0.66;
    vec2 halfway3 = mix(midHighArea, primaryAreaCurved, 0.5)*0.66;
    vec2 halfway4 = mix(primaryAreaCurved, midArea, 0.5)*0.66;
    vec2 halfway5 = mix(midArea, highArea, 0.5)*0.66;
    vec2 halfway6 = mix(highArea, primaryArea, 0.5)*0.66;

    fragColor += fill(length(areaUv - halfway1), 0.01);
    fragColor += fill(length(areaUv - halfway2), 0.01);
    fragColor += fill(length(areaUv - halfway3), 0.01);
    fragColor += fill(length(areaUv - halfway4), 0.01);
    fragColor += fill(length(areaUv - halfway5), 0.01);
    fragColor += fill(length(areaUv - halfway6), 0.01);
    

    //secondary lines
    float lineSecondary1a = lineSDF(areaUv, primaryArea, halfway1);
    float lineSecondary1b = lineSDF(areaUv, bassArea, halfway1);
    float lineSecondary12 = lineSDF(areaUv, halfway1, halfway2);
    float lineSecondary2a = lineSDF(areaUv, bassArea, halfway2);
    float lineSecondary2b = lineSDF(areaUv, midHighArea, halfway2);
    float lineSecondary23 = lineSDF(areaUv, halfway2, halfway3);
    float lineSecondary3a = lineSDF(areaUv, midHighArea, halfway3);
    float lineSecondary3b = lineSDF(areaUv, primaryAreaCurved, halfway3);
    float lineSecondary34 = lineSDF(areaUv, halfway3, halfway4);
    float lineSecondary4a = lineSDF(areaUv, primaryAreaCurved, halfway4);
    float lineSecondary4b = lineSDF(areaUv, midArea, halfway4);
    float lineSecondary45 = lineSDF(areaUv, halfway4, halfway5);
    float lineSecondary5a = lineSDF(areaUv, primaryAreaCurved, halfway5);
    float lineSecondary5b = lineSDF(areaUv, highArea, halfway5);
    float lineSecondary56 = lineSDF(areaUv, halfway5, halfway6);
    float lineSecondary6a = lineSDF(areaUv, highArea, halfway6);
    float lineSecondary6b = lineSDF(areaUv, primaryArea, halfway6);
    float lineSecondary61 = lineSDF(areaUv, halfway6, halfway1);
    
    fragColor += fill(lineSecondary1a, 0.002);
    fragColor += fill(lineSecondary1b, 0.002);
    fragColor += fill(lineSecondary12, 0.002);
    fragColor += fill(lineSecondary2a, 0.002);
    fragColor += fill(lineSecondary2b, 0.002);
    fragColor += fill(lineSecondary23, 0.002);
    fragColor += fill(lineSecondary3a, 0.002);
    fragColor += fill(lineSecondary3b, 0.002);
    fragColor += fill(lineSecondary34, 0.002);
    fragColor += fill(lineSecondary4a, 0.002);
    fragColor += fill(lineSecondary4b, 0.002);
    fragColor += fill(lineSecondary45, 0.002);
    fragColor += fill(lineSecondary5a, 0.002);
    fragColor += fill(lineSecondary5b, 0.002);
    fragColor += fill(lineSecondary56, 0.002);
    fragColor += fill(lineSecondary6a, 0.002);
    fragColor += fill(lineSecondary6b, 0.002);
    fragColor += fill(lineSecondary61, 0.002);
    
    ///Dials
    float dialWidth = 0.015;
    vec2 dialsUv = applyBorder(uv, 0.141);
    float presenceDial = stroke(circularIn(fract(pow2(abs(dialsUv.y - 0.5)*7.+ 0.33) * 1.3)), 0.09, 0.03) + fill(abs(dialsUv.y - 0.5), syn_Presence*0.5);
    fragColor += vec4(presenceDial*_inRange(dialsUv.x, 0.69, 0.725));
    float BassPresenceDial = stroke(circularIn(fract(pow2(abs(dialsUv.y - 0.5)*7.+ 0.33) * 1.3 + offset*5.)), 0.09, 0.03) + fill(abs(dialsUv.y - 0.5), syn_BassPresence*0.5);
    fragColor += vec4(BassPresenceDial*_inRange(dialsUv.x, 0.74, 0.755));
    float MidPresenceDial = stroke(circularIn(fract(pow2(abs(dialsUv.y - 0.5)*7.+ 0.33) * 1.3 + offset*5.)), 0.09, 0.03) + fill(abs(dialsUv.y - 0.5), syn_MidPresence*0.5);
    fragColor += vec4(MidPresenceDial*_inRange(dialsUv.x, 0.77, 0.785));
    float MidHighPresenceDial = stroke(circularIn(fract(pow2(abs(dialsUv.y - 0.5)*7.+ 0.33) * 1.3 + offset*5.)), 0.09, 0.03) + fill(abs(dialsUv.y - 0.5), syn_MidHighPresence*0.5);
    fragColor += vec4(MidHighPresenceDial*_inRange(dialsUv.x, 0.8, 0.815));
    float highPresenceDial = stroke(circularIn(fract(pow2(abs(dialsUv.y - 0.5)*7.+ 0.33) * 1.3 + offset*5.)), 0.09, 0.03) + fill(abs(dialsUv.y - 0.5), syn_HighPresence*0.5);
    fragColor += vec4(highPresenceDial*_inRange(dialsUv.x, 0.83, 0.845));

    

    return fragColor*_inRange(uv, 0.005, 0.995);
}

float getCircuitsGrid(){
    return getFracturedGrid(_uvc*vec2(RENDERSIZE.y/RENDERSIZE.x, 1.), 0.75*5.)-getFracturedGrid(_uvc*vec2(RENDERSIZE.y/RENDERSIZE.x, 1.)+vec2(0.0035), 0.75*5.) + 
    getFracturedGrid(_uvc*vec2(RENDERSIZE.y/RENDERSIZE.x, 1.), 0.75*3.)-getFracturedGrid(_uvc*vec2(RENDERSIZE.y/RENDERSIZE.x, 1.)+vec2(0.0065), 0.75*3.) + getFracturedGrid(_uvc*vec2(RENDERSIZE.y/RENDERSIZE.x, 1.), 0.75*1.)-getFracturedGrid(_uvc*vec2(RENDERSIZE.y/RENDERSIZE.x, 1.)+vec2(0.0135), 0.75*1.);
}

vec4 renderGridPass() {
    vec4 fragColor = vec4(0.);
    
    float gridSize = 2. + noisy_grid;

    vec2 grid1Uv = _uvc*0.72;
    vec2 grid2Uv = _uv*0.66;
    vec2 grid3Uv = (_uvc*1.33 + script_drift*0.33)*(0.4 + pow2(depth)*0.8);
    
    vec2 slider1Uv = vec2(0.);
    slider1Uv.x = mix(grid2Uv.x  + script_slider_time, grid2Uv.x  - script_slider_time, _sqPulse(fract(grid2Uv.y - 1./gridSize), 1./gridSize,  1./gridSize));
    
    vec4 grid1 = getScaledGrid(grid1Uv, script_drift*0.36, 0.4 + pow2(depth*2.));
    vec4 grid1offset = getScaledGrid(grid1Uv - 0.5*0.72 + slider1Uv, script_drift*0.36, 0.4 + pow2(depth*2.));
    vec4 grid2 = getScaledGrid(grid2Uv - 0.5, script_drift*0.33, 0.4 + pow2(depth*2.));
    
    vec2 slider3Uv = vec2(0.);
    slider3Uv.y = mix(grid3Uv.y  + script_slider_time, grid3Uv.y  - script_slider_time, _sqPulse(fract(grid1Uv.x - 1./gridSize), 1./gridSize,  1./gridSize));
    vec4 grid3 = getScaledGrid(grid3Uv + slider3Uv, script_drift*0.36, 0.4 + pow2(depth*2.));
    vec4 grid3offset = getScaledGrid(grid3Uv - 0.5, script_drift*0.36, 0.4 + pow2(depth*2.));
    
	_uv2uvc(grid1.xy);

	float squareStrokeGrid = getSquareStroke(grid1.xy, fract(TIME*0.01 + syn_HighTime*0.06 + syn_BassTime*0.06  + grid1.z + grid1.w));
    fragColor += squareStrokeGrid;
    
    float squareStrokeGrid2 = getSquareStroke((grid3.xy - 0.5)*9., fract(TIME*0.01 + 0.33 + syn_HighTime*0.06 + syn_BassTime*0.06  + grid3.z + grid3.w));
    fragColor += squareStrokeGrid2;
    
    vec4 sqGrid = vec4(getAAGrid(_uvc + script_drift*0.5, 1.5 + depth*6., 0.01))*_noise(_uvc.xy + script_drift*0.5 + vec2(TIME*0.12, syn_MidHighTime*0.02));
    fragColor += sqGrid;
    
    vec4 sqGrid2 = vec4(stroke(fract(grid3offset.x*20.), 0.05, 0.02) + stroke(fract(grid3offset.y*20.), 0.05, 0.02))*_noise(grid3offset.xy + vec2(syn_Time*0.12, TIME*0.02))*0.5;
    fragColor += sqGrid2;
    
    _uvc2uv(grid1.xy);

    float microGridSize = 4.;
    vec2 microCells = _pixelate(grid1offset.xy, microGridSize);
    vec2 microCellHash = _hash22(microCells + grid1offset.zw);
    vec4 microGrid = mirrorTile(grid1offset.xy, microGridSize);
    
    
    float macroSweeper1 = _pulse(grid1offset.x, fract(syn_Time*0.1 + length(grid1offset.zw)*5.), 0.06);
    float macroSweeper2 = _pulse(grid1offset.y, fract(syn_Time*0.1 + length(grid1offset.zw)*5.), 0.06);
    float microSweeper1 = _pulse(microGrid.x, fract(syn_Time*0.1 + length(microCellHash)*5.), 0.06);
    float microSweeper2 = _pulse(microGrid.y, fract(syn_Time*0.1 + length(microCellHash)*5.), 0.06);
    fragColor += mix(microSweeper1, microSweeper2, step(microCellHash.y, 0.5))*step(0.92, microCellHash.x);
    fragColor += mix(macroSweeper1, macroSweeper2, step(grid1offset.w, 0.5))*step(0.92, grid1offset.z);
    
    fragColor += stroke(fract(grid2.y * 6.), 0.1, 0.05)*sineInOut(syn_BassTime*0.22)*step(0.8, grid2.z);
    float vertScanners = stroke(fract(grid2.x * 10.), 0.1, 0.07);
    vertScanners *= _pulse(grid2.y, quadraticInOut(_mirror(syn_HighTime*0.22 + _pixelate(grid2.x, 10.)*12. + grid2.z*7.)), 0.1) + _pulse(grid2.y, circularInOut(_mirror(syn_MidTime*0.28 + _pixelate(grid2.x, 10.)*12. + grid2.w*7.)), 0.1);
    fragColor += _nclamp(vertScanners)*step(0.8, grid2.w);
    
    //dot chaser
    vec4 dotGrid = grid3;
    vec4 dotUvTile = mirrorTile(dotGrid.xy, 24.);

    
    dotGrid.x = mix(dotGrid.x, 1.0 - dotGrid.x, step(mod(dotGrid.y*24., 2. ), 1.));
    
    float dotChaserUpper = mirror(syn_BPMTwitcher* 0.09 + _pixelate(dotGrid.y, 12.)  + 9.*dotGrid.z);
    float dotChaserLower = mirror(syn_BPMTwitcher* 0.06 + _pixelate(dotGrid.y, 6.)  + 9.*dotGrid.z - 0.33);
    fragColor += stroke(length(dotUvTile.xy - 0.5), 0.1, 0.04)*_inRange(_pixelate(dotGrid.x, 24.), dotChaserLower, dotChaserUpper);
    
    vec2 strobePanels = _pixelate(grid2.xy*vec2(3.5, 0.5)*2.2, 10.);
    vec2 strobeHash = _hash22(strobePanels);
    
    fragColor += _pulse(strobeHash.y, _statelessContinuousChaotic(TIME*0.0001)*0.5 + 0.5, 0.1)*step(0.96, strobeHash.x);
    
    fragColor.y = grid1.z;
    fragColor.z = grid2.z;
    fragColor.w = grid3.z;
    
    return fragColor;
}


float geLayerZoom(float value, float multiplier) {
    return mix(0.05 + pow2(value)*1.618*multiplier, value, (1.0-use_parallax));
    
}

float getLayerFocus(float value, float offset) {
    return smoothstep(0., 0.33, abs(pow2(value) - offset) - 0.333/2.)*(use_parallax);
}

float getLayerVisibility(float value, float offset) {
    //layer depths:
        //0.
        //0.33
        //0.66
    float minVisibility = 1.;
    minVisibility = mix(0.75, minVisibility, use_parallax);
    return max(minVisibility, _pulse(value, offset, 0.55));
}


vec4 renderWidgetsPass() {
    	vec2 position = _uv;

	vec4 fragColor = vec4(0.);
	vec4 mainElementUV = getMainElementGrid((_uv - 0.5)*1.15, script_drift*(2. - 1.5*depth), geLayerZoom(depth, 1.5), vec2(1., 0.));
	vec4 mainElementVertUV = getMainElementGrid(((_uv.xy - 0.5)*vec2(1., 1.)), script_drift.xy*(2. - 1.5*depth), geLayerZoom(depth, 2.), vec2(0., 1.));
    vec4 sine = vec4(sineElement(mainElementUV.xy, mainElementUV.z));
    vec4 spectrum = vec4(spectrumElement(mainElementUV.xy, mainElementUV.z));

    vec4 levels = levelElement(mainElementVertUV.xy, mainElementVertUV.z);
    vec4 vertSpect = vertSpectElement(mainElementVertUV.xy, mainElementVertUV.z);

    vec4 areaMesh = areaMeshElement(mainElementUV.xy, mainElementUV.z);
    
    fragColor = _mix3(sine, spectrum, areaMesh, _map(_pixelate(mainElementUV.z, 3.), 0., 0.66, 0., 1.0));
    fragColor += mix(levels, vertSpect, step(0.5, mainElementVertUV.z));
    
    fragColor.yz = mainElementUV.zw;
    fragColor.w = mainElementVertUV.z;

    return fragColor;
}

vec4 renderSecondaryWidgetsPass() {
    vec4 fragColor = vec4(0.);
    vec2 uv = _uv;
        
    vec4 mainElementUvSq = getMainElementGrid(uv*0.215 , script_drift*(2. - 1.5*depth), geLayerZoom(depth, 3.), vec2(1., 0.));

    float oscilloscope = oscilloscopeElement(mainElementUvSq.xy, mainElementUvSq.z);
    float xyScanner = xyScannerElement(mainElementUvSq.xy, mainElementUvSq.z);
    float bpmElement = BPMElement(mainElementUvSq.xy, mainElementUvSq.z);
    
    fragColor += _mix3(vec4(xyScanner), vec4(oscilloscope), vec4(bpmElement), _map(_pixelate(mainElementUvSq.w, 3.), 0., 0.66, 0., 1.0));
    fragColor.zw = mainElementUvSq.zw;
    return fragColor;
}

vec4 getLayerComposite() {
    vec2 uv = _uv;
    vec2 barrelUv = getBarrelDistortion(uv);
    float distortionPulseDepth = smoothstep(0., 0.3, distortion_pulse);
    uv = mix(_uv, barrelUv, distortionPulseDepth);
    vec4 backgroundRaw = texture(Background, uv);
    float backgroundFocus = getLayerFocus(depth + 0.13, 0.);
    float backgroundVisibility = mix(getLayerVisibility(depth, 0.), 1., smoothstep(0.85, 0.93, depth));
    vec4 background = bokehBlur(Background, uv, vec2(3.*backgroundFocus));
    distortionPulseDepth = smoothstep(0.1, 0.4, distortion_pulse);
    uv = mix(_uv, barrelUv, distortionPulseDepth);
    
    vec4 widgetsRaw = texture(Widgets, uv);
    float widgetFocus = _nclamp(getLayerFocus(depth*1.618, 0.72) - smoothstep(0.9, 0.93, depth)*0.8*max(0.7, smoothstep(0.8, -0.6, abs(_uvc.y)*1.33)));
    float widgetsVisibility = getLayerVisibility(depth, 0.44) * smoothstep(0.18, 0.23, depth);

    vec4 widgets = bokehBlur(Widgets, uv, vec2(1.5*widgetFocus));
    distortionPulseDepth = smoothstep(0.2, 0.5, distortion_pulse);
    uv = mix(_uv, barrelUv, distortionPulseDepth);
    
    vec4 widgetsSecondaryRaw = texture(Widgets_Secondary, uv);
    float widgetsSecondaryFocus = _nclamp(getLayerFocus(depth*1.618, 1.9) - smoothstep(0.9, 0.93, depth)*smoothstep(0.7, -0.4, abs(_uvc.y)*1.33));
    float widgetsSecondaryVisibility = getLayerVisibility(depth, 0.89) * smoothstep(0.5, 0.57, depth);
    vec4 widgetsSecondary = bokehBlur(Widgets_Secondary, uv, vec2(1.5*widgetsSecondaryFocus));

    vec4 layerComposite = widgets*widgetsVisibility + widgetsSecondary*widgetsSecondaryVisibility + background*backgroundVisibility;

    layerComposite.y = backgroundRaw.y;
    layerComposite.z = widgetsRaw.z;
    layerComposite.w = widgetsSecondaryRaw.w;
    
    return layerComposite;
}

vec4 renderFirstFeedbackPass() {
    vec4 fragColor = vec4(0.);

    vec4 layerComposite = getLayerComposite();

    fragColor = layerComposite.xxxx;
    vec4 edge = _edgeDetect(Feedback1, _uv);
    vec4 edgeMedia = _edgeDetectMedia();
    vec4 rawMedia = _loadMedia();

    vec4 me = texture(Feedback1, _xy / RENDERSIZE);
    vec4 blurryMe = texture(Feedback1, _uv, 3.);
    float offset = 2.;
    vec4 N = texture(Feedback1, (_xy + vec2(0., offset))/RENDERSIZE, 3. );
    vec4 S = texture(Feedback1, (_xy + vec2(0., -offset))/RENDERSIZE, 3. );
    vec4 E = texture(Feedback1, (_xy + vec2(-offset, 0.))/RENDERSIZE, 3. );
    vec4 W = texture(Feedback1, (_xy + vec2(offset, 0.))/RENDERSIZE, 3. );
    
    float nieghborhood = ( N.z + S.z + E.z + W.z)/4.;
    
    vec4 neighborDelta = (4.*blurryMe.z - N - S - E - W)/4.;
    vec4 lastFrameBlur = texture(Feedback1, _uv, 0.6385*(2.1 - 2.*unfurl_feedback*nieghborhood*_rand(_uv + TIME)));
    vec4 lastFrameBlur2 = texture(Feedback1, _uv, 0.6385*2.1); 
    
    vec2 convect = vec2(E.y - W.y , S.y - N.y)*4.;
    float convectDistanceLowerBounds = smoothstep(0.08,0.08+ 0.15,length(convect/3.))*smoothstep(0.25 + 0.25, 0.25, lastFrameBlur.y);
    vec2 convectUV = (_xy + convect*2.)/RENDERSIZE;
    vec4 feedbackConvect = texture(Feedback1, convectUV);
    vec4 mediaConvect = _textureMedia(convectUV, 0.);
    float mediaConvectLum = _luminance(mediaConvect)*mediaConvect.a;
    
    vec2 advect = vec2(W.x - E.x , N.x - S.x)*3.;

    float advectDistance = smoothstep(0.06, 0.06 + 0.15, length(advect/3.))*smoothstep(0.05 + 0.15, 0.05 , length(advect/3.));
    float advectDistanceLowerBounds = smoothstep(0.05,0.05+ 0.05,length(advect/2.))*smoothstep(0.03, 0.0, me.x);
    vec2 advectUV = (_xy + advect*2.)/RENDERSIZE;
    vec4 feedbackAdvect = texture(Feedback1, advectUV);
    vec4 mediaAdvect = _textureMedia(advectUV, 0.);
    float mediaAdvectLum =  _luminance(mediaAdvect)*mediaAdvect.a;

    vec4 feedback = me;

    float feedbackMixer = exponentialOut(master_feedback);

    float compositeFeedbackFeeder = smoothstep(0.02, 0.75, layerComposite.x);
    float compositeFeedbackKiller = smoothstep(0.4, 0.00, layerComposite.x);


    float feedbackMerged1 = feedbackAdvect.x - compositeFeedbackKiller*0.004 + _nclamp(me.x) * (0.002)*feedbackMixer*(1.0-unfurl_feedback);
    float feedbackMerged2 = feedbackConvect.y * 0.666 + lastFrameBlur2.y*0.333 + _luminance(mediaAdvect)*0.05 - compositeFeedbackKiller*0.003 + _nclamp(me.x) * (0.003 * (1.0 - unfurl_feedback))*feedbackMixer;
    float feedbackMerged3 = lastFrameBlur2.z + edge.z  - compositeFeedbackKiller*0.02;
    
    
    if(_isMediaActive()) {
        feedbackMerged1 = feedbackMerged1 * max(multiply_media, smoothstep(-0.2, 0.35, mediaAdvectLum)) + _nclamp(mediaAdvectLum - (1.0 - media_mix)*0.5)*0.05;
        feedbackMerged2 = feedbackMerged2 * max(multiply_media*mediaConvect.a, smoothstep(-0.2, 0.35, mediaConvectLum)) + _nclamp(mediaConvectLum - (1.0 - media_mix)*0.5)*0.05;
        feedbackMerged3 = feedbackMerged3 * max(multiply_media*rawMedia.a, smoothstep(-0.2, 0.35, _luminance(rawMedia))) + _luminance(1.0 - edgeMedia)*0.025 +  _nclamp(_luminance(edgeMedia*3.)  - media_mix)*0.05;
    }

    feedbackMerged1 += unfurl_feedback*advectDistance + advectDistanceLowerBounds*unfurl_feedback;
    feedback.x = mix(compositeFeedbackFeeder*1.3, feedbackMerged1, feedbackMixer*(1.0-compositeFeedbackFeeder));
    
    feedbackMerged2 += convectDistanceLowerBounds*unfurl_feedback;
    feedback.y = mix(compositeFeedbackFeeder*1.3, feedbackMerged2, feedbackMixer*(1.0-compositeFeedbackFeeder));
        
    float unfurl3 = smoothstep(0.46 + 0.073, 0.46, nieghborhood);

    feedbackMerged3 -=  unfurl_feedback*unfurl3*0.15*(_hash12(neighborDelta.z + _uvc + TIME)) + _noise(vec3(_uvc*5. + neighborDelta.z, TIME + syn_CurvedTime))*0.085*syn_RandomOnBeat;
    feedback.z = mix(compositeFeedbackFeeder*1.3, feedbackMerged3, feedbackMixer*(1.0-compositeFeedbackFeeder));

    fragColor = feedback;

    return fragColor;
}

vec3 getColor(float val, float hueAdjust, bool withBlack) {
    float trimmedVal = _mirror(circularIn(val )* (0.5 + 5.*pow2(palette_mod)) + val*0.1  + color_offset*2.);

    vec3 color1 = _mix5(
        _normalizeRGB(89, 11, 21),
        _normalizeRGB(156, 3, 17),
        _normalizeRGB(227, 136, 32),
        _normalizeRGB(202, 220, 49),
        _normalizeRGB(222, 204, 0), trimmedVal);

    vec3 color2 = _mix5(
        _normalizeRGB(0, 63, 98),
        _normalizeRGB(10, 173, 168),
        _normalizeRGB(0, 112, 90),
        _normalizeRGB(100,209, 46),
        _normalizeRGB(179, 255, 59), trimmedVal);

    vec3 color3 = _mix4(
        _normalizeRGB(61, 14, 90),
        _normalizeRGB(128,45,97),
        _normalizeRGB(155, 62, 200),
        _normalizeRGB(241, 205, 45),
        trimmedVal);
        
    vec3 color4 = _mix5(
        _normalizeRGB(21, 31, 55),
        _normalizeRGB(16, 5, 120),
        _normalizeRGB(5, 147, 162),
        _normalizeRGB(255, 122, 72),
        _normalizeRGB(227, 55, 30),
        trimmedVal);
    
    vec3 mediaRaw = _loadMedia().rgb;
    vec2 uv = _uv - 0.5;
    uv *= 0.95;
    uv += 0.5;
    vec3 mediaLod = _textureMedia(uv,4.).rgb;
    vec3 mediaColor = min(mediaRaw, mediaLod*trimmedVal*3.);
        
    vec3 outColor = _mix4(color1, color2, color3, color4, color_select*0.33);
    
    outColor = mix(outColor, mediaColor, use_media_col);
    
    if(withBlack) {
        outColor = mix(outColor, vec3(0.), smoothstep(0.18, 0.025, trimmedVal ));
    }
    
    outColor = _hueRotate(outColor, hueAdjust*mmax(_uvc)*4. + hue_offset*200.);
    
    return outColor;
}

vec4 renderFinalPass() {
        vec4 fragColor = vec4(0.);

    vec4 layerComposite = getLayerComposite();
    vec4 lastFrame = texture(Feedback1, _uv);
    float feedbackMix = _mix3(lastFrame.x, lastFrame.y, lastFrame.z, _map(feedback_style, 0., 2., 0., 1.));
    vec4 media = _loadMedia();
    vec4 rawMedia = media;
    float mergedElements = _luminance(rawMedia) + feedbackMix;
    
    //our gradient for coloring main elements
    float gradientVal = _ncos(dot(_uv, vec2(2.))*.3 + script_bass_beat_time);
    gradientVal = mix(gradientVal, _mirror(length(_uvc*2. ) + script_bass_beat_time), _nclamp(coloring_style));
    gradientVal = mix(gradientVal, fract(pow(_noise(vec3(_uvc*3., script_bass_beat_time)), 2.) + TIME*0.1), _nclamp(coloring_style - 1));
    gradientVal = mix(gradientVal, _nsin(layerComposite.y + layerComposite.z*1.5 + layerComposite.w*2. + script_bass_beat_time), _nclamp(coloring_style - 2));
    gradientVal = mix(gradientVal, _mirror(smoothstep(0.03, 0.75, layerComposite.x) + _luminance(rawMedia)*1.5 + sqrt(layerComposite.x)*3. + 0.33  + script_bass_beat_time*0.2), _nclamp(coloring_style - 3));
    
    
    vec3 mainElementPaletteGradient = getColor(gradientVal, 8., false);
    vec3 mainElementSelectedGradient = mix(elements_color1, elements_color2, gradientVal);
    vec3 mainElementsColor = mix(mainElementSelectedGradient, mainElementPaletteGradient + 0.06, elements_use_scheme);

    vec3 feedbackPassColored = getColor(smoothstep(-0.05, 0.95, mergedElements), 0., true);
    vec3 colorizedMedia = getColor(_luminance(media) , 6., true);
    media.rgb = mix(colorizedMedia, media.rgb, use_media_col);

    fragColor.rgb = feedbackPassColored;
    
    fragColor.rgb = mix(fragColor.rgb, (fragColor.rgb*0.5 + mainElementsColor)*layerComposite.x, smoothstep(0.0, 0.2, layerComposite.x));
    fragColor.rgb = _nclamp(fragColor.rgb + media.rgb*media_mix);
    
    vec2 lightPos = abs(_rotate(_uvc - vec2(sin(syn_BassTime*0.1)*1.5, cos(syn_HighTime*0.15)), 0.33 + syn_Time*0.08)*1.1)*0.11;

    vec3 sp = vec3(_uvc, 0);
    mergedElements = sum(fragColor.rgb);
    
	vec3 light = vec3(sin(syn_BassTime*0.2 + mergedElements)*0.5, cos(syn_Time*0.15 - mergedElements*1.5), -1)*0.6;

    vec3 ld = light - sp;
    float lDist = max(length(ld), 0.01);
    ld /= lDist;
    float atten = min(1.0/(0.1 + lDist*0.75 + lDist*lDist*0.15) - 0.65, 1.);
    
    vec3 lightingCol = pow2(fragColor.rgb - 0.23*length(_uvc*0.33 - lightPos)) - mmin(lightPos) + fragColor.rgb*atten;

    fragColor = mix(fragColor,fragColor*max(atten, 0.22), lighting*0.8);
            
    fragColor.rgb = mix(fragColor.rgb, lightingCol*atten*0.99, lighting*0.8);
    
    fragColor.rgb = mix(fragColor.rgb, fragColor.rgb*0.7 + normalize(fragColor.rgb - ld*2.  - 1.5)*0.3, neon_lighting*0.85);


    float circuitsGrid = getCircuitsGrid();
    circuitsGrid *= mmax(_pulse(mmax(abs(_uvc)) - 0.1, 1.0 - circuits, 0.07), _pulse(mmax(abs(_rotate(_uvc, 0.33))) - 0.1, fract((1.0 - circuits) - 0.5), 0.06), _pulse(mmax(abs(_rotate(_uvc, 0.66))) - 0.1, fract((1.0 - circuits) - 0.25), 0.05));
    fragColor.rgb = mix(fragColor.rgb, _nclamp(fragColor.rgb * 0.05 + fragColor.rgb * _nclamp(circuitsGrid)*2. ), smoothstep(0., 0.4, circuits));

    return fragColor;

}

vec4 renderMain(void) {
    if (PASSINDEX == 0) {
        return renderGridPass();
    } else if (PASSINDEX == 1) {
    	return renderWidgetsPass();
    } else if (PASSINDEX  == 2) {
        return renderSecondaryWidgetsPass();
    } else if (PASSINDEX == 3) {
        return renderFirstFeedbackPass();
    } else if (PASSINDEX == 4) {
        return renderFinalPass();
    }
}
