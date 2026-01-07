/*
{
    "CREDIT": "Magic Music Visuals",
    "DESCRIPTION": "Tiles 6 inputs preserving aspect ratio",
    "ISFVSN": "2.0",
    "INPUTS": [
        {
            "NAME": "inputImage1",
            "TYPE": "image"
        },
        {
            "NAME": "inputImage2",
            "TYPE": "image"
        },
        {
            "NAME": "inputImage3",
            "TYPE": "image"
        },
        {
            "NAME": "inputImage4",
            "TYPE": "image"
        },
        {
            "NAME": "inputImage5",
            "TYPE": "image"
        },
        {
            "NAME": "inputImage6",
            "TYPE": "image"
        }
    ]
}
*/

void main() {
    vec2 uv = gl_FragCoord.xy / RENDERSIZE;
    
        float cols = 3.0;
    float rows = 2.0;
    
                    
    float colIndex = floor(uv.x * cols);
    float rowIndex = floor(uv.y * rows);
    
        vec2 cellUV = vec2(fract(uv.x * cols), fract(uv.y * rows));
    
        vec2 cellRes = RENDERSIZE / vec2(cols, rows);
    float cellAspect = cellRes.x / cellRes.y;
    
    vec2 imgSize = vec2(1.0, 1.0);
    vec4 color = vec4(0.0);
    
            if (rowIndex > 0.5) {
        if (colIndex < 1.0) {
            imgSize = IMG_SIZE(inputImage1);
        } else if (colIndex < 2.0) {
            imgSize = IMG_SIZE(inputImage2);
        } else {
            imgSize = IMG_SIZE(inputImage3);
        }
    } 
        else {
        if (colIndex < 1.0) {
            imgSize = IMG_SIZE(inputImage4);
        } else if (colIndex < 2.0) {
            imgSize = IMG_SIZE(inputImage5);
        } else {
            imgSize = IMG_SIZE(inputImage6);
        }
    }
    
    float imgAspect = imgSize.x / imgSize.y;
    
        vec2 scale = vec2(1.0);
    
    if (imgAspect > cellAspect) {
                scale = vec2(1.0, cellAspect / imgAspect);
    } else {
                scale = vec2(imgAspect / cellAspect, 1.0);
    }
    
        vec2 centeredUV = (cellUV - 0.5) / scale + 0.5;
    
        if (centeredUV.x < 0.0 || centeredUV.x > 1.0 || centeredUV.y < 0.0 || centeredUV.y > 1.0) {
        color = vec4(0.0);
    } else {
                if (rowIndex > 0.5) {
            if (colIndex < 1.0) {
                color = IMG_NORM_PIXEL(inputImage1, centeredUV);
            } else if (colIndex < 2.0) {
                color = IMG_NORM_PIXEL(inputImage2, centeredUV);
            } else {
                color = IMG_NORM_PIXEL(inputImage3, centeredUV);
            }
        } else {
            if (colIndex < 1.0) {
                color = IMG_NORM_PIXEL(inputImage4, centeredUV);
            } else if (colIndex < 2.0) {
                color = IMG_NORM_PIXEL(inputImage5, centeredUV);
            } else {
                color = IMG_NORM_PIXEL(inputImage6, centeredUV);
            }
        }
    }
    
        if (color.a < 1.0 && color.a > 0.0) {
        color.rgb *= color.a;
    }
    
    gl_FragColor = color;
}

// COST=16.3572
// MODEL=gemini-3-pro-preview
// PROMPT=Create a shader that takes 6 inputs textures and then tiles them. each input can have a name. the tiles should keep all aspect ratios
//