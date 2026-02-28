/*
{
    "CREDIT": "Magic Music Visuals",
    "DESCRIPTION": "Black and white strobe mask with multiple patterns synced to BPM with phrase\/fraction control",
    "ISFVSN": "2",
    "CATEGORIES": [
        "Generator",
        "Utility"
    ],
    "INPUTS": [
        {
            "NAME": "bpm",
            "TYPE": "float",
            "DEFAULT": 120,
            "MIN": 80,
            "MAX": 240,
            "LABEL": "BPM"
        },
        {
            "NAME": "phraseDiv",
            "TYPE": "long",
            "DEFAULT": 2,
            "MIN": 0,
            "MAX": 7,
            "LABELS": [
                "4 Bars",
                "2 Bars",
                "1 Bar",
                "1\/2 Beat",
                "1\/4 Beat",
                "1\/8 Beat",
                "1\/16 Beat",
                "1\/32 Beat"
            ],
            "LABEL": "Phrase Division"
        },
        {
            "NAME": "pattern",
            "TYPE": "long",
            "DEFAULT": 0,
            "MIN": 0,
            "MAX": 3,
            "LABELS": [
                "Full On\/Off",
                "Roller Top-Bottom",
                "Circle Inside-Out",
                "Random Scanlines"
            ],
            "LABEL": "Pattern"
        },
        {
            "NAME": "dutyCycle",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.01,
            "MAX": 1,
            "LABEL": "Duty Cycle"
        },
        {
            "NAME": "fadeOff",
            "TYPE": "float",
            "DEFAULT": 0,
            "MIN": 0,
            "MAX": 1,
            "LABEL": "Fade Off"
        },
        {
            "NAME": "scanlineCount",
            "TYPE": "float",
            "DEFAULT": 20,
            "MIN": 4,
            "MAX": 100,
            "LABEL": "Scanline Count"
        },
        {
            "NAME": "brightness",
            "TYPE": "float",
            "DEFAULT": 1,
            "MIN": 0,
            "MAX": 1,
            "LABEL": "Max Brightness"
        },
        {
            "NAME": "invert",
            "TYPE": "bool",
            "DEFAULT": false,
            "MIN": 0,
            "MAX": 1,
            "LABEL": "Invert"
        }
    ]
}
*/

#define PI 3.14159265359

float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

float hash2(float a, float b) {
    return fract(sin(a * 127.1 + b * 311.7) * 43758.5453123);
}

void main() {
    vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
    
        vec2 uvAspect = (gl_FragCoord.xy - 0.5 * RENDERSIZE.xy) / min(RENDERSIZE.x, RENDERSIZE.y);
    
        float beatsPerSec = bpm / 60.0;
    
    float multiplier;
    if (phraseDiv == 0) {
        multiplier = 1.0 / 16.0;         } else if (phraseDiv == 1) {
        multiplier = 1.0 / 8.0;          } else if (phraseDiv == 2) {
        multiplier = 1.0 / 4.0;          } else if (phraseDiv == 3) {
        multiplier = 1.0 / 2.0;          } else if (phraseDiv == 4) {
        multiplier = 1.0;                 } else if (phraseDiv == 5) {
        multiplier = 2.0;                 } else if (phraseDiv == 6) {
        multiplier = 4.0;                 } else {
        multiplier = 8.0;                 }
    
    float freq = beatsPerSec * multiplier;
    
        float phase = fract(TIME * freq);
    
        float beatIndex = floor(TIME * freq);
    
    float val = 0.0;
    
        if (pattern == 0) {
                if (fadeOff < 0.01) {
                        val = phase < dutyCycle ? 1.0 : 0.0;
        } else {
            if (phase < dutyCycle) {
                val = 1.0;
            } else {
                                float fadePhase = (phase - dutyCycle) / (1.0 - dutyCycle);
                float fadeDuration = fadeOff;                 if (fadeDuration > 0.001) {
                    val = 1.0 - clamp(fadePhase / fadeDuration, 0.0, 1.0);
                } else {
                    val = 0.0;
                }
            }
        }
    }
    
        else if (pattern == 1) {
                        float bandCenter = 1.0 - phase;         float bandHalf = dutyCycle * 0.5;
        float dist = abs(uv.y - bandCenter);
        
        if (fadeOff < 0.01) {
            val = dist < bandHalf ? 1.0 : 0.0;
        } else {
            float edge = fadeOff * 0.5;
            val = 1.0 - smoothstep(bandHalf - edge * bandHalf, bandHalf + edge * bandHalf, dist);
        }
    }
    
        else if (pattern == 2) {
                float radius = length(uvAspect);
        float maxRadius = 0.75;         
                float circleRadius = phase * maxRadius;
        float bandWidth = dutyCycle * maxRadius;
        
        float dist = abs(radius - circleRadius);
        
        if (fadeOff < 0.01) {
            val = dist < bandWidth * 0.5 ? 1.0 : 0.0;
                        if (radius < circleRadius && phase < dutyCycle) {
                val = 1.0;
            }
        } else {
            float edge = fadeOff * bandWidth * 0.5;
            val = 1.0 - smoothstep(bandWidth * 0.5 - edge, bandWidth * 0.5 + edge, dist);
            if (radius < circleRadius && phase < dutyCycle) {
                float fillFade = 1.0 - smoothstep(0.0, edge, circleRadius - radius - bandWidth * 0.5);
                val = max(val, 1.0 - fillFade * (1.0 - val));
            }
        }
        
                if (phase > dutyCycle) {
            float fadePhase = (phase - dutyCycle) / (1.0 - dutyCycle);
            if (fadeOff > 0.01) {
                val *= 1.0 - clamp(fadePhase / fadeOff, 0.0, 1.0);
            } else {
                val = 0.0;
            }
        }
    }
    
        else if (pattern == 3) {
                float lineIndex = floor(uv.y * scanlineCount);
        float totalLines = scanlineCount;
        
                float rnd = hash2(lineIndex, beatIndex);
        
                        float lineOn = rnd < dutyCycle ? 1.0 : 0.0;
        
                float strobeOn;
        if (fadeOff < 0.01) {
            strobeOn = phase < dutyCycle ? 1.0 : 0.0;
        } else {
            if (phase < dutyCycle) {
                strobeOn = 1.0;
            } else {
                float fadePhase = (phase - dutyCycle) / (1.0 - dutyCycle);
                strobeOn = 1.0 - clamp(fadePhase / fadeOff, 0.0, 1.0);
            }
        }
        
        val = lineOn * strobeOn;
        
                float linePhaseOffset = hash2(lineIndex + 100.0, beatIndex) * 0.3;
        float adjustedPhase = fract(phase + linePhaseOffset * 0.5);
        if (adjustedPhase > dutyCycle + 0.1) {
                        float extraFade = fadeOff > 0.01 ? (1.0 - clamp((adjustedPhase - dutyCycle) / fadeOff, 0.0, 1.0)) : 0.0;
            val = lineOn * max(strobeOn, extraFade * 0.5);
        }
    }
    
        val *= brightness;
    
        if (invert) {
        val = brightness - val;
    }
    
        val = clamp(val, 0.0, 1.0);
    
    gl_FragColor = vec4(val, val, val, 1.0);
}

// COST=15.556
// MODEL=claude-opus-4-6
// PROMPT=Create a Stobe effect that can be used as mask (purely black white or gray, no color) and has a parameter that can make the srobe effect from 80bpm to up to 240bpm and e.g. a parameter to set the bpm and then do it in like phrases or fractions of a phrase, right?the strobe effect should have different patterns: 1. roller from top to botttom, 2. circle from insider growing out, 3. just full on or off, 4, lots of randm lines, like e.g. just random scanlines horizontel. Another paremeter is the fade off, default instant, but then also with the option with a super fast fade off so that when the frequencey goes up, it essentially stay white. Duty cycle to decide on the ration of white vs black
//

// COST=6.862
// MODEL=claude-opus-4-6
// PROMPT=Create a Stobe effect that can be used as mask (purely black white or gray, no color) and has a parameter that can make the srobe effect from 80bpm to up to 240bpm and e.g. a parameter to set the bpm and then do it in like phrases or fractions of a phrase, right?
//