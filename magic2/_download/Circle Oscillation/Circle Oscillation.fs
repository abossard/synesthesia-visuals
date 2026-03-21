/*
{
    "CATEGORIES": [
        "Automatically Converted",
        "GrandC Viz"
    ],
    "DESCRIPTION": "  Trip Chess Patten",
    "IMPORTED": {
    },
    "INPUTS": [
    {
        "LABEL":"Speed",
        "MIN": 1,
        "MAX": 4,
        "DEFAULT": 1,
        "TYPE": "float",
        "NAME": "Speed"
    },
    {
        "LABEL":"Blur",
        "MIN": 0.1,
        "MAX": 1,
        "DEFAULT": 0.7,
        "TYPE": "float",
        "NAME": "Blur"
    },
    {
        "LABEL":"Angle",
        "MIN": 0.0,
        "MAX": 6.28319,
        "DEFAULT": 0.78,
        "TYPE": "float",
        "NAME": "Angle"
    },
    {
        "LABEL":"Zoom",
        "MIN": 1,
        "MAX": 30,
        "DEFAULT": 15,
        "TYPE": "float",
        "NAME": "Zoom"
    }
    ]
}

*/


float Xor(float a, float b){
    return a*(1.0 -b) + b*(1.0 -a);
    }

void main() {



    
    vec2 uv = (gl_FragCoord.xy-0.5*RENDERSIZE.xy)/RENDERSIZE.y;
    
    vec3 col = vec3(0);
    
    
    float a = Angle;
    float s = sin(a);
    float c = cos(a);
    uv *= mat2(c, -s, s, c);
    
    
    uv *=Zoom;
    
    vec2 gv = fract ( uv )-0.5;
    vec2 id = floor(uv);
    
    float m = 0.;
    
    float t = TIME*Speed;
    
    
    for(float y =-1.; y <=1.0; y++){
        for(float x =-1.; x <=1.0; x++){
            vec2 offs = vec2(x, y);
            
            float d = length(gv-offs);
            
            float dist = length(id+offs)*.3;
            
            float r = mix(0.3, 1.5, sin(dist-t)*0.5+0.5);
            
            m = Xor(m, smoothstep(r,r*Blur,d));
           
            }
        }
    //col.rg = gv;
    
    col += m;
    
    gl_FragColor = vec4(col,1.0);
}
