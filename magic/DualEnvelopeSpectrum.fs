/*{
    "ISFVSN": "2.0",
    "DESCRIPTION": "FFT spectrum analyzer with adjustable Low/High frequency cutoff lines. Use to visually find good cutoff values, then apply them to your Magic Globals.",
    "CREDIT": "Dual Envelope Spectrum Analyzer",
    "CATEGORIES": ["GENERATOR", "AUDIO-REACTIVE"],
    "INPUTS": [
        {"NAME": "fftImage",  "TYPE": "audioFFT", "MAX": 256, "LABEL": "FFT Input"},
        {"NAME": "lowFreq",   "TYPE": "float", "DEFAULT": 200.0,  "MIN": 20.0,  "MAX": 20000.0, "LABEL": "Low Freq Cutoff (Hz)"},
        {"NAME": "highFreq",  "TYPE": "float", "DEFAULT": 6000.0, "MIN": 20.0,  "MAX": 20000.0, "LABEL": "High Freq Cutoff (Hz)"}
    ]
}*/

// Convert Hz to normalized UV on a log scale (20 Hz - 20 kHz)
float hzToLogUV(float hz) {
    float minLog = log(20.0) / log(10.0);
    float maxLog = log(20000.0) / log(10.0);
    float hzLog = log(max(hz, 20.0)) / log(10.0);
    return clamp((hzLog - minLog) / (maxLog - minLog), 0.0, 1.0);
}

// Convert log-scale UV back to linear FFT UV (for texture lookup)
float logUVtoLinearUV(float logUV) {
    float minLog = log(20.0) / log(10.0);
    float maxLog = log(20000.0) / log(10.0);
    float hzLog = minLog + logUV * (maxLog - minLog);
    float hz = pow(10.0, hzLog);
    return clamp(hz / 22050.0, 0.0, 1.0);
}

void main() {
    vec2 uv = isf_FragNormCoord;
    vec3 col = vec3(0.04);

    // Read FFT value at this x position (log-scaled frequency axis)
    float linearUV = logUVtoLinearUV(uv.x);
    float fftVal = IMG_NORM_PIXEL(fftImage, vec2(linearUV, 0.0)).r;

    // Compute cutoff positions on log scale
    float lowCutX = hzToLogUV(lowFreq);
    float highCutX = hzToLogUV(highFreq);

    // Color the spectrum: blue below lowFreq, orange above highFreq, grey in between
    vec3 specCol = vec3(0.4);
    if (uv.x <= lowCutX) {
        specCol = vec3(0.2, 0.5, 1.0);
    }
    if (uv.x >= highCutX) {
        // If bands overlap, show purple blend where both regions cover
        specCol = (uv.x <= lowCutX) ? vec3(0.6, 0.3, 0.9) : vec3(1.0, 0.6, 0.15);
    }

    // Draw spectrum fill
    float barFill = step(uv.y, fftVal * 1.2);
    col = mix(col, specCol, barFill * 0.8);

    // Dim tint in the envelope regions even when no signal
    if (uv.x <= lowCutX) {
        col = mix(col, vec3(0.1, 0.2, 0.5), (1.0 - barFill) * 0.08);
    }
    if (uv.x >= highCutX) {
        col = mix(col, vec3(0.5, 0.25, 0.05), (1.0 - barFill) * 0.08);
    }

    // Draw cutoff lines (vertical, full height)
    float lineW = 2.0 / RENDERSIZE.x;
    if (abs(uv.x - lowCutX) < lineW) {
        col = vec3(0.3, 0.6, 1.0);
    }
    if (abs(uv.x - highCutX) < lineW) {
        col = vec3(1.0, 0.7, 0.2);
    }

    // Frequency axis tick marks at 100, 1k, 10k
    float mark100 = hzToLogUV(100.0);
    float mark1k  = hzToLogUV(1000.0);
    float mark10k = hzToLogUV(10000.0);
    float tickW = 1.5 / RENDERSIZE.x;
    if (uv.y < 0.02) {
        if (abs(uv.x - mark100) < tickW || abs(uv.x - mark1k) < tickW || abs(uv.x - mark10k) < tickW) {
            col = vec3(0.6);
        }
    }

    gl_FragColor = vec4(col, 1.0);
}
