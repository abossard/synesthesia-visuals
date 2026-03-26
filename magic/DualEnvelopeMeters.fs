/*{
    "ISFVSN": "2.0",
    "DESCRIPTION": "6 horizontal bar meters for dual envelope output values. Link each input to a Magic Global (LowRaw, LowPeak, LowAvg, HighRaw, HighPeak, HighAvg).",
    "CREDIT": "Dual Envelope Meters",
    "CATEGORIES": ["GENERATOR"],
    "INPUTS": [
        {"NAME": "lowRaw",   "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Low Raw"},
        {"NAME": "lowAvg",   "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Low Avg"},
        {"NAME": "lowPeak",  "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Low Peak"},
        {"NAME": "highRaw",  "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "High Raw"},
        {"NAME": "highAvg",  "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "High Avg"},
        {"NAME": "highPeak", "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "High Peak"}
    ]
}*/

void main() {
    vec2 uv = isf_FragNormCoord;
    vec3 col = vec3(0.04);

    float barH = 1.0 / 6.0;
    float gap = 0.008;
    float band = floor(uv.y / barH);
    float localY = mod(uv.y, barH);

    // Gap between bars
    if (localY < gap) {
        gl_FragColor = vec4(vec3(0.02), 1.0);
        return;
    }

    float val = 0.0;
    vec3 barCol = vec3(0.3);

    // Bottom to top: LowRaw, LowAvg, LowPeak, HighRaw, HighAvg, HighPeak
    if (band < 1.0)      { val = lowRaw;   barCol = vec3(0.15, 0.35, 0.9); }
    else if (band < 2.0) { val = lowAvg;   barCol = vec3(0.25, 0.50, 1.0); }
    else if (band < 3.0) { val = lowPeak;  barCol = vec3(0.45, 0.70, 1.0); }
    else if (band < 4.0) { val = highRaw;  barCol = vec3(0.9, 0.45, 0.05); }
    else if (band < 5.0) { val = highAvg;  barCol = vec3(1.0, 0.60, 0.15); }
    else                 { val = highPeak; barCol = vec3(1.0, 0.80, 0.30); }

    float fill = step(uv.x, val);
    col = mix(col, barCol, fill * 0.85);

    // Dim background tint
    col = mix(col, barCol * 0.08, (1.0 - fill));

    gl_FragColor = vec4(col, 1.0);
}
