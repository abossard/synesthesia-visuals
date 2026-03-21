varying vec2 texOffsets[5];

void main(void) {
    // Load the main shader stuff
    isf_vertShaderInit();

    int blurLevel = int(floor(blurAmount / 6.0));
    float blurMod = mod(blurAmount, 6.0);
    float blurRadius = 0.0;
    float blurRadiusInPixels = 0.0;

    // First three passes are just drawing the texture - do nothing
    if (PASSINDEX == 0) {
        texOffsets[0] = isf_FragNormCoord;
    }
    else if (PASSINDEX == 1) {
        texOffsets[0] = isf_FragNormCoord;
    }
    else if (PASSINDEX == 2) {
        texOffsets[0] = isf_FragNormCoord;
        texOffsets[1] = isf_FragNormCoord;
        texOffsets[2] = isf_FragNormCoord;
    }
    else if (PASSINDEX == 3) {
        // Half-size pass (Pass 2 in FS)
        float pixelWidth = 1.0 / RENDERSIZE.x;
        if (blurLevel == 3) {
            blurRadius = blurMod / 2.0;
        } else if (blurLevel > 3) {
            blurRadius = 3.0;
        }
        blurRadiusInPixels = pixelWidth * blurRadius;
        texOffsets[0] = isf_FragNormCoord;
        texOffsets[1] = (blurRadius == 0.0) ? isf_FragNormCoord : clamp(vec2(isf_FragNormCoord[0] - blurRadiusInPixels, isf_FragNormCoord[1]), 0.0, 1.0);
        texOffsets[2] = (blurRadius == 0.0) ? isf_FragNormCoord : clamp(vec2(isf_FragNormCoord[0] + blurRadiusInPixels, isf_FragNormCoord[1]), 0.0, 1.0);
    }
    else if (PASSINDEX == 4) {
        // Quarter-size pass (Pass 3 in FS)
        float pixelHeight = 1.0 / RENDERSIZE.y;
        if (blurLevel == 2) {
            blurRadius = blurMod / 1.5;
        } else if (blurLevel > 2) {
            blurRadius = 4.0;
        }
        blurRadiusInPixels = pixelHeight * blurRadius;
        texOffsets[0] = isf_FragNormCoord;
        texOffsets[1] = (blurRadius == 0.0) ? isf_FragNormCoord : clamp(vec2(isf_FragNormCoord[0], isf_FragNormCoord[1] - blurRadiusInPixels), 0.0, 1.0);
        texOffsets[2] = (blurRadius == 0.0) ? isf_FragNormCoord : clamp(vec2(isf_FragNormCoord[0], isf_FragNormCoord[1] + blurRadiusInPixels), 0.0, 1.0);
    }
}
