/*
{
    "CREDIT": "Magic Music Visuals",
    "DESCRIPTION": "Dynamic text renderer that arranges characters from integer variables into a grid layout using a standard 16x16 ASCII font atlas.",
    "ISFVSN": "2",
    "CATEGORIES": [
        "Text",
        "Generator"
    ],
    "INPUTS": [
        {
            "NAME": "FontImage",
            "TYPE": "image",
            "LABEL": "Font Atlas (16x16)"
        },
        {
            "NAME": "FillColor",
            "TYPE": "color",
            "DEFAULT": [
                1,
                1,
                1,
                1
            ]
        },
        {
            "NAME": "FontSize",
            "TYPE": "float",
            "DEFAULT": 0.1,
            "MIN": 0.01,
            "MAX": 1
        },
        {
            "NAME": "WrapWidth",
            "TYPE": "float",
            "DEFAULT": 1,
            "MIN": 0.1,
            "MAX": 5,
            "LABEL": "Layout Width"
        },
        {
            "NAME": "Char01",
            "TYPE": "long",
            "DEFAULT": 72,
            "LABEL": "Char 1 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char02",
            "TYPE": "long",
            "DEFAULT": 69,
            "LABEL": "Char 2 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char03",
            "TYPE": "long",
            "DEFAULT": 76,
            "LABEL": "Char 3 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char04",
            "TYPE": "long",
            "DEFAULT": 76,
            "LABEL": "Char 4 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char05",
            "TYPE": "long",
            "DEFAULT": 79,
            "LABEL": "Char 5 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char06",
            "TYPE": "long",
            "DEFAULT": 32,
            "LABEL": "Char 6 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char07",
            "TYPE": "long",
            "DEFAULT": 87,
            "LABEL": "Char 7 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char08",
            "TYPE": "long",
            "DEFAULT": 79,
            "LABEL": "Char 8 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char09",
            "TYPE": "long",
            "DEFAULT": 82,
            "LABEL": "Char 9 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char10",
            "TYPE": "long",
            "DEFAULT": 76,
            "LABEL": "Char 10 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char11",
            "TYPE": "long",
            "DEFAULT": 68,
            "LABEL": "Char 11 (ASCII)",
            "MIN": 0,
            "MAX": 255
        },
        {
            "NAME": "Char12",
            "TYPE": "long",
            "DEFAULT": 33,
            "LABEL": "Char 12 (ASCII)",
            "MIN": 0,
            "MAX": 255
        }
    ]
}
*/

void main() {
        vec2 st = gl_FragCoord.xy / RENDERSIZE.xy;
    
        float aspect = RENDERSIZE.x / RENDERSIZE.y;
    st.x *= aspect;
    
        st.y = 1.0 - st.y;
    
        float maxW = WrapWidth * aspect;
    
        if (st.x < 0.0 || st.x > maxW || st.y < 0.0) {
        gl_FragColor = vec4(0.0);
        return;
    }

        float size = FontSize;
    float charsPerLine = floor(maxW / size);
    
        float col = floor(st.x / size);
    float row = floor(st.y / size);
    
        vec2 cellUV = fract(st / size);
    
        int charIndex = int(row * charsPerLine + col);
    
            int asciiCode = 0;     
    if (charIndex == 0) asciiCode = int(Char01);
    else if (charIndex == 1) asciiCode = int(Char02);
    else if (charIndex == 2) asciiCode = int(Char03);
    else if (charIndex == 3) asciiCode = int(Char04);
    else if (charIndex == 4) asciiCode = int(Char05);
    else if (charIndex == 5) asciiCode = int(Char06);
    else if (charIndex == 6) asciiCode = int(Char07);
    else if (charIndex == 7) asciiCode = int(Char08);
    else if (charIndex == 8) asciiCode = int(Char09);
    else if (charIndex == 9) asciiCode = int(Char10);
    else if (charIndex == 10) asciiCode = int(Char11);
    else if (charIndex == 11) asciiCode = int(Char12);
    
        if (asciiCode == 0) {
        gl_FragColor = vec4(0.0);
        return;
    }

                        
    float atlasCol = mod(float(asciiCode), 16.0);
    float atlasRow = floor(float(asciiCode) / 16.0);
    
            atlasRow = 15.0 - atlasRow;
    
        vec2 fontUV = (vec2(atlasCol, atlasRow) + cellUV) / 16.0;
    
        vec4 texColor = texture2D(FontImage, fontUV);
    
        vec4 finalColor = texColor * FillColor;
    
        gl_FragColor = vec4(finalColor.rgb * finalColor.a, finalColor.a);
}

// COST=15.6972
// MODEL=gemini-3-pro-preview
// PROMPT=create a dynamic text renderer. it has an auto layout mode to do line breaks and parameter to set the generall font and text size. it gets the text from variables
//