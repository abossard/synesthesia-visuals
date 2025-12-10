////FX
#define DRAW_EDGES (edge_detect>0.5)


float SS(in float a, in float b,in float c) {return smoothstep(a-b,a+b,c); }
#define R RENDERSIZE.xy
#define PI 3.14529
#define TT (scriptTime + TIME*0.05 + syn_BeatTime*beat_jump*0.25)

float dot2(in vec2 v ) { return dot(v,v); }

float nsin(in float a) { return sin(a)*0.5+0.5; }

mat2 Rot(in float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(c, s, -s, c);
}

float pulse(in float a, in float c, in float w) {
    return SS(c,w/2.,a) * SS(c,-w/2.,a);
}

float triwave(in float a) {
    return (2.0 / PI) * asin(sin(2.0 * PI * a)) + 0.5;
}

// iq 2d sdfs
float sdCross( in vec2 p, in vec2 b, float r ) 
{
    p = abs(p); p = (p.y>p.x) ? p.yx : p.xy;
    vec2  q = p - b;
    float k = max(q.y,q.x);
    vec2  w = (k>0.0) ? q : vec2(b.y-p.x,-k);
    return sign(k)*length(max(w,0.0)) + r;
}
float sdHeart( in vec2 p ) {
    p.x = abs(p.x);

    if( p.y+p.x>1.0 )
        return sqrt(dot2(p-vec2(0.25,0.75))) - sqrt(2.0)/4.0;
    return sqrt(min(dot2(p-vec2(0.00,1.00)),
                    dot2(p-0.5*max(p.x+p.y,0.0)))) * sign(p.x-p.y);
}
float sdRoundedBox( in vec2 p, in vec2 b, in vec4 r )
{
    r.xy = (p.x>0.0)?r.xy : r.zw;
    r.x  = (p.y>0.0)?r.x  : r.y;
    vec2 q = abs(p)-b+r.x;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r.x;
}
float sdBox( in vec2 p, in vec2 b )
{
    vec2 d = abs(p)-b;
    return length(max(d,0.0)) + min(max(d.x,d.y),0.0);
}
float sdStar5(in vec2 p, in float r, in float rf)
{
    const vec2 k1 = vec2(0.809016994375, -0.587785252292);
    const vec2 k2 = vec2(-k1.x,k1.y);
    p.x = abs(p.x);
    p -= 2.0*max(dot(k1,p),0.0)*k1;
    p -= 2.0*max(dot(k2,p),0.0)*k2;
    p.x = abs(p.x);
    p.y -= r;
    vec2 ba = rf*vec2(-k1.y,k1.x) - vec2(0,1);
    float h = clamp( dot(p,ba)/dot(ba,ba), 0.0, r );
    return length(p-ba*h) * sign(p.y*ba.x-p.x*ba.y);
}
float sdHexagon( in vec2 p, in float r )
{
    const vec3 k = vec3(-0.866025404,0.5,0.577350269);
    p = abs(p);
    p -= 2.0*min(dot(k.xy,p),0.0)*k.xy;
    p -= vec2(clamp(p.x, -k.z*r, k.z*r), r);
    return length(p)*sign(p.y);
}
float mix3(float val1, float val2, float val3, float mixVal){
    mixVal *= 2.0;
    float mix1 = clamp(mixVal,0.0,1.0);
    float mix2 = clamp(mixVal-1.0, 0.0, 1.0);
    return mix(mix(val1, val2, mix1), mix(val2, val3, mix2), step(1.0, mixVal));
}
vec3 _grad3(vec3 col1, vec3 col2, vec3 col3, float mixVal){
    mixVal *= 2.0;
    float mix1 = clamp(mixVal,0.0,1.0);
    mix1 = smoothstep(0.4,0.6,mix1);
    float mix2 = clamp(mixVal-1.0, 0.0, 1.0);
    mix2 = smoothstep(0.4,0.6,mix2);
    return mix(mix(col1, col2, mix1), mix(col2, col3, mix2), step(1.0, mixVal));
}
// MAIN

////GLOBAL CONTROLS//////
vec2 GRID_SIZE = vec2(grid_size*grid_size*2.0);

////DICTS://////////////
////GRIDS:
#define GRID_FILL_FADE         0
#define GRID_FILL_UP           1
#define GRID_EXPANDING_CIRCLE  2
#define GRID_FADING_STRIPES    4
#define GRID_ROTATING_SQUARE   5
#define GRID_ROTATING_X        7
#define GRID_DIAGONAL_LINES    8
#define GRID_SPINNING_HEART    9
#define GRID_PULSATING_CROSS   10
#define GRID_PULSATING_BOX     3
#define GRID_STARBURST         11
#define GRID_RIPPLES           12
#define GRID_CHECKER_WAVE      13
#define GRID_RADIAL_GRADIENT   14
#define GRID_HEART_WAVE        15
#define GRID_CIRCLE_PULSES      16
#define GRID_SOFT_BULB    17
#define GRID_INTERLOCKING_DIAMOND 18
#define GRID_MEDIA            19
// define above         increment number below!
#define GRID_MODE_MAX          19
#define GRID_MODE_PICKED int(grid_mode+.01)

/////PULSES:
#define PULSE_LOG_SPIRAL       0
#define PULSE_WIPE_UP          1
#define PULSE_WIPE_CIRCLE      2
#define PULSE_EXPANDING_WAVES  3
#define PULSE_ZIGZAG           4
#define PULSE_RADIAL_WAVES     5
#define PULSE_SPIRAL_FAN       6
#define PULSE_SIMPLE_BPM_OSC   10
#define PULSE_SPINNING_STAR    11
#define PULSE_RADIAL_FLOW      12
#define PULSE_SWIRLING_ROUND   13
#define PULSE_GLOWING_HEX      14
#define PULSE_EXPANDING_HEART  16
#define PULSE_DIAGONAL_WAVES   18
#define PULSE_TWISTING_LAYERS  19
#define PULSE_FADE_UP          20
#define PULSE_MEDIA            21
// define above        increment number below!
#define PULSE_MODE_MAX         21
#define PULSE_MODE_PICKED int(pulse_mode+.01)

////MODES:
#define META_MODE_ALL          0
#define META_MODE_SHOW_PULSES  1
#define META_MODE_SHOW_GRIDS   2
#define META_MODE_PICKED       3
#define META_MODE_DEBUG_GRID   4
#define META_MODE_DEBUG_PULSE  5
int get_meta_mode() {
    int META_MODE = META_MODE_PICKED;
    // if (debug_grid>0.5) META_MODE = META_MODE_DEBUG_GRID;
    // if (debug_pulse>0.5) META_MODE = META_MODE_DEBUG_PULSE;
    return META_MODE;
}
/////////////////////////

// robobo1221 bloom
vec3 makeBloom(sampler2D samp, float lod, vec2 offset, vec2 bCoord){
    
    vec2 pixelSize = 1.0 / RENDERSIZE;

    offset += pixelSize;

    float lodFactor = exp2(lod);

    vec3 bloom = vec3(0.0);
    vec2 scale = lodFactor * pixelSize;

    vec2 coord = (bCoord.xy-offset)*lodFactor;
    float totalWeight = 0.0;

    if (any(greaterThanEqual(abs(coord - 0.5), scale + 0.5)))
        return vec3(0.0);

    for (int i = -5; i < 5; i++) {
        for (int j = -5; j < 5; j++) {

            float wg = pow(1.0-length(vec2(i,j)) * 0.125,6.0);

            bloom = pow(texture(samp,vec2(i,j) * scale + lodFactor * pixelSize + coord, lod).rgb,vec3(2.2))*wg + bloom;
            totalWeight += wg;

        }
    }

    bloom /= totalWeight;

    return bloom;
}

vec4 bloomPass(sampler2D samp) {
    vec3 blur = makeBloom(samp, 2.,vec2(0.0,0.0), _uv);
        blur += makeBloom(samp, 3.,vec2(0.3,0.0), _uv);
        blur += makeBloom(samp, 4.,vec2(0.0,0.3), _uv);
        blur += makeBloom(samp, 5.,vec2(0.1,0.3), _uv);
        blur += makeBloom(samp, 6.,vec2(0.2,0.3), _uv);

    return vec4(pow(blur, vec3(1.0 / 2.2)),1.0);
}


#define colorRange 1.3

vec3 jodieReinhardTonemap(vec3 c){
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    vec3 tc = c / (c + 1.0);

    return mix(c / (l + 1.0), tc, tc);
}

vec3 bloomTile(sampler2D samp, float lod, vec2 offset, vec2 uv){
    return texture(samp, uv * exp2(-lod) + offset).rgb;
}

vec3 getBloom(sampler2D samp, vec2 uv){

    vec3 blur = vec3(0.0);

    blur = pow(bloomTile(samp, 2., vec2(0.0,0.0), uv),vec3(2.2))              + blur;
    blur = pow(bloomTile(samp, 3., vec2(0.3,0.0), uv),vec3(2.2)) * 1.3        + blur;
    blur = pow(bloomTile(samp, 4., vec2(0.0,0.3), uv),vec3(2.2)) * 1.6        + blur;
    blur = pow(bloomTile(samp, 5., vec2(0.1,0.3), uv),vec3(2.2)) * 1.9        + blur;
    blur = pow(bloomTile(samp, 6., vec2(0.2,0.3), uv),vec3(2.2)) * 2.2        + blur;

    return blur * colorRange;
}

// drawPulses accepts a cell coordinate, mode, and 2 optional extra parameters ranging 0-1
// a is generally an 'complexity' parameter, b is generally an 'amount' parameter
float drawPulses(vec2 cell, int mode, float aIn, float bIn) {
    float o = 0.;
    // float a = mix(aIn, 1.0-aIn, more_reactivity*syn_HighHits);
    float a = aIn;
    float b = mix(bIn, 1.0-bIn, more_reactivity*pow(syn_BassLevel,2.0));
    // cell += pow(syn_BassLevel,2.0)*0.03*vec2(_statelessContinuousChaotic(syn_BassTime*0.01),_statelessContinuousChaotic(syn_BassTime*0.013279));
    float media_brightness = _luminance(_textureMedia(cell*vec2(RENDERSIZE.y/RENDERSIZE.x,1.0)+0.5,media_blur).rgb);
    cell+=vec2(0.0,(media_brightness)*media_pulse_offset*media_pulse_offset*2.0);
    if (mode==PULSE_MEDIA) {
        float media_pulse = _nsin(TT+a*30.*media_brightness)*(1.-b);
        o = SS(1.-b,a,media_pulse);
        // o = media_pulse;
    }
    if (mode==PULSE_WIPE_UP) {
        o += SS(triwave(TT*.25 - abs(cell.x*.05))*.8+.25,b,cell.y+.5);
    }
    if (mode==PULSE_WIPE_CIRCLE) {
        o += SS(triwave(TT*.25)*.8+.1,b,length(cell));
    }
    if (mode==PULSE_EXPANDING_WAVES) {
        float dist = length(cell);
        float wave = triwave(-TT + dist * mix(5., 15.,b));
        o = wave * a * 0.5;
    }
    if (mode==PULSE_ZIGZAG) {
        // float pos = cell.x + cell.y;
        // float zigzag = abs(sin(pos * 15.0 - TT * 5.0));
        vec2 gv = fract(cell.xy*mix(1.0, 10.0, b));
        gv.x = gv.x * 2.0 - 1.0;
        gv.x = abs(gv.x);

        // Distort uv.y
        gv.y += gv.x * 0.4;
        gv.y -= 0.1;
        float zigzag = fract(gv.x-gv.y+TT*0.3);
        o = smoothstep(0.0, 1.0, zigzag) * a;
    }
    if (mode==PULSE_RADIAL_WAVES) {
        float dist = length(cell)*(5.0-b*8.0+b*b*20.0) + TT;
        o = fract(clamp(sin(dist),-0.999,0.999) * 0.5 + 0.5) * a;
    }
    if (mode==PULSE_SPIRAL_FAN) {
        float angle = atan(cell.y, cell.x);
        float spiral = sin(int(mix(1.0,25.0,b)) * angle - TT * 4.0+length(cell)*10.0) * 0.5 + 0.5;
        // o = SS(spiral+0.5, 1.0, mix(0.0,1.5,a));
        o = _nclamp(SS(0.5, a, spiral)*1.3-0.3);

    }
    if (mode==PULSE_SIMPLE_BPM_OSC) {
        float heartbeat = syn_BPMSin4/(syn_BPMConfidence+0.001);
        o = heartbeat;
        // o = SS(0.5, a, heartbeat);
    }
    if (mode==PULSE_SPINNING_STAR) {
        float angle = atan(cell.y, cell.x) + TT;
        float star = cos(angle * 6.0) * 0.5 + 0.5;
        o = star * a;
    }
    if (mode==PULSE_GLOWING_HEX) {
        float hexPattern = sdHexagon(cell*mix(1.0,10.0,b), 1.0*mix(1.0,10.0,b));
        o = sin(hexPattern * mix(1.0,7.0,a)*10.0 - TT*3.0);
    }
    if (mode==PULSE_EXPANDING_HEART) {
        float dist = sdHeart(cell*vec2(1.5,1.2)*1.2+vec2(0.0,0.6));
        o = SS(0.0+a*0.6, 0.4+b, nsin(dist*8*PI-TT*3.0));
        float dist2 = sdHeart(cell*vec2(1.5,1.2)*mix(1.9,2.3,nsin(TT*6.0))+vec2(0.0,0.6));
        o += SS(0.0+a*0.6, 0.4+b, -6.0*dist2);
        o = _nclamp(o);

        // o *= mix(1.0, 0.0, 1.0/(length(abs(cell)*0.5+abs(dist*0.005))*15.0));

        // o = SS(-a, a, dist) * abs(sin(TT * 5.0));
    }
    if (mode==PULSE_DIAGONAL_WAVES) {
        float dist = _pulse(0.0,mix(0.4,0.04,b*b),abs(sin((cell.x + cell.y - TT) * PI)));
        o = _nclamp(mix(dist, 1.0-dist*2.0, a));
        // o = 1.0-dist*1.0;
    }
    if (mode==PULSE_TWISTING_LAYERS) {
        float angle = atan(cell.y, cell.x) + TT;
        float layers = sin(angle * 4.0) * 0.5 + 0.5;
        o = layers * a;
    }
    if (mode==PULSE_FADE_UP) {
        o = _nsin(TT + cell.y);
    }
    return _nclamp(o)+pulse_boost_cut;
}

// drawGrid accepts an amt 0-1, a gxy 0-1 coord system, and an int mode
// each mode uses the amt and gxy to fill a grid cell
// optional extra 0-1 grid param "a" maps to complexity
// optional extra 0-1 grid param "b" maps to fill amount
float drawGrid(float amt, vec2 gxy, int mode, float aIn, float b) {
    float o = 0.;
    float a = mix(aIn, 1.0-aIn, more_reactivity*syn_HighHits);
    vec2 gpxl = GRID_SIZE/R;
    // if (gpxl.y<0.01){
    //     if (_uv.y>0.5){
    //         gxy.y = 1.0-gxy.y;
    //         gxy.x = 1.0-gxy.x;
    //     }
    //     // gpxl.y = 0.01;
    //     // gxy.y = abs(1.0-gxy.y);
    // }
    vec2 pxl = 1./R;
    if (mode==GRID_MEDIA) {
        //HAVE TO FIX MEDIA LOADING HERE, THE GRID IS WRONG. MAYBE USE _loadMedia instead and manually blur? Or blur in earlier passes?
        vec2 uvM = gxy*vec2(1.0,RENDERSIZE.x/RENDERSIZE.y);
        vec3 media_blurred = _textureMedia(uvM,4.5).rgb;
        media_blurred += _textureMedia(uvM,2.5).rgb;
        media_blurred += _textureMedia(uvM,.5).rgb;
        media_blurred /= 3.;
        if ((uvM.x>=1.0)||(uvM.y>=1.0)||(uvM.x<0.0)||(uvM.y<0.0)){
            media_blurred=vec3(0.0);
        }
        // smoothstep(a-b,a+b,c)
        if (!_isMediaActive()){
            media_blurred = vec3(-0.01);
        }
        o = SS(amt, gpxl.y, _luminance(media_blurred)-0.01); // Modified to incorporate amt
    }
    if (mode==GRID_FILL_FADE) {
        o = mix(amt, 1.0-amt, step(a, 0.5));
    }
    if (mode==GRID_FILL_UP) {
        o = mix(float(gxy.y < amt),float(gxy.y > amt),a);
    }
    if (mode == GRID_EXPANDING_CIRCLE) {
        float dist = length(gxy-.5);
        o = 1.-SS(gpxl.y, gpxl.y, dist - amt*.5  + 1.0 - (b*0.8+0.6));
        o = mix(o, 1.0-o, a);
        // o = _nclamp(o);
    }
    // if (mode == GRID_SHRINKING_CIRCLE) {
    //     float dist = length(gxy-.5);
    //     o = SS(((1.0+b) - amt) - gpxl.y, gpxl.y, dist);
    // }
    if (mode == GRID_FADING_STRIPES) {
        float stripes = PI-PI*SS(amt*(b+0.01)-gpxl.y, gpxl.y, nsin((gxy.x + amt/PI/2.) * PI * (8. + 16. * a)));
        o = stripes * amt;
    }
    if (mode == GRID_ROTATING_SQUARE) {
        vec2 rotated = gxy - .5;
        rotated *= Rot(amt * b * 4.0 * PI / 2.);
        rotated *= 2.;
        float sq = sdBox(rotated, vec2(mix(amt,1.0-amt, a)));
        o = 1.-SS(-gpxl.y, gpxl.y, sq);
    }    
    if (mode == GRID_DIAGONAL_LINES) {
        float diagonal_grad = _nsin((gxy.x + gxy.y) * PI * (1. + 4. * b));
        o = 1.-SS(amt*(1.005-a)-pxl.y, pxl.y, diagonal_grad);
    }
    if (mode == GRID_ROTATING_X) {
        // b /= 2.; // mapping to 0 - 0.5
        // vec2 rotated = gxy - .5;
        // rotated *= Rot(amt * PI * 2 * a);
        // // rotated /= (1.0 - amt);
        // float square_field = SS(b, 0.1, abs(rotated.x)) + SS(b, 0.1, abs(rotated.y));
        // o = 1. - SS(amt, 0.1, square_field);
//
        vec2 rotated = gxy - .5;
        rotated *= Rot(amt * 2.0 * PI / 2.);
        float sq = sdCross(rotated, vec2(mix3(0.4,0.1,1.0,a), b*b*0.3+0.01), 0.0);
        o = 1.-SS(-gpxl.y, gpxl.y, sq);
    }
    if (mode == GRID_SPINNING_HEART) {
        vec2 rotated = gxy-vec2(.5);
        rotated *= Rot(TT * PI + a*PI*2)*.5;
        rotated /= .001+b*amt*0.7;
        rotated.y += .5;
        float heart = sdHeart(rotated);
        o = 1.-SS(-gpxl.y, gpxl.y, heart);
    }
    if (mode == GRID_PULSATING_CROSS) {
        // if (a>0.001){
        //     gxy.xy = sign(gxy.xy)*fract(gxy.xy*a*6.0 - 0.5*a*6.0);
        // }
        bool N = abs(gxy.x-.5)<=gxy.y-.5;
        bool S = abs(gxy.x-.5)<=1.-gxy.y-.5;
        bool E = abs(gxy.y-.5)<=gxy.x-.5;
        bool W = abs(gxy.y-.5)<=1.-gxy.x-.5;
        if (N) o = abs(gxy.x-.5)*2.;
        if (S) o = abs(1.-gxy.x-.5)*2.;
        if (E) o = abs(gxy.y-.5)*2.;
        if (W) o = abs(1.-gxy.y-.5)*2.;
        o = SS(o-gpxl.y,gpxl.y,amt*b);
    }
    if (mode == GRID_PULSATING_BOX) {
        float aPlus = mix(-1.5,1.0,a)*1.0+0.5;
        gxy.xy = sign(gxy.xy)*fract(gxy.xy*aPlus*6.0 - 0.5*aPlus*6.0);
        bool N = abs(gxy.x-.5)<=gxy.y-.5;
        bool S = abs(gxy.x-.5)<=1.-gxy.y-.5;
        bool E = abs(gxy.y-.5)<=gxy.x-.5;
        bool W = abs(gxy.y-.5)<=1.-gxy.x-.5;
        if (N) o = abs(gxy.x-.5)*2.;
        if (S) o = abs(1.-gxy.x-.5)*2.;
        if (E) o = abs(gxy.y-.5)*2.;
        if (W) o = abs(1.-gxy.y-.5)*2.;
        o = SS(o-gpxl.y,gpxl.y,amt*b);
    }
    if (mode == GRID_STARBURST) { // weird
        // o = SS(cos((atan(gxy.y - .5, gxy.x - .5) + PI/2.) * floor(a*8.0)), gpxl.x, amt*mix(1.0,5.0,b));
        float amtIn = amt*0.9-0.5;
        o = pow(-0.3+1.5*SS(cos((atan(gxy.y - .5, gxy.x - .5) - amtIn*PI/2.) * 10.0), SS(length(gxy)*0.1, 0.1, 0.5-amtIn), amtIn*mix(1.0,5.0,b))-0.1,3.0);
        // o = _nclamp(o);
    }
    if (mode == GRID_RIPPLES) {
        float d = length(gxy - .5);
        o = _nsin(d * 20. - TT * 6.);
        o = SS(o-gpxl.y,gpxl.y,b*amt);
    }
    if (mode == GRID_CHECKER_WAVE) {
        o = SS((cos(gxy.x * PI * 2. + PI * amt) * sin(gxy.y * PI * 2. + mix(1.0,5,a)*PI * amt) + amt) / 2., gpxl.y, -0.1-b+b*b*b*1.8);
    }
    if (mode == GRID_HEART_WAVE) {
        float d = length(gxy - .5);
        float aPlus = mix(0.5, 0.2, a);
        float hDist = sdHeart((gxy - vec2(0.5,mix(0.3, 0.08, a))) * 4.*aPlus);
        o = sin(d * 0. - TT * 6. + 5*hDist * PI) * amt;
        o = max(o, _pulse(hDist, 0.0, 0.1)) * amt;
    }
    if (mode == GRID_CIRCLE_PULSES) {
        o = cos(length(gxy - .5) * mix(0., 100., b*b)*mix(1.0, 5.0, a) - TT * 10.) * amt;
    }
    if (mode == GRID_SOFT_BULB) {
        vec2 remap = vec2(gxy.x * amt, gxy.y * amt) / 1.5;
        vec2 cDist = length(gxy - .5) * normalize(remap * amt);
        o = _nclamp(SS(length(cDist)*1.5, a+b-pxl.y, mix(0.2,-0.5, amt))*2.0);
    }
        // everything above is checked
    // o = mix(o, abs(dFdx(o))+abs(dFdy(o)), edge_grid);
    return o;
}

vec4 mainImage( in vec2 coord ) {
    vec4 color = vec4(0.);
    // 0-1 coords
    vec2 uv = coord/R;
    // aspect corrected and centered coords
    vec2 fix = vec2(0.0);
    if (min(GRID_SIZE.x,GRID_SIZE.y)<0.01){
        fix = R;
    }
    vec2 uvc = (coord - R/2.+fix)/R.y; 
    
    // grid id
    vec2 grid_uvc = uvc*GRID_SIZE;
    vec2 cell = vec2(
        floor(grid_uvc.x)/GRID_SIZE.x,
        floor(grid_uvc.y)/GRID_SIZE.y
    );
    // grid subuv
    vec2 gxy = vec2(
        fract(grid_uvc.x),
        fract(grid_uvc.y)
    );
    // color vars
    vec3 col = vec3(0.);    
    float bw = 0.;

    // DISPLAY MODE OPTIONS FOR PERFORMANCE & DEBUGGING
    int META_MODE = get_meta_mode();
    if (no_grid>0.5){
        META_MODE = META_MODE_DEBUG_PULSE;
        gxy = _uvc+0.5;
        cell = vec2(0,0);
    }
    if (META_MODE==META_MODE_ALL) {
        int PULSE_MODE = int(mod(TT*.5,float(PULSE_MODE_MAX+1)));
        float amt = drawPulses(cell, PULSE_MODE, 1., .1);

        int GRID_MODE = int(mod(TT*.3,float(GRID_MODE_MAX+1)));
        bw += drawGrid(amt, gxy, GRID_MODE, 0.5, 0.6);
    }
    if (META_MODE==META_MODE_SHOW_PULSES) {
        int PULSE_MODE = int(mod(TT*.5,float(PULSE_MODE_MAX+1)));
        float amt = drawPulses(uvc, PULSE_MODE, 1., .1);
        bw = amt;
    }
    if (META_MODE==META_MODE_SHOW_GRIDS) {
        float amt = drawPulses(cell, PULSE_FADE_UP, 1., .1);
        int GRID_MODE = int(mod(TT*.3,float(GRID_MODE_MAX+1)));
        bw = drawGrid(amt, gxy, GRID_MODE, cell.y, cell.x);
    }
    if (META_MODE==META_MODE_PICKED) {
        float amt = drawPulses(cell, PULSE_MODE_PICKED, pulse_param_a, pulse_param_b);
        bw = drawGrid(amt, gxy, GRID_MODE_PICKED, grid_param_a, grid_param_b);
    }
    if (META_MODE==META_MODE_DEBUG_GRID) {
        float amt = _nsin(TIME*2*PI);
        bw = drawGrid(amt, _uvc+0.5, GRID_MODE_PICKED, grid_param_a, grid_param_b);
    }
    if (META_MODE==META_MODE_DEBUG_PULSE) {
        float amt = drawPulses(_uvc, PULSE_MODE_PICKED, pulse_param_a, pulse_param_b);
        bw = amt;
    }
    // output
    bw = mix(bw, 1.0-bw, invert_grid);
    col = vec3(bw);
    col = mix(col, texture(fbFix, _uv+vec2(0.0,feedback_rise_fall*feedback_rise_fall*feedback_rise_fall)*0.0075+_uvc*feedback_zoom*feedback_zoom*feedback_zoom*0.0075).rgb, pow(feedback*0.999,1.75));
    col = _nclamp(col*(mix(1.00, 1.3, feedback_gain*feedback_gain)));
    color = vec4(col,1.0);
    return color;
}


////FX
float getBuffA(in vec2 uv, in int offX, in int offY, in float mip) {
    vec2 buv = uv + vec2(offX, offY) / R;
    return texture(gen, buv, mip).r;
}

#define GBxym(o,m) getBuffA(uv,x,y,m)
#define GBm(m) getBuffA(uv,0,0,m)
#define GBxy(x,y) getBuffA(uv,x,y,0.)
#define GB getBuffA(uv,0,0,0.)
#define GBmOffset(m) getBuffA(uv,0,0,m)

vec4 compositePass( in vec2 coord ) {
    vec4 color = vec4(0.,0.,0.,1.);
    float bw = 0.;
    // 0-1 coords
    vec2 uv = coord/R;
    // aspect corrected and centered coords
    vec2 uvc = (coord - R/2.)/R.y;
    
    float buffA0 = GB;
    float buffAZoom = getBuffA(uv/2.0+0.25,0,0,0.0);
    // float buffAZoom2 = getBuffA(uv*2.0,0,0,0.0);

    float blurA = 0.0;
    float blurAZoom = 0.0;
    float maxMip = 5;
    for (int i = 0; i<maxMip; i++){
        blurA += GBm(float(i));
        blurAZoom += getBuffA(uv/2.0+0.25, 0, 0, float(i));
    }
    blurA *= 1/(maxMip);
    float buffA1 = GBm(1.);
    // float buffA2 = GBm(2.);
    // float buffA3 = GBm(3.);

    // vec4 buffA2 = texture(iChannel0, uv, 2.);
    
    bw = buffA0;
    // bw = mix(bw, bw*0.5+buffAZoom*0.5, layer_small);
    // bw = mix(bw, bw*0.5+buffAZoom2*0.5, layer_big);

    // bw += buffAZoom2*layer_big;
    if (DRAW_EDGES) {
        // mipmap difference method
        float mipdiff = abs(buffA0 - buffA1);
        // fwidth method
        // float dfXY = fwidth(buffA0); // trash
        // sobel method
        mat3 sobelX = mat3(-1.0, -2.0, -1.0,
                           0.0,  0.0, 0.0,
                           1.0,  2.0,  1.0);
        mat3 sobelY = mat3(-1.0,  0.0,  1.0,
                           -2.0,  0.0, 2.0,
                           -1.0,  0.0,  1.0);  

        float sumX = 0.0;	// x-axis change
        float sumY = 0.0;	// y-axis change

        for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            sumX += GBxy(i,j) * sobelX[1+i][1+j];
            sumY += GBxy(i,j) * sobelY[1+i][1+j];
        }}

        float sobel = abs(sumX) + abs(sumY);
        
        float sum_diff = mix(mipdiff, sobel, 0.5);
        
        color = vec4(sum_diff);
        bw = sum_diff;
        bw = mix(bw, 1.0-bw, invert_grid);

    } else {
        color.rgb = vec3(bw);
    }
    // return vec4(blurA);
    // bw = mix(bw, 1.0-bw, invert_grid);
    // blurA = mix(blurA, 1.0-blurA, invert_grid);
    bw += buffAZoom*grid_2x_stack;
    blurA += blurAZoom*grid_2x_stack;
    // bw = _nclamp(bw);
    // blurA = _nclamp(blurA);
    vec4 rawPat = vec4(bw,bw,bw,1.0);

    // vec4 singleCol = vec4(colorize, 1.0); //Make into a uniform //COLORIZE COMMENTED OUT
    // vec4 colPat = rawPat*singleCol; //COLORIZE COMMENTED OUT
    // rawPat = mix(rawPat, colPat, colorize_on);
    // blurA = mix(blurA, blurA*singleCol, colorize_on);
    // if (_isMediaActive()) {
    //     if (mask_logo>0.5){
    //         color *= mix(vec4(1.), _loadMedia(media_offset), amount_mask);
    //     }
    //     // color += _edgeDetectSobel(gen);
    //     // color = mix(color, _edgeDetectSobelMedia()*.25, _nclamp(media_mult_after-bw));
    // }

    vec4 logoCol = _loadMedia();
    // logoCol *= mix(vec4(1.0), singleCol, colorize_on);
    vec4 logoEdge = _edgeDetectSobelMedia();
    // logoEdge *= mix(vec4(1.0), singleCol, colorize_on);
    vec4 logoDis = _loadMedia(vec2(displace_x*displace_x*displace_x, displace_y*displace_y*displace_y)*blurA*mix(0.05, 0.015, grid_2x_stack));
    vec4 logoDisNeg = _loadMedia(vec2(-displace_x*displace_x*displace_x, -displace_y*displace_y*displace_y)*blurA*mix(0.05, 0.015, grid_2x_stack));
    vec4 maskOfLogo = _loadMediaAsMask();
    logoDis = mix(logoDis, max(logoDis, logoDisNeg), displace_mirror);
    // logoDis *= mix(vec4(1.0), singleCol, colorize_on);
    // vec3 pattern_colFix = _grad3(pattern_col, pattern_col*logoCol.rgb, logoCol.rgb, use_media_colors);
    // vec3 displace_colFix = _grad3(displace_col, displace_col*logoCol.rgb, logoCol.rgb, use_media_colors);
    // vec3 logo_colFix = _grad3(logo_col, logo_col*logoCol.rgb, logoCol.rgb, use_media_colors);
    // vec3 mask_colFix = _grad3(mask_col, mask_col*logoCol.rgb, logoCol.rgb, use_media_colors);
    color = vec4(0.0,0.0,0.0,1.0);
    color += pattern*rawPat*vec4(pattern_col,1.0);
    color += raw_logo*logoCol*vec4(logo_col,1.0);
    color += displace_logo*logoDis*mix(1.0, pow(blurA*mix(1.0,0.5,grid_2x_stack),2.0)*4.0, show_displaced_only)*vec4(displace_col,1.0);
    color += mask_logo*maskOfLogo*(1.0-bw)*vec4(mask_col,1.0);
    // color *= 1.0+flasher*syn_HighHits;
    color += color*2.0*syn_OnBeat*flasher;
    float lum = _nclamp(dot(color.rgb, vec3(1.0))/3.0);
    float mask = _nclamp(pow(lum, 2.0)*3.0);
    // color = mix(color, singleCol*lum, colorize_on); //COLORIZE COMMENTED OUT
    color = mix(color, _nclamp(1.0-color), syn_BassHits*flasher_invert*mask);
    // color += max(debug_grid, debug_pulse)*buffA0;
    return color;
}   


// vec4 _mix3(vec4 col1, vec4 col2, vec4 col3, float mixVal){
//     mixVal *= 2.0;
//     vec4 mix1 = clamp(mixVal,0.0,1.0);
//     vec4 mix2 = clamp(mixVal-1.0, 0.0, 1.0);
//     return mix(mix(col1, col2, mix1), mix(col2, col3, mix2), step(1.0, mixVal));
// }

vec4 renderMain(void) {
    if (PASSINDEX==0.0) {
        return mainImage(_xy);
    }
    if (PASSINDEX==1.0) {
        return texture(gen, _uv);
    } 
    if (PASSINDEX==2.0) {
        return _nclamp(compositePass(_xy));
    } 
    if(PASSINDEX == 3.0){
        return bloomPass(composite);
    }
    if(PASSINDEX == 4.0){
        vec4 col = vec4(0.);
        vec4 bCol = vec4(getBloom(bloomed, _uv), 1.0);
        // bCol = pow(bCol, vec4(1.25));
        vec4 bassCol = pow(bCol, vec4(2.0));
        vec4 cCol = texture(composite, _uv);
        col = _mix3(cCol, cCol*0.8+bCol*0.2, cCol*0.4+bCol*0.5, bloom_mixer);
        col += bassCol*pow(syn_BassLevel, 2.0)*pow(bloom_bass,2.0);
        // float cReduce = mix(0.4, 1.0, mixer);
        // float bBoost = mix(0.3, 0.75, mixer);
        // col = cCol+bCol*0.5;
        // col = mix(texture(composite,_uv).rgb,col,pow(bloom_mix,9) + pow(bloom_bass * syn_BassLevel, bloom_bass * 7. + 2.));

        return col;
    }
}
