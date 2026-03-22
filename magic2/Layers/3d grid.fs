/*{
    "CATEGORIES": ["Generator"],
    "DESCRIPTION": "3D perspective grid with adjustable parameters for lines and grid effects",
    "INPUTS": [
        {
            "NAME": "posY",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "persp",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.1,
            "MAX": 3.0
        },
        {
            "NAME": "linewidth",
            "TYPE": "float",
            "DEFAULT": 0.001,
            "MIN": 0.001,
            "MAX": 0.1
        },
        {
            "NAME": "scale",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.5,
            "MAX": 1.0
        },
        {
            "NAME": "fade",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": 0.0,
            "MAX": 3.0
        },
        {
            "NAME": "horiz",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "vert",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 1.0
        },
        {
            "NAME": "brightness",
            "TYPE": "float",
            "DEFAULT": 2.0,
            "MIN": 0.0,
            "MAX": 2.0
        },
        {
          "NAME" : "color",
          "TYPE" : "color",
          "DEFAULT" : [
            1.0,
            1.0,
            1.0,
            1
          ]
        }
    ]
}*/

// Half cells for positioning

// Segment drawing function with adjustable parameters
vec3 segment(vec2 p, vec3 from, vec3 to, float width, float dist) {
    width = 1.0 / width;
    vec2 seg = from.xy - to.xy;
    float halfdist = distance(from.xy, to.xy) * 0.5;
    float ang = atan(seg.y, seg.x);
    float sine = sin(ang);
    float cose = cos(ang);
    p -= from.xy; 
    p *= mat2(cose, sine, -sine, cose);
    float dx = abs(p.x + halfdist) - halfdist;
    float dy = abs(p.y);
    float pz = -from.z - (to.z - from.z);
    float l = 1.0 - clamp(max(dx, dy) * width / (pz + dist) * dist * dist, 0.0, 0.1) / 0.1;
    l = pow(abs(l), 4.) * (1.0 - pow(clamp(abs(dist - pz) * 0.5, 0.0, 1.0), 0.5)) * 1.0;
    return vec3((3.5 -fade) - (from.z * fade)) * l * color.rgb;
    

}

// Rotation matrix function
mat3 rotmat(vec3 v, float angle) {
    angle = radians(angle);
    float c = cos(angle);
    float s = sin(angle);
    
    return mat3(
        c + (1.0 - c) * v.x * v.x, (1.0 - c) * v.x * v.y - s * v.z, (1.0 - c) * v.x * v.z + s * v.y,
        (1.0 - c) * v.x * v.y + s * v.z, c + (1.0 - c) * v.y * v.y, (1.0 - c) * v.y * v.z - s * v.x,
        (1.0 - c) * v.x * v.z - s * v.y, (1.0 - c) * v.y * v.z + s * v.x, c + (1.0 - c) * v.z * v.z
    );
}

// Get Z-depth value for grid positioning
float getz(vec2 xy) {
    return 0.;
}

void main() {
    vec2 uv = isf_FragNormCoord - 0.5;
    
    // Apply perspective transformation with zOffset controlling the closest point to the viewer
    vec2 perspectiveUV = (uv - 0.5) * vec2(persp, 1.0);  // Scale horizontally by persp to bring closest point forward
    perspectiveUV.y = (perspectiveUV.y + 0.5) / (abs(perspectiveUV.y + 0.1) + 0.05);
    float tilt = -0.25 + posY * 0.5;
    // Initialize camera rotation based on time and preset configurations
    mat3 camrot = rotmat(normalize(vec3(0.0, 0.0, 1.0)), 0.0 * 90.0) *
                  rotmat(normalize(vec3(1.0, 0.0, 0.0)), 90. + 90.0 * tilt);

    float dist = 1.2 + pow(scale, 5.0) * 0.5;
    vec3 col = vec3(0.0);
    
    const float cells = 10.0; // Number of grid cells.
const float halfCells = cells * 0.5; // Half of the grid for centering.

for (float y = 0.0; y < cells; y++) {
    for (float x = 0.0; x < cells; x++) {
        // Correct grid positioning to center on the x-axis.
        vec3 p1 = vec3(x - halfCells + 0.5, y - halfCells + 0.5, 0.0) * 0.1; // Offset by 0.5 for proper centering.
        vec3 p2 = vec3(p1.x + 0.1, p1.y, 0.0);
        vec3 p3 = vec3(p1.x, p1.y + 0.1, 0.0);

        // Apply camera rotation to the points.
        p1 *= camrot;
        p2 *= camrot;
        p3 *= camrot;

        // Apply perspective distortion.
        p1.xy *= persp / max(0.1, p1.z + dist);
        p2.xy *= persp / max(0.1, p2.z + dist);
        p3.xy *= persp / max(0.1, p3.z + dist);

        // Add y-axis offset (already accounted for in your original code).
        float yOffset = persp * (-0.25 + posY * 0.5);
        p1.y += yOffset;
        p2.y += yOffset;
        p3.y += yOffset;

        // Compute linewidth for the grid lines.
        float line = max(0.05, persp * linewidth);

        // Draw horizontal segments.
        if (max(p1.x, p2.x) > uv.x - line / 4.0 && min(p1.x, p2.x) < uv.x + line / 4.0 && x < cells - 1.0) {
            if (max(p1.y, p2.y) > uv.y - line / 4.0 && min(p1.y, p2.y) < uv.y + line / 4.0) {
                col += segment(uv, p1, p2, line, dist) * horiz;
            }
        }

        // Draw vertical segments.
        if (max(p1.x, p3.x) > uv.x - line / 4.0 && min(p1.x, p3.x) < uv.x + line / 4.0 && y < cells - 1.0) {
            if (max(p1.y, p3.y) > uv.y - line / 4.0 && min(p1.y, p3.y) < uv.y + line / 4.0) {
                col += segment(uv, p1, p3, line, dist) * vert;
            }
        }
    }
}


    // Adjust brightness
    col *= brightness;

    gl_FragColor = vec4(col, 1.0);
}
