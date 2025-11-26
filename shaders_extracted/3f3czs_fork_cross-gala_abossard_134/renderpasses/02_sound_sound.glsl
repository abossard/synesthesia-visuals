#define PI 3.1415926535

// comment these define to remove the synth and/or wave sound
#define SYNTH
#define WAVE

// octave is an integer number, 0 is some octave, 1 is an octave higher, etc
// pitch is an integer between 0 and 7
// fractionnal and negative values are allowed
// returns a frequency in Hz
float tone(float octave, float pitch) {
    float baseFreq = 264.0;
    baseFreq *= pow(2.0, octave); // multiply the frequency by 2 for higher octave
    baseFreq *= pow(1.1041, pitch); // seventh root of 2
    return baseFreq;
}

// 1D version of IQ code, see https://www.shadertoy.com/view/lsf3WH
float hash( float p ){
	float h = p * 127.1;
    return fract(sin(h)*43758.5453123);
}
float perlinNoise( in float x ) {
    float lower = floor(x);
    float upper = lower + 1.0;
    float lowerV = hash(lower);
    float upperV = hash(upper);
    return smoothstep(lower, upper, x) * (upperV - lowerV) + lowerV;
}

// return a different white noise on both channels
// thanks Dave Hoskins! see https://www.shadertoy.com/view/4djSRW
#define ITERATIONS 8
#define MOD3 vec3(443.8975,397.2973, 491.1871)
vec2 hash22( in vec2 p ) {
	vec3 p3 = fract(vec3(p.xyx) * MOD3);
    p3 += dot(p3.zxy, p3.yxz+19.19);
    return fract(vec2(p3.x * p3.y, p3.z*p3.x));
}
vec2 noise( in float time ) {
	vec2 audio = vec2(0.0);
    for (int t = 0; t < ITERATIONS; t++) {
        float v = float(t)*3.21239;
		audio += hash22(vec2(time + v, time*1.423 + v)) * 2.0 - 1.0;
    }
    audio /= float(ITERATIONS);
    return audio;
}

// do a low pass on the white noise and get the wave sound
#define SAMPLES 41
vec2 getWaveSound( in float time ) {
    // snap to the nearest 1/iSampleRate
    float period = 1.0 / iSampleRate;
    time = floor(time/period)*period;
    float totAmpl = 0.0;
    vec2 audio = vec2(0);
    for (int i = 0 ; i < SAMPLES ; i++) {
        float index = float(i - SAMPLES/2);
        float currStepF = period * index;
        vec2 curr = noise(time + currStepF);
        index /= 2.0; index *= index;
        float ampl = 1.0 - index;
        totAmpl += ampl;
        audio += curr*ampl;
    }
    return audio/totAmpl;
}

// base synth sound
#define SYNTH_HARMONICS 3
float getSynthBase( in float time, in float freq, in float frac ) {
    float x = fract(time*freq);
    float value = 0.0;
    if ( x < 0.078) {
        value = 0.692 - smoothstep(0.0, 0.078, x) * 0.588;
    } else if ( x < 0.346 ) {
        value = smoothstep(0.078, 0.346, x) * 0.666 + 0.105; 
    } else if ( x < 0.986 ) {
        value = 0.771 - smoothstep(0.346, 0.986, x) * 0.351;
    } else {
        value = smoothstep(0.986, 1.0, x) * 0.272 + 0.420;
    }
    value *= 2.7;
    float totAmpl = 2.7;
    
    // add harmonics
    float mult = time*2.0*PI*freq;
    for (int i = 0 ; i < SYNTH_HARMONICS ; i++) {
        float fact = 1.0 / pow(2.0, float(i)); // = 1, = .5, =.25 etc
        float harm = sin(mult * fact);
        float ampl = (cos(frac*2.0*PI) * 3.0 + 4.0) * (1.0 - fact) + 3.0;
       	value += harm * ampl;
        totAmpl += ampl;
    }
    
    return value / totAmpl;
}

#define TEMPO 7.0

// partition
float getTone( in float time ) {
    float timei = floor((time+TEMPO) / TEMPO);
    return floor((sin(timei*3.95216) * 0.5 + 0.5) * 4.0);
}

// synth sound
#define PART_LENGTH 4.0
#define PART_COUNT 3.0
#define TOT_PART (PART_LENGTH*PART_COUNT)
vec2 getSynth( in float time ) {
    float part = mod(floor(time / TEMPO / PART_LENGTH), PART_COUNT);
    if (mod(time, TEMPO * TOT_PART) > TEMPO * 7.0) return vec2(0); // add some calm
    float currentTone = getTone(time);
    float frac = mod(time, TEMPO);
    float freq = tone(-2.0+part, currentTone);
	float ampl = smoothstep(0.0, 2.0, frac) * (1.0 - smoothstep(TEMPO-2.0, TEMPO, frac));
    float synthBase = ampl * getSynthBase(time, freq, mod(time, TEMPO)/TEMPO);
    frac = smoothstep(0.0, TEMPO, frac); // stereo panning
    if ( mod(floor(time / TEMPO), 2.0) < 1.0) frac = 1.0 - frac;
    return vec2((1.0-frac)*synthBase, 1.0*synthBase);
}

vec2 mainSound( in int samp,float time) {
    vec2 result = vec2(0);
    
    #ifdef SYNTH
    result += smoothstep(0.0, 2.0, time) * getSynth(time);
    #endif
    
    #ifdef WAVE
    float waveAmpl = sin(time * 0.353) * 0.12 + 0.24;
    float perlinAmpl = 1.0 - perlinNoise( time * 1.2146 ) * 0.5;
    result += smoothstep(0.0, 12.0, time) * getWaveSound(time) * waveAmpl * perlinAmpl;
    #endif
    
    return result;
}
