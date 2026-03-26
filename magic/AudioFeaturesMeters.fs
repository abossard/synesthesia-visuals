/*{
    "ISFVSN": "2.0",
    "DESCRIPTION": "9 horizontal bar meters for Energy, Tone, Mid, and Kick Onset. Transparent background for overlay. Link each input to a Magic Global.",
    "CREDIT": "Audio Features Meters",
    "CATEGORIES": ["GENERATOR"],
    "INPUTS": [
        {"NAME": "energyRaw",    "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Energy Raw"},
        {"NAME": "energySmooth", "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Energy Smooth"},
        {"NAME": "energyPeak",   "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Energy Peak"},
        {"NAME": "toneRaw",      "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Tone Raw"},
        {"NAME": "toneSmooth",   "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Tone Smooth"},
        {"NAME": "midRaw",       "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Mid Raw"},
        {"NAME": "midSmooth",    "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Mid Smooth"},
        {"NAME": "midPeak",      "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Mid Peak"},
        {"NAME": "kickOnset",    "TYPE": "float", "DEFAULT": 0.0, "MIN": 0.0, "MAX": 1.0, "LABEL": "Kick Onset"}
    ]
}*/

void main() {
    vec2 uv = isf_FragNormCoord;

    float barH = 1.0 / 9.0;
    float gap = 0.006;
    float band = floor(uv.y / barH);
    float localY = mod(uv.y, barH);

    // Gap between bars = transparent
    if (localY < gap) {
        gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
        return;
    }

    float val = 0.0;
    vec3 barCol = vec3(0.3);

    // Bottom to top: Energy (green), Tone (yellow), Mid (purple), KickOnset (red)
    if (band < 1.0)      { val = energyRaw;    barCol = vec3(0.15, 0.7, 0.2); }
    else if (band < 2.0) { val = energySmooth; barCol = vec3(0.2, 0.8, 0.3); }
    else if (band < 3.0) { val = energyPeak;   barCol = vec3(0.3, 0.9, 0.4); }
    else if (band < 4.0) { val = toneRaw;      barCol = vec3(0.8, 0.7, 0.1); }
    else if (band < 5.0) { val = toneSmooth;   barCol = vec3(0.9, 0.8, 0.2); }
    else if (band < 6.0) { val = midRaw;       barCol = vec3(0.5, 0.2, 0.7); }
    else if (band < 7.0) { val = midSmooth;    barCol = vec3(0.6, 0.3, 0.8); }
    else if (band < 8.0) { val = midPeak;      barCol = vec3(0.7, 0.4, 0.9); }
    else                 { val = kickOnset;    barCol = vec3(1.0, 0.2, 0.2); }

    float fill = step(uv.x, val);
    float alpha = fill * 0.85;
    vec3 col = barCol * fill;

    // Dim background tint for the bar area
    float bgTint = (1.0 - fill) * 0.1;
    col = mix(col, barCol * 0.15, bgTint);
    alpha = max(alpha, bgTint);

    // KickOnset: extra bright flash when active
    if (band >= 8.0 && val > 0.3) {
        col = mix(col, vec3(1.0, 0.9, 0.8), fill * val * 0.5);
        alpha = max(alpha, fill * 0.95);
    }

    gl_FragColor = vec4(col, alpha);
}
