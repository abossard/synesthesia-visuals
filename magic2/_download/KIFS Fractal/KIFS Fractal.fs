
/*{
    "DESCRIPTION": "Fractal shader with mirroring and customizable parameters.",
    "CATEGORIES": ["Fractal", "Mirroring", "Interactive"],
    "INPUTS": [
		{
			"NAME": "inputImage",
			"TYPE": "image"
		},
        {
            "NAME": "offset", 
            "TYPE": "float", 
            "DEFAULT": 0.55, 
            "MIN": 0.0, 
            "MAX": 1.0
        },
        {
            "NAME": "rotation", 
            "TYPE": "float", 
            "DEFAULT": 14.8, 
            "MIN": 14.3, 
            "MAX": 15.8
        },
        {
            "NAME": "zoomLevel", 
            "TYPE": "float", 
            "DEFAULT": 2.0, 
            "MIN": 0.5, 
            "MAX": 2.0
            
        }
    ]
}*/

// Based on the code from Art of Code
// https://www.youtube.com/watch?v=il_Qg9AqQkE

// Utility function to calculate normal vector.
vec2 N(float angle) {
    return vec2(sin(angle), cos(angle));
}

// Rotate around an arbitrary line by a given angle.
vec2 rotate(vec2 uv, vec2 cp, float a, bool side) {
    vec2 n = N(a * 3.14159);
    float d = dot(uv - cp, n);
    if (side) {
        uv -= n * max(0.0, d) * 2.0;
    } else {
        uv -= n * min(0.0, d) * 2.0;
    }
    return uv;
}

// Used if needing the distance for showing the mirroring line.
float dist(vec2 uv, vec2 cp, float a) {
    vec2 n = N(a * 3.14159);
    return dot(uv - cp, n);
}

void main() {
    // ISF Variables
    vec2 uv = isf_FragNormCoord * RENDERSIZE; // Normalized fragment coordinates.
    uv -= 0.5 * RENDERSIZE;                  // Center origin.
    uv /= RENDERSIZE.y;                      // Square using aspect ratio.

    uv *= zoomLevel; // Apply zoom level.
    
    
    
    uv.y += tan((5.0 / 6.0) * 3.14159) * 0.5; // Re-center.


    vec3 col = vec3(0.0); // Initialize black color.

    uv.x = abs(uv.x); // Mirror on Y axis.
    uv = rotate(uv, vec2(0.5, 0.0), 5.0 / 6.0, true); // Rotate UV.

    float scale = 1.0; // Initial scale.
    uv.x += 0.5;       // Shift right.

    for (int i = 0; i < 5; i++) {
        uv *= 3.0; // Scale UV.
        scale *= 3.0;
        uv.x -= 1.5; // Shift left.
        uv.x = abs(uv.x); // Mirror on Y axis.
        uv.x -= 0.5; // Shift left.
        uv = rotate(uv, vec2(0.0, 0.0), rotation * 0.1 * 3.14159, false);
    }
        //Calculate the color based on the distance from the line. Until now, just shifting, scaling, mirroring UV space.
        //Remember uv space has been mirrored repeatedly to create the fractal outline. 
        //So we are only drwaing one line, but it is crumpled up.
    float d = length(uv - vec2(clamp(uv.x, -1.0, 1.0), 0));


    uv /= scale;
    col += IMG_NORM_PIXEL(inputImage, vec2(offset, 0.0) - uv).rgb;
    col += smoothstep(1.0 / RENDERSIZE.y, 0.0, d / scale);//Smooth out and thicken the lines. and adjust based on scale.


    gl_FragColor = vec4(col, 1.0); // Output the final color.
}
