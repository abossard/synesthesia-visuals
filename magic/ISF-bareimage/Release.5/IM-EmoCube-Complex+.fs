/*{
    "DESCRIPTION": "A tumbling voxel cube with 17 generative color palettes and advanced animation controls. Features smoothed, time-independent animation and parameter transitions with dedicated damping controls for rotation, scale, and twist. I am very proud of this shader, each of the side of the shader is defined an array that can be modified to create unlimited numbers of voxel like designs, and if this is not enough, it has build in color template engine. Why + at the end of the name? Well, I got bored with original code, and desided to spice things up by adding XYZ independent rotations, and MATERIAL TWISTING",
    "CREDIT": "Original by @dot2dot (bareimage). ISF 2.0 Conversion by @dot2dot (bareimage)",
    "ISFVSN": "2.0",
    "CATEGORIES": [
        "GENERATOR"
    ],
    "INPUTS": [
        {
            "NAME": "startTime",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": 0.0,
            "MAX": 1000.0,
            "LABEL": "Start Time Offset"
        },
        {
            "NAME": "colorDamping",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.1,
            "MAX": 10.0,
            "LABEL": "Color/Pattern Damping"
        },
        {
            "NAME": "rotationDamping",
            "TYPE": "float",
            "DEFAULT": 50.0,
            "MIN": 0.1,
            "MAX": 100.0,
            "LABEL": "Rotation Damping"
        },
        {
            "NAME": "scaleTwistDamping",
            "TYPE": "float",
            "DEFAULT": 2.0,
            "MIN": 0.1,
            "MAX": 10.0,
            "LABEL": "Scale & Twist Damping"
        },
        {
            "NAME": "colorPalette",
            "TYPE": "long",
            "DEFAULT": 3,
            "VALUES": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
            "LABELS": ["Plasma Ball", "Accretion Field", "Glitch Matrix", "Stargate", "Original Pop", "Ectoplasm", "Circuit Board", "Warp Drive", "Kaleidoscope", "Nebula", "Dot Matrix", "Interference", "Psychedelic Tunnels", "Turing Spots", "Labyrinth", "Coral Growth", "Cellular"],
            "LABEL": "Color Palette"
        },
        {
            "NAME": "colorAnimSpeed",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 5.0,
            "LABEL": "Color Animation Speed"
        },
        {
            "NAME": "colorBrightness",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 5.0,
            "LABEL": "Color Brightness"
        },
        {
            "NAME": "patternScale",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.1,
            "MAX": 5.0,
            "LABEL": "Pattern Scale"
        },
        {
            "NAME": "patternComplexity",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 1.0,
            "LABEL": "Pattern Complexity"
        },
        {
            "NAME": "rotX", "TYPE": "float", "DEFAULT": 0.0, "MIN": -5.0, "MAX": 5.0, "LABEL": "Rotation X Speed"
        },
        {
            "NAME": "rotY", "TYPE": "float", "DEFAULT": 0.2, "MIN": -5.0, "MAX": 5.0, "LABEL": "Rotation Y Speed"
        },
        {
            "NAME": "rotZ", "TYPE": "float", "DEFAULT": 0.0, "MIN": -5.0, "MAX": 5.0, "LABEL": "Rotation Z Speed"
        },
        {
            "NAME": "scaleX", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.1, "MAX": 3.0, "LABEL": "Scale X"
        },
        {
            "NAME": "scaleY", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.1, "MAX": 3.0, "LABEL": "Scale Y"
        },
        {
            "NAME": "scaleZ", "TYPE": "float", "DEFAULT": 1.0, "MIN": 0.1, "MAX": 3.0, "LABEL": "Scale Z"
        },
        {
            "NAME": "twistX", "TYPE": "float", "DEFAULT": 0.0, "MIN": -1.0, "MAX": 1.0, "LABEL": "Twist X"
        },
        {
            "NAME": "twistY", "TYPE": "float", "DEFAULT": 0.0, "MIN": -1.0, "MAX": 1.0, "LABEL": "Twist Y"
        },
        {
            "NAME": "twistZ", "TYPE": "float", "DEFAULT": 0.0, "MIN": -1.0, "MAX": 1.0, "LABEL": "Twist Z"
        }
    ],
    "PASSES": [
        {
            "TARGET": "timeBuffer",
            "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1
        },
        {
            "TARGET": "colorBuffer",
            "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1
        },
        {
            "TARGET": "controlsBuffer",
            "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1
        },
        {
            "TARGET": "rotationBuffer",
            "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1
        },
        {
            "TARGET": "scaleBuffer",
            "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1
        },
        {
            "TARGET": "twistBuffer",
            "PERSISTENT": true, "FLOAT": true, "WIDTH": 1, "HEIGHT": 1
        },
        {
            "TARGET": "sceneBuffer",
            "FLOAT": true
        },
        {
            "TARGET": "finalOutput"
        }
    ]
}*/

// MIT License
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// ADDITIONAL ATTRIBUTION REQUIREMENT:
// When using, modifying, or distributing this software, proper acknowledgment
// and credit must be maintained for both the original authors and any
// substantial contributors to derivative works.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

// --- Utility & Noise Functions ---
vec3 hsv2rgb(vec3 c) { vec4 K=vec4(1.,2./3.,1./3.,3.); vec3 p=abs(fract(c.xxx+K.xyz)*6.-K.www); return c.z*mix(K.xxx,clamp(p-K.xxx,0.,1.),c.y); }
float hash11(float p) { return fract(sin(p*727.1)*435.545); }
vec2 hash2(vec2 p) { return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453); }
float noise(vec3 x) {
    vec3 p=floor(x), f=fract(x); f=f*f*(3.-2.*f); float n=p.x+p.y*157.+113.*p.z;
    return mix(mix(mix(hash11(n),hash11(n+1.),f.x),mix(hash11(n+157.),hash11(n+158.),f.x),f.y),
               mix(mix(hash11(n+113.),hash11(n+114.),f.x),mix(hash11(n+270.),hash11(n+271.),f.x),f.y),f.z);
}
vec3 aces_approx(vec3 v) {
    v=max(v,0.)*0.6; float a=2.51,b=0.03,c=2.43,d=0.59,e=0.14;
    return clamp((v*(a*v+b))/(v*(c*v+d)+e),0.,1.);
}

// --- Transformation Helpers ---
mat3 rotationX(float angle) { float s=sin(angle),c=cos(angle); return mat3(1.0,0.0,0.0,0.0,c,-s,0.0,s,c); }
mat3 rotationY(float angle) { float s=sin(angle),c=cos(angle); return mat3(c,0.0,s,0.0,1.0,0.0,-s,0.0,c); }
mat3 rotationZ(float angle) { float s=sin(angle),c=cos(angle); return mat3(c,-s,0.0,s,c,0.0,0.0,0.0,1.0); }

// Applies an organic-looking twist to a 3D coordinate
vec3 twist(vec3 p, vec3 t) {
    float c,s;
    c=cos(t.x*p.x); s=sin(t.x*p.x); p.yz=mat2(c,-s,s,c)*p.yz;
    c=cos(t.y*p.y); s=sin(t.y*p.y); p.xz=mat2(c,-s,s,c)*p.xz;
    c=cos(t.z*p.z); s=sin(t.z*p.z); p.xy=mat2(c,-s,s,c)*p.xy;
    return p;
}

// --- Voxel Cube Data (Correctly Formatted) ---
// --- Voxel Cube Data (GLSL 1.20 compatible) ---
float faceFront[169];
float faceBack[169];
float faceTop[169];
float faceBottom[169];
float faceLeft[169];
float faceRight[169];

void initFaceData() {
    faceFront[0]=1.0; faceFront[1]=1.0; faceFront[2]=1.0; faceFront[3]=1.0; faceFront[4]=1.0; faceFront[5]=1.0;
    faceFront[6]=1.0; faceFront[7]=1.0; faceFront[8]=1.0; faceFront[9]=1.0; faceFront[10]=1.0; faceFront[11]=1.0;
    faceFront[12]=1.0; faceFront[13]=1.0; faceFront[14]=0.0; faceFront[15]=0.0; faceFront[16]=0.0; faceFront[17]=0.0;
    faceFront[18]=0.0; faceFront[19]=0.0; faceFront[20]=0.0; faceFront[21]=0.0; faceFront[22]=0.0; faceFront[23]=0.0;
    faceFront[24]=0.0; faceFront[25]=1.0; faceFront[26]=1.0; faceFront[27]=1.0; faceFront[28]=1.0; faceFront[29]=1.0;
    faceFront[30]=1.0; faceFront[31]=1.0; faceFront[32]=1.0; faceFront[33]=1.0; faceFront[34]=1.0; faceFront[35]=1.0;
    faceFront[36]=1.0; faceFront[37]=0.0; faceFront[38]=1.0; faceFront[39]=1.0; faceFront[40]=0.0; faceFront[41]=0.0;
    faceFront[42]=0.0; faceFront[43]=0.0; faceFront[44]=0.0; faceFront[45]=0.0; faceFront[46]=0.0; faceFront[47]=0.0;
    faceFront[48]=0.0; faceFront[49]=1.0; faceFront[50]=0.0; faceFront[51]=1.0; faceFront[52]=1.0; faceFront[53]=0.0;
    faceFront[54]=1.0; faceFront[55]=1.0; faceFront[56]=1.0; faceFront[57]=1.0; faceFront[58]=1.0; faceFront[59]=1.0;
    faceFront[60]=1.0; faceFront[61]=0.0; faceFront[62]=1.0; faceFront[63]=0.0; faceFront[64]=1.0; faceFront[65]=1.0;
    faceFront[66]=0.0; faceFront[67]=1.0; faceFront[68]=0.0; faceFront[69]=0.0; faceFront[70]=0.0; faceFront[71]=0.0;
    faceFront[72]=0.0; faceFront[73]=1.0; faceFront[74]=0.0; faceFront[75]=1.0; faceFront[76]=0.0; faceFront[77]=1.0;
    faceFront[78]=1.0; faceFront[79]=0.0; faceFront[80]=1.0; faceFront[81]=0.0; faceFront[82]=1.0; faceFront[83]=1.0;
    faceFront[84]=1.0; faceFront[85]=0.0; faceFront[86]=1.0; faceFront[87]=0.0; faceFront[88]=1.0; faceFront[89]=0.0;
    faceFront[90]=1.0; faceFront[91]=1.0; faceFront[92]=0.0; faceFront[93]=1.0; faceFront[94]=0.0; faceFront[95]=1.0;
    faceFront[96]=0.0; faceFront[97]=0.0; faceFront[98]=0.0; faceFront[99]=1.0; faceFront[100]=0.0; faceFront[101]=1.0;
    faceFront[102]=0.0; faceFront[103]=1.0; faceFront[104]=1.0; faceFront[105]=0.0; faceFront[106]=1.0; faceFront[107]=0.0;
    faceFront[108]=1.0; faceFront[109]=1.0; faceFront[110]=1.0; faceFront[111]=1.0; faceFront[112]=1.0; faceFront[113]=0.0;
    faceFront[114]=1.0; faceFront[115]=0.0; faceFront[116]=1.0; faceFront[117]=1.0; faceFront[118]=0.0; faceFront[119]=1.0;
    faceFront[120]=0.0; faceFront[121]=0.0; faceFront[122]=0.0; faceFront[123]=0.0; faceFront[124]=0.0; faceFront[125]=0.0;
    faceFront[126]=0.0; faceFront[127]=1.0; faceFront[128]=0.0; faceFront[129]=1.0; faceFront[130]=1.0; faceFront[131]=0.0;
    faceFront[132]=1.0; faceFront[133]=1.0; faceFront[134]=1.0; faceFront[135]=1.0; faceFront[136]=1.0; faceFront[137]=1.0;
    faceFront[138]=1.0; faceFront[139]=1.0; faceFront[140]=1.0; faceFront[141]=0.0; faceFront[142]=1.0; faceFront[143]=1.0;
    faceFront[144]=0.0; faceFront[145]=0.0; faceFront[146]=0.0; faceFront[147]=0.0; faceFront[148]=0.0; faceFront[149]=0.0;
    faceFront[150]=0.0; faceFront[151]=0.0; faceFront[152]=0.0; faceFront[153]=0.0; faceFront[154]=0.0; faceFront[155]=1.0;
    faceFront[156]=1.0; faceFront[157]=1.0; faceFront[158]=1.0; faceFront[159]=1.0; faceFront[160]=1.0; faceFront[161]=1.0;
    faceFront[162]=1.0; faceFront[163]=1.0; faceFront[164]=1.0; faceFront[165]=1.0; faceFront[166]=1.0; faceFront[167]=1.0;
    faceFront[168]=1.0; faceBack[0]=1.0; faceBack[1]=1.0; faceBack[2]=1.0; faceBack[3]=1.0; faceBack[4]=1.0;
    faceBack[5]=1.0; faceBack[6]=1.0; faceBack[7]=1.0; faceBack[8]=1.0; faceBack[9]=1.0; faceBack[10]=1.0;
    faceBack[11]=1.0; faceBack[12]=1.0; faceBack[13]=1.0; faceBack[14]=1.0; faceBack[15]=1.0; faceBack[16]=1.0;
    faceBack[17]=1.0; faceBack[18]=1.0; faceBack[19]=1.0; faceBack[20]=1.0; faceBack[21]=1.0; faceBack[22]=1.0;
    faceBack[23]=1.0; faceBack[24]=1.0; faceBack[25]=1.0; faceBack[26]=1.0; faceBack[27]=1.0; faceBack[28]=0.0;
    faceBack[29]=0.0; faceBack[30]=0.0; faceBack[31]=1.0; faceBack[32]=0.0; faceBack[33]=1.0; faceBack[34]=0.0;
    faceBack[35]=0.0; faceBack[36]=0.0; faceBack[37]=1.0; faceBack[38]=1.0; faceBack[39]=1.0; faceBack[40]=1.0;
    faceBack[41]=0.0; faceBack[42]=1.0; faceBack[43]=0.0; faceBack[44]=1.0; faceBack[45]=0.0; faceBack[46]=1.0;
    faceBack[47]=0.0; faceBack[48]=1.0; faceBack[49]=0.0; faceBack[50]=1.0; faceBack[51]=1.0; faceBack[52]=1.0;
    faceBack[53]=1.0; faceBack[54]=1.0; faceBack[55]=1.0; faceBack[56]=1.0; faceBack[57]=1.0; faceBack[58]=0.0;
    faceBack[59]=1.0; faceBack[60]=1.0; faceBack[61]=1.0; faceBack[62]=1.0; faceBack[63]=1.0; faceBack[64]=1.0;
    faceBack[65]=1.0; faceBack[66]=0.0; faceBack[67]=0.0; faceBack[68]=1.0; faceBack[69]=1.0; faceBack[70]=1.0;
    faceBack[71]=0.0; faceBack[72]=1.0; faceBack[73]=1.0; faceBack[74]=1.0; faceBack[75]=0.0; faceBack[76]=0.0;
    faceBack[77]=1.0; faceBack[78]=1.0; faceBack[79]=1.0; faceBack[80]=1.0; faceBack[81]=1.0; faceBack[82]=1.0;
    faceBack[83]=0.0; faceBack[84]=0.0; faceBack[85]=0.0; faceBack[86]=1.0; faceBack[87]=1.0; faceBack[88]=1.0;
    faceBack[89]=1.0; faceBack[90]=1.0; faceBack[91]=1.0; faceBack[92]=1.0; faceBack[93]=0.0; faceBack[94]=1.0;
    faceBack[95]=1.0; faceBack[96]=1.0; faceBack[97]=1.0; faceBack[98]=1.0; faceBack[99]=1.0; faceBack[100]=1.0;
    faceBack[101]=0.0; faceBack[102]=1.0; faceBack[103]=1.0; faceBack[104]=1.0; faceBack[105]=1.0; faceBack[106]=1.0;
    faceBack[107]=1.0; faceBack[108]=0.0; faceBack[109]=0.0; faceBack[110]=0.0; faceBack[111]=0.0; faceBack[112]=0.0;
    faceBack[113]=1.0; faceBack[114]=1.0; faceBack[115]=1.0; faceBack[116]=1.0; faceBack[117]=1.0; faceBack[118]=1.0;
    faceBack[119]=0.0; faceBack[120]=1.0; faceBack[121]=0.0; faceBack[122]=1.0; faceBack[123]=1.0; faceBack[124]=1.0;
    faceBack[125]=0.0; faceBack[126]=1.0; faceBack[127]=0.0; faceBack[128]=1.0; faceBack[129]=1.0; faceBack[130]=1.0;
    faceBack[131]=1.0; faceBack[132]=0.0; faceBack[133]=1.0; faceBack[134]=0.0; faceBack[135]=0.0; faceBack[136]=0.0;
    faceBack[137]=0.0; faceBack[138]=0.0; faceBack[139]=1.0; faceBack[140]=0.0; faceBack[141]=1.0; faceBack[142]=1.0;
    faceBack[143]=1.0; faceBack[144]=0.0; faceBack[145]=0.0; faceBack[146]=1.0; faceBack[147]=1.0; faceBack[148]=1.0;
    faceBack[149]=1.0; faceBack[150]=1.0; faceBack[151]=1.0; faceBack[152]=1.0; faceBack[153]=0.0; faceBack[154]=0.0;
    faceBack[155]=1.0; faceBack[156]=1.0; faceBack[157]=1.0; faceBack[158]=1.0; faceBack[159]=1.0; faceBack[160]=1.0;
    faceBack[161]=1.0; faceBack[162]=1.0; faceBack[163]=1.0; faceBack[164]=1.0; faceBack[165]=1.0; faceBack[166]=1.0;
    faceBack[167]=1.0; faceBack[168]=1.0; faceTop[0]=1.0; faceTop[1]=1.0; faceTop[2]=1.0; faceTop[3]=1.0;
    faceTop[4]=1.0; faceTop[5]=1.0; faceTop[6]=1.0; faceTop[7]=1.0; faceTop[8]=1.0; faceTop[9]=1.0;
    faceTop[10]=1.0; faceTop[11]=1.0; faceTop[12]=1.0; faceTop[13]=1.0; faceTop[14]=1.0; faceTop[15]=0.0;
    faceTop[16]=1.0; faceTop[17]=1.0; faceTop[18]=1.0; faceTop[19]=1.0; faceTop[20]=1.0; faceTop[21]=1.0;
    faceTop[22]=1.0; faceTop[23]=0.0; faceTop[24]=1.0; faceTop[25]=1.0; faceTop[26]=1.0; faceTop[27]=1.0;
    faceTop[28]=0.0; faceTop[29]=0.0; faceTop[30]=0.0; faceTop[31]=1.0; faceTop[32]=0.0; faceTop[33]=1.0;
    faceTop[34]=0.0; faceTop[35]=0.0; faceTop[36]=0.0; faceTop[37]=1.0; faceTop[38]=1.0; faceTop[39]=1.0;
    faceTop[40]=1.0; faceTop[41]=1.0; faceTop[42]=1.0; faceTop[43]=0.0; faceTop[44]=1.0; faceTop[45]=0.0;
    faceTop[46]=1.0; faceTop[47]=0.0; faceTop[48]=1.0; faceTop[49]=1.0; faceTop[50]=1.0; faceTop[51]=1.0;
    faceTop[52]=1.0; faceTop[53]=1.0; faceTop[54]=1.0; faceTop[55]=1.0; faceTop[56]=1.0; faceTop[57]=1.0;
    faceTop[58]=0.0; faceTop[59]=1.0; faceTop[60]=1.0; faceTop[61]=1.0; faceTop[62]=1.0; faceTop[63]=1.0;
    faceTop[64]=1.0; faceTop[65]=1.0; faceTop[66]=1.0; faceTop[67]=0.0; faceTop[68]=1.0; faceTop[69]=1.0;
    faceTop[70]=1.0; faceTop[71]=0.0; faceTop[72]=1.0; faceTop[73]=1.0; faceTop[74]=1.0; faceTop[75]=0.0;
    faceTop[76]=1.0; faceTop[77]=1.0; faceTop[78]=1.0; faceTop[79]=0.0; faceTop[80]=0.0; faceTop[81]=1.0;
    faceTop[82]=1.0; faceTop[83]=0.0; faceTop[84]=0.0; faceTop[85]=0.0; faceTop[86]=1.0; faceTop[87]=1.0;
    faceTop[88]=0.0; faceTop[89]=0.0; faceTop[90]=1.0; faceTop[91]=1.0; faceTop[92]=1.0; faceTop[93]=1.0;
    faceTop[94]=1.0; faceTop[95]=1.0; faceTop[96]=1.0; faceTop[97]=1.0; faceTop[98]=1.0; faceTop[99]=1.0;
    faceTop[100]=1.0; faceTop[101]=1.0; faceTop[102]=1.0; faceTop[103]=1.0; faceTop[104]=1.0; faceTop[105]=0.0;
    faceTop[106]=1.0; faceTop[107]=0.0; faceTop[108]=0.0; faceTop[109]=0.0; faceTop[110]=0.0; faceTop[111]=0.0;
    faceTop[112]=0.0; faceTop[113]=0.0; faceTop[114]=1.0; faceTop[115]=1.0; faceTop[116]=1.0; faceTop[117]=1.0;
    faceTop[118]=1.0; faceTop[119]=1.0; faceTop[120]=1.0; faceTop[121]=0.0; faceTop[122]=1.0; faceTop[123]=1.0;
    faceTop[124]=1.0; faceTop[125]=0.0; faceTop[126]=1.0; faceTop[127]=1.0; faceTop[128]=1.0; faceTop[129]=1.0;
    faceTop[130]=1.0; faceTop[131]=0.0; faceTop[132]=1.0; faceTop[133]=1.0; faceTop[134]=1.0; faceTop[135]=0.0;
    faceTop[136]=0.0; faceTop[137]=0.0; faceTop[138]=1.0; faceTop[139]=1.0; faceTop[140]=1.0; faceTop[141]=0.0;
    faceTop[142]=1.0; faceTop[143]=1.0; faceTop[144]=0.0; faceTop[145]=0.0; faceTop[146]=1.0; faceTop[147]=1.0;
    faceTop[148]=1.0; faceTop[149]=0.0; faceTop[150]=1.0; faceTop[151]=1.0; faceTop[152]=1.0; faceTop[153]=0.0;
    faceTop[154]=0.0; faceTop[155]=1.0; faceTop[156]=1.0; faceTop[157]=1.0; faceTop[158]=1.0; faceTop[159]=1.0;
    faceTop[160]=1.0; faceTop[161]=1.0; faceTop[162]=1.0; faceTop[163]=1.0; faceTop[164]=1.0; faceTop[165]=1.0;
    faceTop[166]=1.0; faceTop[167]=1.0; faceTop[168]=1.0; faceBottom[0]=1.0; faceBottom[1]=1.0; faceBottom[2]=1.0;
    faceBottom[3]=1.0; faceBottom[4]=1.0; faceBottom[5]=1.0; faceBottom[6]=1.0; faceBottom[7]=1.0; faceBottom[8]=1.0;
    faceBottom[9]=1.0; faceBottom[10]=1.0; faceBottom[11]=1.0; faceBottom[12]=1.0; faceBottom[13]=1.0; faceBottom[14]=1.0;
    faceBottom[15]=1.0; faceBottom[16]=1.0; faceBottom[17]=1.0; faceBottom[18]=1.0; faceBottom[19]=1.0; faceBottom[20]=1.0;
    faceBottom[21]=1.0; faceBottom[22]=1.0; faceBottom[23]=1.0; faceBottom[24]=1.0; faceBottom[25]=1.0; faceBottom[26]=1.0;
    faceBottom[27]=0.0; faceBottom[28]=0.0; faceBottom[29]=0.0; faceBottom[30]=0.0; faceBottom[31]=1.0; faceBottom[32]=0.0;
    faceBottom[33]=1.0; faceBottom[34]=0.0; faceBottom[35]=0.0; faceBottom[36]=0.0; faceBottom[37]=0.0; faceBottom[38]=1.0;
    faceBottom[39]=1.0; faceBottom[40]=1.0; faceBottom[41]=1.0; faceBottom[42]=1.0; faceBottom[43]=0.0; faceBottom[44]=1.0;
    faceBottom[45]=0.0; faceBottom[46]=1.0; faceBottom[47]=0.0; faceBottom[48]=1.0; faceBottom[49]=1.0; faceBottom[50]=1.0;
    faceBottom[51]=1.0; faceBottom[52]=1.0; faceBottom[53]=1.0; faceBottom[54]=1.0; faceBottom[55]=1.0; faceBottom[56]=1.0;
    faceBottom[57]=1.0; faceBottom[58]=0.0; faceBottom[59]=1.0; faceBottom[60]=1.0; faceBottom[61]=1.0; faceBottom[62]=1.0;
    faceBottom[63]=1.0; faceBottom[64]=1.0; faceBottom[65]=1.0; faceBottom[66]=0.0; faceBottom[67]=0.0; faceBottom[68]=1.0;
    faceBottom[69]=1.0; faceBottom[70]=1.0; faceBottom[71]=0.0; faceBottom[72]=1.0; faceBottom[73]=1.0; faceBottom[74]=1.0;
    faceBottom[75]=0.0; faceBottom[76]=0.0; faceBottom[77]=1.0; faceBottom[78]=1.0; faceBottom[79]=1.0; faceBottom[80]=1.0;
    faceBottom[81]=1.0; faceBottom[82]=1.0; faceBottom[83]=0.0; faceBottom[84]=0.0; faceBottom[85]=0.0; faceBottom[86]=1.0;
    faceBottom[87]=1.0; faceBottom[88]=1.0; faceBottom[89]=1.0; faceBottom[90]=1.0; faceBottom[91]=1.0; faceBottom[92]=1.0;
    faceBottom[93]=0.0; faceBottom[94]=1.0; faceBottom[95]=1.0; faceBottom[96]=1.0; faceBottom[97]=1.0; faceBottom[98]=1.0;
    faceBottom[99]=1.0; faceBottom[100]=1.0; faceBottom[101]=0.0; faceBottom[102]=1.0; faceBottom[103]=1.0; faceBottom[104]=1.0;
    faceBottom[105]=1.0; faceBottom[106]=0.0; faceBottom[107]=1.0; faceBottom[108]=1.0; faceBottom[109]=0.0; faceBottom[110]=0.0;
    faceBottom[111]=0.0; faceBottom[112]=1.0; faceBottom[113]=1.0; faceBottom[114]=0.0; faceBottom[115]=1.0; faceBottom[116]=1.0;
    faceBottom[117]=1.0; faceBottom[118]=1.0; faceBottom[119]=0.0; faceBottom[120]=1.0; faceBottom[121]=1.0; faceBottom[122]=0.0;
    faceBottom[123]=1.0; faceBottom[124]=0.0; faceBottom[125]=1.0; faceBottom[126]=1.0; faceBottom[127]=0.0; faceBottom[128]=1.0;
    faceBottom[129]=1.0; faceBottom[130]=1.0; faceBottom[131]=1.0; faceBottom[132]=0.0; faceBottom[133]=1.0; faceBottom[134]=1.0;
    faceBottom[135]=0.0; faceBottom[136]=1.0; faceBottom[137]=0.0; faceBottom[138]=1.0; faceBottom[139]=1.0; faceBottom[140]=0.0;
    faceBottom[141]=1.0; faceBottom[142]=1.0; faceBottom[143]=1.0; faceBottom[144]=0.0; faceBottom[145]=0.0; faceBottom[146]=1.0;
    faceBottom[147]=1.0; faceBottom[148]=0.0; faceBottom[149]=0.0; faceBottom[150]=0.0; faceBottom[151]=1.0; faceBottom[152]=1.0;
    faceBottom[153]=0.0; faceBottom[154]=0.0; faceBottom[155]=1.0; faceBottom[156]=1.0; faceBottom[157]=1.0; faceBottom[158]=1.0;
    faceBottom[159]=1.0; faceBottom[160]=1.0; faceBottom[161]=1.0; faceBottom[162]=1.0; faceBottom[163]=1.0; faceBottom[164]=1.0;
    faceBottom[165]=1.0; faceBottom[166]=1.0; faceBottom[167]=1.0; faceBottom[168]=1.0; faceLeft[0]=1.0; faceLeft[1]=1.0;
    faceLeft[2]=1.0; faceLeft[3]=1.0; faceLeft[4]=1.0; faceLeft[5]=1.0; faceLeft[6]=1.0; faceLeft[7]=1.0;
    faceLeft[8]=1.0; faceLeft[9]=1.0; faceLeft[10]=1.0; faceLeft[11]=1.0; faceLeft[12]=1.0; faceLeft[13]=1.0;
    faceLeft[14]=1.0; faceLeft[15]=1.0; faceLeft[16]=1.0; faceLeft[17]=0.0; faceLeft[18]=1.0; faceLeft[19]=1.0;
    faceLeft[20]=1.0; faceLeft[21]=0.0; faceLeft[22]=1.0; faceLeft[23]=1.0; faceLeft[24]=1.0; faceLeft[25]=1.0;
    faceLeft[26]=1.0; faceLeft[27]=1.0; faceLeft[28]=0.0; faceLeft[29]=0.0; faceLeft[30]=0.0; faceLeft[31]=1.0;
    faceLeft[32]=0.0; faceLeft[33]=1.0; faceLeft[34]=0.0; faceLeft[35]=0.0; faceLeft[36]=0.0; faceLeft[37]=1.0;
    faceLeft[38]=1.0; faceLeft[39]=1.0; faceLeft[40]=1.0; faceLeft[41]=0.0; faceLeft[42]=1.0; faceLeft[43]=1.0;
    faceLeft[44]=1.0; faceLeft[45]=0.0; faceLeft[46]=1.0; faceLeft[47]=1.0; faceLeft[48]=1.0; faceLeft[49]=0.0;
    faceLeft[50]=1.0; faceLeft[51]=1.0; faceLeft[52]=1.0; faceLeft[53]=1.0; faceLeft[54]=1.0; faceLeft[55]=1.0;
    faceLeft[56]=1.0; faceLeft[57]=1.0; faceLeft[58]=0.0; faceLeft[59]=1.0; faceLeft[60]=1.0; faceLeft[61]=1.0;
    faceLeft[62]=1.0; faceLeft[63]=1.0; faceLeft[64]=1.0; faceLeft[65]=1.0; faceLeft[66]=0.0; faceLeft[67]=0.0;
    faceLeft[68]=0.0; faceLeft[69]=1.0; faceLeft[70]=1.0; faceLeft[71]=0.0; faceLeft[72]=1.0; faceLeft[73]=1.0;
    faceLeft[74]=0.0; faceLeft[75]=0.0; faceLeft[76]=0.0; faceLeft[77]=1.0; faceLeft[78]=1.0; faceLeft[79]=1.0;
    faceLeft[80]=1.0; faceLeft[81]=0.0; faceLeft[82]=1.0; faceLeft[83]=0.0; faceLeft[84]=0.0; faceLeft[85]=0.0;
    faceLeft[86]=1.0; faceLeft[87]=0.0; faceLeft[88]=1.0; faceLeft[89]=1.0; faceLeft[90]=1.0; faceLeft[91]=1.0;
    faceLeft[92]=0.0; faceLeft[93]=1.0; faceLeft[94]=1.0; faceLeft[95]=1.0; faceLeft[96]=1.0; faceLeft[97]=1.0;
    faceLeft[98]=1.0; faceLeft[99]=1.0; faceLeft[100]=1.0; faceLeft[101]=1.0; faceLeft[102]=0.0; faceLeft[103]=1.0;
    faceLeft[104]=1.0; faceLeft[105]=0.0; faceLeft[106]=1.0; faceLeft[107]=1.0; faceLeft[108]=1.0; faceLeft[109]=1.0;
    faceLeft[110]=0.0; faceLeft[111]=1.0; faceLeft[112]=1.0; faceLeft[113]=1.0; faceLeft[114]=1.0; faceLeft[115]=0.0;
    faceLeft[116]=1.0; faceLeft[117]=1.0; faceLeft[118]=0.0; faceLeft[119]=0.0; faceLeft[120]=1.0; faceLeft[121]=1.0;
    faceLeft[122]=0.0; faceLeft[123]=0.0; faceLeft[124]=0.0; faceLeft[125]=1.0; faceLeft[126]=1.0; faceLeft[127]=0.0;
    faceLeft[128]=0.0; faceLeft[129]=1.0; faceLeft[130]=1.0; faceLeft[131]=1.0; faceLeft[132]=1.0; faceLeft[133]=1.0;
    faceLeft[134]=0.0; faceLeft[135]=0.0; faceLeft[136]=1.0; faceLeft[137]=0.0; faceLeft[138]=0.0; faceLeft[139]=1.0;
    faceLeft[140]=1.0; faceLeft[141]=1.0; faceLeft[142]=1.0; faceLeft[143]=1.0; faceLeft[144]=1.0; faceLeft[145]=1.0;
    faceLeft[146]=0.0; faceLeft[147]=0.0; faceLeft[148]=0.0; faceLeft[149]=0.0; faceLeft[150]=0.0; faceLeft[151]=0.0;
    faceLeft[152]=0.0; faceLeft[153]=1.0; faceLeft[154]=1.0; faceLeft[155]=1.0; faceLeft[156]=1.0; faceLeft[157]=1.0;
    faceLeft[158]=1.0; faceLeft[159]=1.0; faceLeft[160]=1.0; faceLeft[161]=1.0; faceLeft[162]=1.0; faceLeft[163]=1.0;
    faceLeft[164]=1.0; faceLeft[165]=1.0; faceLeft[166]=1.0; faceLeft[167]=1.0; faceLeft[168]=1.0; faceRight[0]=1.0;
    faceRight[1]=1.0; faceRight[2]=1.0; faceRight[3]=1.0; faceRight[4]=1.0; faceRight[5]=1.0; faceRight[6]=1.0;
    faceRight[7]=1.0; faceRight[8]=1.0; faceRight[9]=1.0; faceRight[10]=1.0; faceRight[11]=1.0; faceRight[12]=1.0;
    faceRight[13]=1.0; faceRight[14]=1.0; faceRight[15]=1.0; faceRight[16]=1.0; faceRight[17]=1.0; faceRight[18]=1.0;
    faceRight[19]=1.0; faceRight[20]=1.0; faceRight[21]=1.0; faceRight[22]=1.0; faceRight[23]=1.0; faceRight[24]=1.0;
    faceRight[25]=1.0; faceRight[26]=1.0; faceRight[27]=1.0; faceRight[28]=0.0; faceRight[29]=0.0; faceRight[30]=0.0;
    faceRight[31]=1.0; faceRight[32]=0.0; faceRight[33]=1.0; faceRight[34]=0.0; faceRight[35]=0.0; faceRight[36]=0.0;
    faceRight[37]=1.0; faceRight[38]=1.0; faceRight[39]=1.0; faceRight[40]=1.0; faceRight[41]=0.0; faceRight[42]=1.0;
    faceRight[43]=1.0; faceRight[44]=1.0; faceRight[45]=0.0; faceRight[46]=1.0; faceRight[47]=1.0; faceRight[48]=1.0;
    faceRight[49]=0.0; faceRight[50]=1.0; faceRight[51]=1.0; faceRight[52]=1.0; faceRight[53]=1.0; faceRight[54]=0.0;
    faceRight[55]=0.0; faceRight[56]=1.0; faceRight[57]=1.0; faceRight[58]=0.0; faceRight[59]=1.0; faceRight[60]=1.0;
    faceRight[61]=0.0; faceRight[62]=0.0; faceRight[63]=1.0; faceRight[64]=1.0; faceRight[65]=1.0; faceRight[66]=1.0;
    faceRight[67]=1.0; faceRight[68]=1.0; faceRight[69]=1.0; faceRight[70]=1.0; faceRight[71]=0.0; faceRight[72]=1.0;
    faceRight[73]=1.0; faceRight[74]=1.0; faceRight[75]=1.0; faceRight[76]=1.0; faceRight[77]=1.0; faceRight[78]=1.0;
    faceRight[79]=1.0; faceRight[80]=1.0; faceRight[81]=0.0; faceRight[82]=1.0; faceRight[83]=0.0; faceRight[84]=0.0;
    faceRight[85]=0.0; faceRight[86]=1.0; faceRight[87]=0.0; faceRight[88]=1.0; faceRight[89]=1.0; faceRight[90]=1.0;
    faceRight[91]=1.0; faceRight[92]=1.0; faceRight[93]=1.0; faceRight[94]=0.0; faceRight[95]=1.0; faceRight[96]=1.0;
    faceRight[97]=1.0; faceRight[98]=1.0; faceRight[99]=1.0; faceRight[100]=0.0; faceRight[101]=1.0; faceRight[102]=1.0;
    faceRight[103]=1.0; faceRight[104]=1.0; faceRight[105]=0.0; faceRight[106]=1.0; faceRight[107]=0.0; faceRight[108]=1.0;
    faceRight[109]=0.0; faceRight[110]=0.0; faceRight[111]=0.0; faceRight[112]=1.0; faceRight[113]=0.0; faceRight[114]=1.0;
    faceRight[115]=0.0; faceRight[116]=1.0; faceRight[117]=1.0; faceRight[118]=0.0; faceRight[119]=0.0; faceRight[120]=0.0;
    faceRight[121]=1.0; faceRight[122]=0.0; faceRight[123]=0.0; faceRight[124]=0.0; faceRight[125]=1.0; faceRight[126]=0.0;
    faceRight[127]=0.0; faceRight[128]=0.0; faceRight[129]=1.0; faceRight[130]=1.0; faceRight[131]=0.0; faceRight[132]=1.0;
    faceRight[133]=1.0; faceRight[134]=1.0; faceRight[135]=1.0; faceRight[136]=1.0; faceRight[137]=1.0; faceRight[138]=1.0;
    faceRight[139]=1.0; faceRight[140]=1.0; faceRight[141]=0.0; faceRight[142]=1.0; faceRight[143]=1.0; faceRight[144]=1.0;
    faceRight[145]=1.0; faceRight[146]=0.0; faceRight[147]=0.0; faceRight[148]=1.0; faceRight[149]=0.0; faceRight[150]=1.0;
    faceRight[151]=0.0; faceRight[152]=0.0; faceRight[153]=1.0; faceRight[154]=1.0; faceRight[155]=1.0; faceRight[156]=1.0;
    faceRight[157]=1.0; faceRight[158]=1.0; faceRight[159]=1.0; faceRight[160]=1.0; faceRight[161]=1.0; faceRight[162]=1.0;
    faceRight[163]=1.0; faceRight[164]=1.0; faceRight[165]=1.0; faceRight[166]=1.0; faceRight[167]=1.0; faceRight[168]=1.0;
}


// --- Voxel Cube Rendering Logic ---
const float EPS=0.001;
const float CUBE_SIZE = 13.0;
bool voxelMap(in vec3 p,out float v,float t){float last=CUBE_SIZE-1.;vec2 uv;int i=-1;float cV=0.;v=0.;if(p.z>-EPS&&p.z<EPS){uv=p.xy;if(all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(CUBE_SIZE)))){i=int(uv.y)*int(CUBE_SIZE)+int(uv.x);cV=faceFront[i];}}else if(p.z>last-EPS&&p.z<last+EPS){uv=p.xy;if(all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(CUBE_SIZE)))){i=int(uv.y)*int(CUBE_SIZE)+int(uv.x);cV=faceBack[i];}}else if(p.y>-EPS&&p.y<EPS){uv=p.xz;if(all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(CUBE_SIZE)))){i=int(uv.y)*int(CUBE_SIZE)+int(uv.x);cV=faceBottom[i];}}else if(p.y>last-EPS&&p.y<last+EPS){uv=p.xz;if(all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(CUBE_SIZE)))){i=int(uv.y)*int(CUBE_SIZE)+int(uv.x);cV=faceTop[i];}}else if(p.x>-EPS&&p.x<EPS){uv=p.zy;if(all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(CUBE_SIZE)))){i=int(uv.y)*int(CUBE_SIZE)+int(uv.x);cV=faceLeft[i];}}else if(p.x>last-EPS&&p.x<last+EPS){uv=p.zy;if(all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThan(uv,vec2(CUBE_SIZE)))){i=int(uv.y)*int(CUBE_SIZE)+int(uv.x);cV=faceRight[i];}}return cV>0.5;}
bool IRayAABox(in vec3 ro,in vec3 rd,in vec3 invrd,in vec3 bmin,in vec3 bmax,out vec3 p0,out vec3 p1){vec3 t0=(bmin-ro)*invrd,t1=(bmax-ro)*invrd;vec3 tmin=min(t0,t1),tmax=max(t0,t1);float fmin=max(max(tmin.x,tmin.y),tmin.z),fmax=min(min(tmax.x,tmax.y),tmax.z);p0=ro+rd*fmin;p1=ro+rd*fmax;return fmax>=fmin;}
vec3 AABoxNormal(vec3 bmin,vec3 bmax,vec3 p){vec3 c=(bmin+bmax)*0.5,d=p-c,ad=abs(d);if(ad.x>ad.y&&ad.x>ad.z)return vec3(sign(d.x),0.0,0.0);if(ad.y>ad.z)return vec3(0.0,sign(d.y),0.0);return vec3(0.0,0.0,sign(d.z));}
bool traceVoxelGrid(in vec3 i_ro,in vec3 rd,in vec3 invrd,in vec3 bmin,in vec3 bmax,out vec3 n,out vec3 p,out float v,float t){n=vec3(0.0);p=vec3(0.0);v=0.0;vec3 ro,e;if(!IRayAABox(i_ro,rd,invrd,bmin,bmax,ro,e))return false;if(dot(e-ro,rd)<EPS)return false;vec3 ep=floor(ro+rd*EPS);bool ret=false;for(int i=0;i<64;++i){if(voxelMap(ep,v,t)){ret=true;break;}vec3 d0;IRayAABox(ro-rd*2.,rd,invrd,ep,ep+1.,d0,ro);ep=floor(ro+rd*EPS);if(dot(e-ro,rd)<EPS){ret=false;break;}}if(ret){n=AABoxNormal(ep,ep+1.,ro);p=ro;}return ret;}
float intersectVoxelCube(in vec3 ro,in vec3 rd,out vec3 p_hit,out vec3 n_hit,out float v_hit,float t){const float WSIZE=CUBE_SIZE;vec3 bmin_w=-vec3(WSIZE*0.5),bmax_w=vec3(WSIZE*0.5);vec3 invrd=1./rd,p_entry,p_exit;if(!IRayAABox(ro,rd,invrd,bmin_w,bmax_w,p_entry,p_exit))return-1.;vec3 ro_s=p_entry;if(dot(p_entry-ro,rd)<0.)ro_s=ro;vec3 ro_v=(ro_s-bmin_w)/WSIZE*CUBE_SIZE,rd_v=rd/WSIZE*CUBE_SIZE,invrd_v=1./rd_v;vec3 n_v,p_v;if(traceVoxelGrid(ro_v,rd_v,invrd_v,vec3(0.0),vec3(CUBE_SIZE),n_v,p_v,v_hit,t)){p_hit=bmin_w+(p_v/CUBE_SIZE)*WSIZE;n_hit=normalize(n_v);if(distance(ro,p_hit)>distance(ro,p_exit)+EPS)return-1.;return distance(ro,p_hit);}return-1.;}

// --- High-Quality Animated Color Palettes ---
vec3 getColor(int p_int, float time, vec3 p, vec3 n, float t, vec2 uv, vec4 controls, vec3 rd) {
    p *= controls.z; // Apply Pattern Scale
    vec2 face_uv; if(abs(n.x)>0.9)face_uv=p.yz;else if(abs(n.y)>0.9)face_uv=p.xz;else face_uv=p.xy;
    if(p_int==0){float plasma=sin(length(p)*1.5-time*2.);float hue=fract(0.6+0.1*plasma+controls.w*0.5);return hsv2rgb(vec3(hue,1.,1.+plasma));}
    if(p_int==1){vec3 p_turb=p*0.5;for(float i=1.;i<2.+5.*controls.w;i++){p_turb+=sin(p_turb.yzx*i+time*0.5+0.3*t)/i*0.8;}return((1.5+cos(p_turb.x+t*0.4+vec4(6.0,1.0,2.0,0.0)))*1.).rgb;}
    if(p_int==2){p.xy*=mat2(cos(2.+t*0.01+vec4(0.0,11.0,33.0,0.0)));p.xy*=mat2(cos(p.z*0.1+time*0.5+vec4(0.0,11.0,33.0,0.0)));return((1.+sin(0.5*p.z+length(p)+vec4(0.0,4.0,3.0,6.0)))*(0.8+0.2*sin(p.z*(1.+controls.w*20.)))).rgb;}
    if(p_int==3){vec3 col=vec3(0.);for(float i=1.;i<3.+10.*controls.w;i++){float a=atan(face_uv.y,face_uv.x)*ceil(i*2.5)+time*2.*sin(i*i)+i*i;col+=25./(abs(length(face_uv)*6.-i*1.5)+40.)*clamp(cos(a),0.,0.8)*(cos(a-i+vec4(0.0,1.0,2.0,0.0))+1.).rgb;}return col;}
    if(p_int==4){return(1.+sin(vec4(0.,0.5,1.,0.)-t/3.3+(2.+controls.w*5.)*(uv.x+uv.y))).rgb*1.2;}
    if(p_int==5){vec3 N1=vec3(noise(p*0.5+time*0.2));vec3 N2=vec3(noise(p*(1.5+controls.w*3.)-time*0.1));return mix(vec3(N2.x,N1.y,N2.z),vec3(N1.x,N2.y,N1.z),controls.w)*vec3(0.5,2.,1.2);}
    if(p_int==6){vec3 grid=abs(fract(p*0.5)-0.5)/(abs(n)+0.1);float lines=pow(min(min(grid.x,grid.y),grid.z),0.1+controls.w*0.4);float pulse=sin(p.x*(1.+controls.w*5.)-time)*0.5+0.5;return vec3(lines*pulse*2.,lines*1.5,lines*4.);}
    if(p_int==7){float stretch=fract((p.z+n.x)*0.2+time);stretch=pow(stretch,5.*(1.+controls.w*3.));return hsv2rgb(vec3(fract(p.z*0.05),1.,stretch*5.));}
    if(p_int==8){for(int i=0;i<int(controls.w*5.);i++)face_uv=abs(face_uv);face_uv=vec2(atan(face_uv.y,face_uv.x),length(face_uv));face_uv.x+=sin(face_uv.y*2.-time)*0.5;return hsv2rgb(vec3(fract(face_uv.x/6.283),1.,pow(face_uv.y*0.1,0.5)));}
    if(p_int==9){float f=0.;mat2 m=mat2(1.6,1.2,-1.2,1.6);p*=0.5;for(int i=0;i<3+int(controls.w*4.);i++){f+=noise(p)*pow(0.5,float(i));p.xy*=m;}return hsv2rgb(vec3(f+time*0.05,0.8,1.));}
    if(p_int==10){vec3 d=vec3(0.);for(float i=1.;i<4.+8.*controls.w;i+=1.){d.x+=sin(length(p+vec3(i*0.5,0.0,0.0))-time*2.0);d.y+=cos(length(p+vec3(0.0,i*0.5,0.0))-time*2.0);d.z+=sin(length(p-vec3(0.0,0.0,i*0.5))-time*2.0);}return normalize(d)*0.5+0.5;}
    if(p_int==11){float v=0.;float dot_size=mix(0.4,0.4,controls.w);for(int i=1;i<4;++i){vec3 g=floor(p*float(i)*0.5);float id=g.x+g.y*157.+113.*g.z;vec3 f=fract(p*float(i)*0.5);vec3 rand_pos=vec3(hash2(g.xy+g.z),hash11(id*3.14));v+=smoothstep(dot_size,dot_size-0.1,length(f-rand_pos-vec3(0.0,sin(time+id),0.0)));}return vec3(v)*hsv2rgb(vec3(fract(p.z*0.1+time*0.1),1.,1.));}
    if(p_int==12){vec2 p_polar=vec2(atan(face_uv.y,face_uv.x),log(length(face_uv)));float k=1.+controls.w*10.;float a=p_polar.x+time*0.5;a=floor(a*k)/k;p_polar=vec2(p_polar.y*cos(a)-a*sin(a),p_polar.y*sin(a)+a*cos(a));return hsv2rgb(vec3(fract(p_polar.x*.2+time*.1),1.,smoothstep(0.,1.,fract(p_polar.y*5.))));}
    if(p_int==13){vec2 g=floor(face_uv*3.),f=fract(face_uv*3.)-.5;float d=1e9;vec3 c;for(int i=-1;i<=1;i++)for(int j=-1;j<=1;j++){vec2 o=hash2(g+vec2(i,j));float D=length(f-o+.5);if(D<d){d=D;c=hsv2rgb(vec3(hash11(g.x+g.y*157.+time*.1),.7,.9));}}return(1.-smoothstep(0.,.8,d))*c;}
    if(p_int==14){float n=noise(p*0.5);float pattern=sin(n*15.+time*2.+sin(p.y+n)*2.);pattern=smoothstep(0.,1.,pattern);return hsv2rgb(vec3(fract(n+time*0.1),0.8,pattern));}
    if(p_int==15){vec2 p_warp=face_uv;for(int i=0;i<3+int(controls.w*5.);i++){p_warp=abs(p_warp)/dot(p_warp,p_warp)-.8+sin(time*0.2)*0.1;}return hsv2rgb(vec3(fract(p_warp.x*.2),1.,1.));}
    if(p_int==16){vec2 st=floor(face_uv/10.*(5.+controls.w*20.));float h=hash11(st.x+st.y*157.);float on=step(0.5,fract(h*10.+time*h));return vec3(on)*hsv2rgb(vec3(fract(h*3.),1.,1.));}
    return vec3(0.8);
}

// GLSL 1.20 polyfill: transpose not available
mat3 _transpose(mat3 m) {
    return mat3(
        m[0][0], m[1][0], m[2][0],
        m[0][1], m[1][1], m[2][1],
        m[0][2], m[1][2], m[2][2]
    );
}

// --- FXAA Implementation by @XorDev ---
vec4 fxaa(sampler2D tex,vec2 uv,vec2 r){const float m=8.,n=1./128.,o=1./32.;const vec3 l=vec3(0.299,0.587,0.114);vec3 c=texture2D(tex,uv).rgb,p=texture2D(tex,uv+vec2(-.5,-.5)*r).rgb,q=texture2D(tex,uv+vec2(.5,-.5)*r).rgb,s=texture2D(tex,uv+vec2(-.5,.5)*r).rgb,v=texture2D(tex,uv+vec2(.5,.5)*r).rgb;float d=dot(c,l),e=dot(p,l),f=dot(q,l),g=dot(s,l),h=dot(v,l);vec2 j=vec2((g+h)-(e+f),(e+g)-(f+h));float k=max((e+f+g+h)*o,n),a=1./(min(abs(j.x),abs(j.y))+k);j=clamp(j*a,-m,m)*r;vec4 A=.5*(texture2D(tex,uv-j*(1./6.))+texture2D(tex,uv+j*(1./6.))),B=A*.5+.25*(texture2D(tex,uv-j*.5)+texture2D(tex,uv+j*.5));float b=min(d,min(min(e,f),min(g,h))),i=max(d,max(max(e,f),max(g,h)));return dot(B.rgb,l)<b||dot(B.rgb,l)>i?A:B;}

void main() {
    initFaceData();
    if (PASSINDEX == 0) { // Time & Rotation Angle Buffer
        vec4 prevTime = IMG_NORM_PIXEL(timeBuffer, vec2(0.5));
        vec4 rotSpeeds = IMG_NORM_PIXEL(rotationBuffer, vec2(0.5));
        
        float angleX = prevTime.r + rotSpeeds.r * TIMEDELTA;
        float angleY = prevTime.g + rotSpeeds.g * TIMEDELTA;
        float angleZ = prevTime.b + rotSpeeds.b * TIMEDELTA;
        float colorTime = prevTime.a + rotSpeeds.a * TIMEDELTA;

        if(FRAMEINDEX == 0) {
            angleX = angleY = angleZ = colorTime = startTime;
        }
        gl_FragColor = vec4(angleX,angleY,angleZ,colorTime);
    }
    else if (PASSINDEX == 1) { // Color Palette Buffer
        gl_FragColor = vec4(float(colorPalette), 0.0, 0.0, 1.0);
    }
    else if (PASSINDEX == 2) { // Controls Buffer (Brightness, Pattern Scale, Complexity)
        float smoothness = min(1.0, TIMEDELTA * colorDamping);
        vec4 prevVal = IMG_NORM_PIXEL(controlsBuffer, vec2(0.5));
        vec4 targetVal = vec4(colorBrightness,patternScale,patternComplexity,0.0);
        gl_FragColor = (FRAMEINDEX == 0) ? targetVal : mix(prevVal, targetVal, smoothness);
    }
    else if (PASSINDEX == 3) { // Rotation & Color Speed Buffer
        float smoothness = min(1.0, TIMEDELTA * rotationDamping);
        vec4 prevVal = IMG_NORM_PIXEL(rotationBuffer, vec2(0.5));
        vec4 targetVal = vec4(rotX,rotY,rotZ,colorAnimSpeed);
        gl_FragColor = (FRAMEINDEX == 0) ? targetVal : mix(prevVal, targetVal, smoothness);
    }
    else if (PASSINDEX == 4) { // Scale Buffer
        float smoothness = min(1.0, TIMEDELTA * scaleTwistDamping);
        vec4 prevVal = IMG_NORM_PIXEL(scaleBuffer, vec2(0.5));
        vec4 targetVal = vec4(scaleX,scaleY,scaleZ,1.0);
        gl_FragColor = (FRAMEINDEX == 0) ? targetVal : mix(prevVal, targetVal, smoothness);
    }
    else if (PASSINDEX == 5) { // Twist Buffer
        float smoothness = min(1.0, TIMEDELTA * scaleTwistDamping);
        vec4 prevVal = IMG_NORM_PIXEL(twistBuffer, vec2(0.5));
        vec4 targetVal = vec4(twistX,twistY,twistZ,0.0);
        gl_FragColor = (FRAMEINDEX == 0) ? targetVal : mix(prevVal, targetVal, smoothness);
    }
    else if (PASSINDEX == 6) { // Scene Render
        // Get smoothed animation values from buffers
        vec4 timeData = IMG_NORM_PIXEL(timeBuffer, vec2(0.5));
        float paletteIndex = IMG_NORM_PIXEL(colorBuffer, vec2(0.5)).r;
        vec4 controls = IMG_NORM_PIXEL(controlsBuffer, vec2(0.5));
        vec3 scales = IMG_NORM_PIXEL(scaleBuffer, vec2(0.5)).xyz;
        vec3 twists = IMG_NORM_PIXEL(twistBuffer, vec2(0.5)).xyz;

        // Setup camera ray
        vec2 uv = (gl_FragCoord.xy - 0.5 * RENDERSIZE.xy) / RENDERSIZE.y;
        vec3 ro = vec3(0.0,0.0,-20.0);
        vec3 rd = normalize(vec3(uv,1.0));

        // Build transformation matrices
        mat3 rotM = rotationX(timeData.r) * rotationY(timeData.g) * rotationZ(timeData.b);
        mat3 rotM_inv = _transpose(rotM); // Inverse of orthogonal matrix is its transpose

        // Transform ray into object space (inverse scale, inverse rotate)
        vec3 invScale = 1.0 / scales;
        vec3 ro_obj = ro * rotM_inv * invScale;
        vec3 rd_obj = normalize(rd * rotM_inv * invScale);

        // Intersect with voxel cube in its local, untransformed space
        vec3 p_hit_obj, n_hit_obj;
        float v_hit;
        float t = intersectVoxelCube(ro_obj, rd_obj, p_hit_obj, n_hit_obj, v_hit, 0.0);
        
        vec3 col = vec3(0.0);
        if (t > 0.0) {
            // Transform normal to world space for lighting
            vec3 n_hit_world = normalize(n_hit_obj * rotM);
            
            // Create a texture coordinate from the hit point and apply transformations
            // This makes the color patterns twist and warp with the cube
            vec3 p_texture = twist(p_hit_obj, twists);

            // Calculate lighting
            vec3 lightDir = normalize(vec3(0.5,0.8,-1.0));
            float diffuse = max(0.0, dot(n_hit_world, lightDir)) * 0.7 + 0.3;

            // Get the raw color from the palette function
            // We pass a vec4 to conform to the original function: (dummy, brightness, scale, complexity)
            vec4 color_controls = vec4(0.0,controls.x,controls.y,controls.z);
            vec3 raw_col = getColor(int(paletteIndex + 0.5), timeData.a, p_texture, n_hit_world, t, uv, color_controls, rd);
            
            // Apply lighting and brightness
            col = raw_col * diffuse * controls.x;
        }

        gl_FragColor = vec4(aces_approx(col), 1.0);
    }
    else { // Final Pass with FXAA
        gl_FragColor = fxaa(sceneBuffer, isf_FragNormCoord, sqrt(2.0) / RENDERSIZE.xy);
    }
}
