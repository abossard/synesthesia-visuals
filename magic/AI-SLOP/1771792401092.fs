/*
{
    "CREDIT": "Magic Music Visuals",
    "DESCRIPTION": "Black and white strobe effect synced to BPM with phrase\/fraction control",
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
            "NAME": "dutyCycle",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.01,
            "MAX": 1,
            "LABEL": "Duty Cycle"
        },
        {
            "NAME": "smoothness",
            "TYPE": "float",
            "DEFAULT": 0,
            "MIN": 0,
            "MAX": 1,
            "LABEL": "Smoothness"
        },
        {
            "NAME": "invert",
            "TYPE": "bool",
            "DEFAULT": false,
            "MIN": 0,
            "MAX": 1,
            "LABEL": "Invert"
        },
        {
            "NAME": "brightness",
            "TYPE": "float",
            "DEFAULT": 1,
            "MIN": 0,
            "MAX": 1,
            "LABEL": "Max Brightness"
        }
    ]
}
*/

#define PI 3.14159265359

void main() {
        float beatsPerSec = bpm / 60.0;
    
                float multiplier;
    if (phraseDiv == 0) {
        multiplier = 1.0 / 16.0;     } else if (phraseDiv == 1) {
        multiplier = 1.0 / 8.0;      } else if (phraseDiv == 2) {
        multiplier = 1.0 / 4.0;      } else if (phraseDiv == 3) {
        multiplier = 1.0 / 2.0;      } else if (phraseDiv == 4) {
        multiplier = 1.0;             } else if (phraseDiv == 5) {
        multiplier = 2.0;             } else if (phraseDiv == 6) {
        multiplier = 4.0;             } else {
        multiplier = 8.0;             }
    
        float freq = beatsPerSec * multiplier;
    
        float phase = fract(TIME * freq);
    
    float val;
    
    if (smoothness < 0.01) {
                val = phase < dutyCycle ? 1.0 : 0.0;
    } else {
                float edge = smoothness * 0.5;
        float onEdge = smoothstep(dutyCycle - edge, dutyCycle + edge, phase);
        val = 1.0 - onEdge;
                float startEdge = smoothstep(-edge, edge, phase);
        val = val * startEdge;
                float wrapVal = smoothstep(1.0 - edge, 1.0, phase);
        val = max(val, wrapVal);
    }
    
        val *= brightness;
    
        if (invert) {
        val = brightness - val;
    }
    
        val = clamp(val, 0.0, 1.0);
    
    gl_FragColor = vec4(val, val, val, 1.0);
}

// COST=6.862
// MODEL=claude-opus-4-6
// PROMPT=Create a Stobe effect that can be used as mask (purely black white or gray, no color) and has a parameter that can make the srobe effect from 80bpm to up to 240bpm and e.g. a parameter to set the bpm and then do it in like phrases or fractions of a phrase, right?
//