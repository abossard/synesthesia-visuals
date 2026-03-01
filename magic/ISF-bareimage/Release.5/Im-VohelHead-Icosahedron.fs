/*{
    "DESCRIPTION": "A raymarched icosahedron containing an animated voxel cube, with a Voronoi-patterned floor. Features smooth, time-independent animation speed and parameter transitions. Controllable position and rotation. For helping with  array fillup, use this webapp https://github.com/bareimage/ISF/blob/main/Misc/VoxelArrayBuilder.html",
    "CREDIT": "Original by @dot2dot (bareimage). ISF 2.0 Conversion by @dot2dot (bareimage)",
    "ISFVSN": "2.0",
    "CATEGORIES": [
        "GENERATOR"
    ],
    "INPUTS": [
        {
            "NAME": "speed",
            "TYPE": "float",
            "DEFAULT": 0.5,
            "MIN": 0.0,
            "MAX": 50.0,
            "LABEL": "Animation Speed"
        },
        {
            "NAME": "polyhedronSize",
            "TYPE": "float",
            "DEFAULT": 3.5,
            "MIN": 1.0,
            "MAX": 10.0,
            "LABEL": "Icosahedron Size"
        },
        {
            "NAME": "objectY",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": -5.0,
            "MAX": 10.0,
            "LABEL": "Object Y Position"
        },
        {
            "NAME": "voxelWorldSize",
            "TYPE": "float",
            "DEFAULT": 2.5,
            "MIN": 0.5,
            "MAX": 5.0,
            "LABEL": "Voxel Cube Size"
        },
        {
            "NAME": "colorModifier",
            "TYPE": "float",
            "DEFAULT": 0.2,
            "MIN": 0.0,
            "MAX": 1.0,
            "LABEL": "Voxel Color Pulsation"
        },
        {
            "NAME": "glowIntensity",
            "TYPE": "float",
            "DEFAULT": 1.0,
            "MIN": 0.0,
            "MAX": 5.0,
            "LABEL": "Outer Glow Intensity"
        },
        {
            "NAME": "rotX",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": -3.14159,
            "MAX": 3.14159,
            "LABEL": "Icosahedron Rotation X"
        },
        {
            "NAME": "rotY",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": -3.14159,
            "MAX": 3.14159,
            "LABEL": "Icosahedron Rotation Y"
        },
        {
            "NAME": "rotZ",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": -3.14159,
            "MAX": 3.14159,
            "LABEL": "Icosahedron Rotation Z"
        },
        {
            "NAME": "cameraPan",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": -180.0,
            "MAX": 180.0,
            "LABEL": "Camera Pan"
        },
        {
            "NAME": "cameraTilt",
            "TYPE": "float",
            "DEFAULT": 20.0,
            "MIN": -89.0,
            "MAX": 89.0,
            "LABEL": "Camera Tilt"
        },
        {
            "NAME": "cameraHeight",
            "TYPE": "float",
            "DEFAULT": 0.0,
            "MIN": -10.0,
            "MAX": 10.0,
            "LABEL": "Camera Height"
        },
        {
            "NAME": "cameraDistance",
            "TYPE": "float",
            "DEFAULT": 15.0,
            "MIN": 5.0,
            "MAX": 40.0,
            "LABEL": "Camera Distance"
        },
        {
            "NAME": "transitionSpeed",
            "TYPE": "float",
            "DEFAULT": 2.0,
            "MIN": 0.1,
            "MAX": 10.0,
            "LABEL": "Parameter Smoothing"
        }
    ],
    "PASSES": [
        {
            "TARGET": "timeBuffer",
            "PERSISTENT": true,
            "FLOAT": true,
            "WIDTH": 1,
            "HEIGHT": 1
        },
        {
            "TARGET": "paramBuffer",
            "PERSISTENT": true,
            "FLOAT": true,
            "WIDTH": 1,
            "HEIGHT": 1
        },
        {
            "TARGET": "transformBuffer",
            "PERSISTENT": true,
            "FLOAT": true,
            "WIDTH": 1,
            "HEIGHT": 1
        },
        {
            "TARGET": "cameraBuffer",
            "PERSISTENT": true,
            "FLOAT": true,
            "WIDTH": 1,
            "HEIGHT": 1
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

// --- Constants and Macros ---
#define PI 3.14159265359
#define TAU (2.0*PI)
#define ROT(a) mat2(cos(a), sin(a), -sin(a), cos(a))
#define EPS 0.001

// --- Voxel Cube Data (13x13 Faces) ---
float faceFront[169];
float faceBack[169];
float faceTop[169];
float faceBottom[169];
float faceLeft[169];
float faceRight[169];
void initFaceData() {
    faceFront[0]=1.0;
    faceFront[1]=1.0;
    faceFront[2]=1.0;
    faceFront[3]=1.0;
    faceFront[4]=1.0;
    faceFront[5]=1.0;
    faceFront[6]=1.0;
    faceFront[7]=1.0;
    faceFront[8]=1.0;
    faceFront[9]=1.0;
    faceFront[10]=1.0;
    faceFront[11]=1.0;
    faceFront[12]=1.0;
    faceFront[13]=1.0;
    faceFront[14]=0.0;
    faceFront[15]=0.0;
    faceFront[16]=0.0;
    faceFront[17]=0.0;
    faceFront[18]=0.0;
    faceFront[19]=0.0;
    faceFront[20]=0.0;
    faceFront[21]=0.0;
    faceFront[22]=0.0;
    faceFront[23]=0.0;
    faceFront[24]=0.0;
    faceFront[25]=1.0;
    faceFront[26]=1.0;
    faceFront[27]=1.0;
    faceFront[28]=1.0;
    faceFront[29]=1.0;
    faceFront[30]=1.0;
    faceFront[31]=1.0;
    faceFront[32]=1.0;
    faceFront[33]=1.0;
    faceFront[34]=1.0;
    faceFront[35]=1.0;
    faceFront[36]=1.0;
    faceFront[37]=0.0;
    faceFront[38]=1.0;
    faceFront[39]=1.0;
    faceFront[40]=0.0;
    faceFront[41]=0.0;
    faceFront[42]=0.0;
    faceFront[43]=0.0;
    faceFront[44]=0.0;
    faceFront[45]=0.0;
    faceFront[46]=0.0;
    faceFront[47]=0.0;
    faceFront[48]=0.0;
    faceFront[49]=1.0;
    faceFront[50]=0.0;
    faceFront[51]=1.0;
    faceFront[52]=1.0;
    faceFront[53]=0.0;
    faceFront[54]=1.0;
    faceFront[55]=1.0;
    faceFront[56]=1.0;
    faceFront[57]=1.0;
    faceFront[58]=1.0;
    faceFront[59]=1.0;
    faceFront[60]=1.0;
    faceFront[61]=0.0;
    faceFront[62]=1.0;
    faceFront[63]=0.0;
    faceFront[64]=1.0;
    faceFront[65]=1.0;
    faceFront[66]=0.0;
    faceFront[67]=1.0;
    faceFront[68]=0.0;
    faceFront[69]=0.0;
    faceFront[70]=0.0;
    faceFront[71]=0.0;
    faceFront[72]=0.0;
    faceFront[73]=1.0;
    faceFront[74]=0.0;
    faceFront[75]=1.0;
    faceFront[76]=0.0;
    faceFront[77]=1.0;
    faceFront[78]=1.0;
    faceFront[79]=0.0;
    faceFront[80]=1.0;
    faceFront[81]=0.0;
    faceFront[82]=1.0;
    faceFront[83]=1.0;
    faceFront[84]=1.0;
    faceFront[85]=0.0;
    faceFront[86]=1.0;
    faceFront[87]=0.0;
    faceFront[88]=1.0;
    faceFront[89]=0.0;
    faceFront[90]=1.0;
    faceFront[91]=1.0;
    faceFront[92]=0.0;
    faceFront[93]=1.0;
    faceFront[94]=0.0;
    faceFront[95]=1.0;
    faceFront[96]=0.0;
    faceFront[97]=0.0;
    faceFront[98]=0.0;
    faceFront[99]=1.0;
    faceFront[100]=0.0;
    faceFront[101]=1.0;
    faceFront[102]=0.0;
    faceFront[103]=1.0;
    faceFront[104]=1.0;
    faceFront[105]=0.0;
    faceFront[106]=1.0;
    faceFront[107]=0.0;
    faceFront[108]=1.0;
    faceFront[109]=1.0;
    faceFront[110]=1.0;
    faceFront[111]=1.0;
    faceFront[112]=1.0;
    faceFront[113]=0.0;
    faceFront[114]=1.0;
    faceFront[115]=0.0;
    faceFront[116]=1.0;
    faceFront[117]=1.0;
    faceFront[118]=0.0;
    faceFront[119]=1.0;
    faceFront[120]=0.0;
    faceFront[121]=0.0;
    faceFront[122]=0.0;
    faceFront[123]=0.0;
    faceFront[124]=0.0;
    faceFront[125]=0.0;
    faceFront[126]=0.0;
    faceFront[127]=1.0;
    faceFront[128]=0.0;
    faceFront[129]=1.0;
    faceFront[130]=1.0;
    faceFront[131]=0.0;
    faceFront[132]=1.0;
    faceFront[133]=1.0;
    faceFront[134]=1.0;
    faceFront[135]=1.0;
    faceFront[136]=1.0;
    faceFront[137]=1.0;
    faceFront[138]=1.0;
    faceFront[139]=1.0;
    faceFront[140]=1.0;
    faceFront[141]=0.0;
    faceFront[142]=1.0;
    faceFront[143]=1.0;
    faceFront[144]=0.0;
    faceFront[145]=0.0;
    faceFront[146]=0.0;
    faceFront[147]=0.0;
    faceFront[148]=0.0;
    faceFront[149]=0.0;
    faceFront[150]=0.0;
    faceFront[151]=0.0;
    faceFront[152]=0.0;
    faceFront[153]=0.0;
    faceFront[154]=0.0;
    faceFront[155]=1.0;
    faceFront[156]=1.0;
    faceFront[157]=1.0;
    faceFront[158]=1.0;
    faceFront[159]=1.0;
    faceFront[160]=1.0;
    faceFront[161]=1.0;
    faceFront[162]=1.0;
    faceFront[163]=1.0;
    faceFront[164]=1.0;
    faceFront[165]=1.0;
    faceFront[166]=1.0;
    faceFront[167]=1.0;
    faceFront[168]=1.0;
    faceBack[0]=1.0;
    faceBack[1]=1.0;
    faceBack[2]=1.0;
    faceBack[3]=1.0;
    faceBack[4]=1.0;
    faceBack[5]=1.0;
    faceBack[6]=1.0;
    faceBack[7]=1.0;
    faceBack[8]=1.0;
    faceBack[9]=1.0;
    faceBack[10]=1.0;
    faceBack[11]=1.0;
    faceBack[12]=1.0;
    faceBack[13]=1.0;
    faceBack[14]=1.0;
    faceBack[15]=1.0;
    faceBack[16]=1.0;
    faceBack[17]=1.0;
    faceBack[18]=1.0;
    faceBack[19]=1.0;
    faceBack[20]=1.0;
    faceBack[21]=1.0;
    faceBack[22]=1.0;
    faceBack[23]=1.0;
    faceBack[24]=1.0;
    faceBack[25]=1.0;
    faceBack[26]=1.0;
    faceBack[27]=1.0;
    faceBack[28]=0.0;
    faceBack[29]=0.0;
    faceBack[30]=0.0;
    faceBack[31]=1.0;
    faceBack[32]=0.0;
    faceBack[33]=1.0;
    faceBack[34]=0.0;
    faceBack[35]=0.0;
    faceBack[36]=0.0;
    faceBack[37]=1.0;
    faceBack[38]=1.0;
    faceBack[39]=1.0;
    faceBack[40]=1.0;
    faceBack[41]=0.0;
    faceBack[42]=1.0;
    faceBack[43]=0.0;
    faceBack[44]=1.0;
    faceBack[45]=0.0;
    faceBack[46]=1.0;
    faceBack[47]=0.0;
    faceBack[48]=1.0;
    faceBack[49]=0.0;
    faceBack[50]=1.0;
    faceBack[51]=1.0;
    faceBack[52]=1.0;
    faceBack[53]=1.0;
    faceBack[54]=1.0;
    faceBack[55]=1.0;
    faceBack[56]=1.0;
    faceBack[57]=1.0;
    faceBack[58]=0.0;
    faceBack[59]=1.0;
    faceBack[60]=1.0;
    faceBack[61]=1.0;
    faceBack[62]=1.0;
    faceBack[63]=1.0;
    faceBack[64]=1.0;
    faceBack[65]=1.0;
    faceBack[66]=0.0;
    faceBack[67]=0.0;
    faceBack[68]=1.0;
    faceBack[69]=1.0;
    faceBack[70]=1.0;
    faceBack[71]=0.0;
    faceBack[72]=1.0;
    faceBack[73]=1.0;
    faceBack[74]=1.0;
    faceBack[75]=0.0;
    faceBack[76]=0.0;
    faceBack[77]=1.0;
    faceBack[78]=1.0;
    faceBack[79]=1.0;
    faceBack[80]=1.0;
    faceBack[81]=1.0;
    faceBack[82]=1.0;
    faceBack[83]=0.0;
    faceBack[84]=0.0;
    faceBack[85]=0.0;
    faceBack[86]=1.0;
    faceBack[87]=1.0;
    faceBack[88]=1.0;
    faceBack[89]=1.0;
    faceBack[90]=1.0;
    faceBack[91]=1.0;
    faceBack[92]=1.0;
    faceBack[93]=0.0;
    faceBack[94]=1.0;
    faceBack[95]=1.0;
    faceBack[96]=1.0;
    faceBack[97]=1.0;
    faceBack[98]=1.0;
    faceBack[99]=1.0;
    faceBack[100]=1.0;
    faceBack[101]=0.0;
    faceBack[102]=1.0;
    faceBack[103]=1.0;
    faceBack[104]=1.0;
    faceBack[105]=1.0;
    faceBack[106]=1.0;
    faceBack[107]=1.0;
    faceBack[108]=0.0;
    faceBack[109]=0.0;
    faceBack[110]=0.0;
    faceBack[111]=0.0;
    faceBack[112]=0.0;
    faceBack[113]=1.0;
    faceBack[114]=1.0;
    faceBack[115]=1.0;
    faceBack[116]=1.0;
    faceBack[117]=1.0;
    faceBack[118]=1.0;
    faceBack[119]=0.0;
    faceBack[120]=1.0;
    faceBack[121]=0.0;
    faceBack[122]=1.0;
    faceBack[123]=1.0;
    faceBack[124]=1.0;
    faceBack[125]=0.0;
    faceBack[126]=1.0;
    faceBack[127]=0.0;
    faceBack[128]=1.0;
    faceBack[129]=1.0;
    faceBack[130]=1.0;
    faceBack[131]=1.0;
    faceBack[132]=0.0;
    faceBack[133]=1.0;
    faceBack[134]=0.0;
    faceBack[135]=0.0;
    faceBack[136]=0.0;
    faceBack[137]=0.0;
    faceBack[138]=0.0;
    faceBack[139]=1.0;
    faceBack[140]=0.0;
    faceBack[141]=1.0;
    faceBack[142]=1.0;
    faceBack[143]=1.0;
    faceBack[144]=0.0;
    faceBack[145]=0.0;
    faceBack[146]=1.0;
    faceBack[147]=1.0;
    faceBack[148]=1.0;
    faceBack[149]=1.0;
    faceBack[150]=1.0;
    faceBack[151]=1.0;
    faceBack[152]=1.0;
    faceBack[153]=0.0;
    faceBack[154]=0.0;
    faceBack[155]=1.0;
    faceBack[156]=1.0;
    faceBack[157]=1.0;
    faceBack[158]=1.0;
    faceBack[159]=1.0;
    faceBack[160]=1.0;
    faceBack[161]=1.0;
    faceBack[162]=1.0;
    faceBack[163]=1.0;
    faceBack[164]=1.0;
    faceBack[165]=1.0;
    faceBack[166]=1.0;
    faceBack[167]=1.0;
    faceBack[168]=1.0;
    faceTop[0]=1.0;
    faceTop[1]=1.0;
    faceTop[2]=1.0;
    faceTop[3]=1.0;
    faceTop[4]=1.0;
    faceTop[5]=1.0;
    faceTop[6]=1.0;
    faceTop[7]=1.0;
    faceTop[8]=1.0;
    faceTop[9]=1.0;
    faceTop[10]=1.0;
    faceTop[11]=1.0;
    faceTop[12]=1.0;
    faceTop[13]=1.0;
    faceTop[14]=1.0;
    faceTop[15]=0.0;
    faceTop[16]=1.0;
    faceTop[17]=1.0;
    faceTop[18]=1.0;
    faceTop[19]=1.0;
    faceTop[20]=1.0;
    faceTop[21]=1.0;
    faceTop[22]=1.0;
    faceTop[23]=0.0;
    faceTop[24]=1.0;
    faceTop[25]=1.0;
    faceTop[26]=1.0;
    faceTop[27]=1.0;
    faceTop[28]=0.0;
    faceTop[29]=0.0;
    faceTop[30]=0.0;
    faceTop[31]=1.0;
    faceTop[32]=0.0;
    faceTop[33]=1.0;
    faceTop[34]=0.0;
    faceTop[35]=0.0;
    faceTop[36]=0.0;
    faceTop[37]=1.0;
    faceTop[38]=1.0;
    faceTop[39]=1.0;
    faceTop[40]=1.0;
    faceTop[41]=1.0;
    faceTop[42]=1.0;
    faceTop[43]=0.0;
    faceTop[44]=1.0;
    faceTop[45]=0.0;
    faceTop[46]=1.0;
    faceTop[47]=0.0;
    faceTop[48]=1.0;
    faceTop[49]=1.0;
    faceTop[50]=1.0;
    faceTop[51]=1.0;
    faceTop[52]=1.0;
    faceTop[53]=1.0;
    faceTop[54]=1.0;
    faceTop[55]=1.0;
    faceTop[56]=1.0;
    faceTop[57]=1.0;
    faceTop[58]=0.0;
    faceTop[59]=1.0;
    faceTop[60]=1.0;
    faceTop[61]=1.0;
    faceTop[62]=1.0;
    faceTop[63]=1.0;
    faceTop[64]=1.0;
    faceTop[65]=1.0;
    faceTop[66]=1.0;
    faceTop[67]=0.0;
    faceTop[68]=1.0;
    faceTop[69]=1.0;
    faceTop[70]=1.0;
    faceTop[71]=0.0;
    faceTop[72]=1.0;
    faceTop[73]=1.0;
    faceTop[74]=1.0;
    faceTop[75]=0.0;
    faceTop[76]=1.0;
    faceTop[77]=1.0;
    faceTop[78]=1.0;
    faceTop[79]=0.0;
    faceTop[80]=0.0;
    faceTop[81]=1.0;
    faceTop[82]=1.0;
    faceTop[83]=0.0;
    faceTop[84]=0.0;
    faceTop[85]=0.0;
    faceTop[86]=1.0;
    faceTop[87]=1.0;
    faceTop[88]=0.0;
    faceTop[89]=0.0;
    faceTop[90]=1.0;
    faceTop[91]=1.0;
    faceTop[92]=1.0;
    faceTop[93]=1.0;
    faceTop[94]=1.0;
    faceTop[95]=1.0;
    faceTop[96]=1.0;
    faceTop[97]=1.0;
    faceTop[98]=1.0;
    faceTop[99]=1.0;
    faceTop[100]=1.0;
    faceTop[101]=1.0;
    faceTop[102]=1.0;
    faceTop[103]=1.0;
    faceTop[104]=1.0;
    faceTop[105]=0.0;
    faceTop[106]=1.0;
    faceTop[107]=0.0;
    faceTop[108]=0.0;
    faceTop[109]=0.0;
    faceTop[110]=0.0;
    faceTop[111]=0.0;
    faceTop[112]=0.0;
    faceTop[113]=0.0;
    faceTop[114]=1.0;
    faceTop[115]=1.0;
    faceTop[116]=1.0;
    faceTop[117]=1.0;
    faceTop[118]=1.0;
    faceTop[119]=1.0;
    faceTop[120]=1.0;
    faceTop[121]=0.0;
    faceTop[122]=1.0;
    faceTop[123]=1.0;
    faceTop[124]=1.0;
    faceTop[125]=0.0;
    faceTop[126]=1.0;
    faceTop[127]=1.0;
    faceTop[128]=1.0;
    faceTop[129]=1.0;
    faceTop[130]=1.0;
    faceTop[131]=0.0;
    faceTop[132]=1.0;
    faceTop[133]=1.0;
    faceTop[134]=1.0;
    faceTop[135]=0.0;
    faceTop[136]=0.0;
    faceTop[137]=0.0;
    faceTop[138]=1.0;
    faceTop[139]=1.0;
    faceTop[140]=1.0;
    faceTop[141]=0.0;
    faceTop[142]=1.0;
    faceTop[143]=1.0;
    faceTop[144]=0.0;
    faceTop[145]=0.0;
    faceTop[146]=1.0;
    faceTop[147]=1.0;
    faceTop[148]=1.0;
    faceTop[149]=0.0;
    faceTop[150]=1.0;
    faceTop[151]=1.0;
    faceTop[152]=1.0;
    faceTop[153]=0.0;
    faceTop[154]=0.0;
    faceTop[155]=1.0;
    faceTop[156]=1.0;
    faceTop[157]=1.0;
    faceTop[158]=1.0;
    faceTop[159]=1.0;
    faceTop[160]=1.0;
    faceTop[161]=1.0;
    faceTop[162]=1.0;
    faceTop[163]=1.0;
    faceTop[164]=1.0;
    faceTop[165]=1.0;
    faceTop[166]=1.0;
    faceTop[167]=1.0;
    faceTop[168]=1.0;
    faceBottom[0]=1.0;
    faceBottom[1]=1.0;
    faceBottom[2]=1.0;
    faceBottom[3]=1.0;
    faceBottom[4]=1.0;
    faceBottom[5]=1.0;
    faceBottom[6]=1.0;
    faceBottom[7]=1.0;
    faceBottom[8]=1.0;
    faceBottom[9]=1.0;
    faceBottom[10]=1.0;
    faceBottom[11]=1.0;
    faceBottom[12]=1.0;
    faceBottom[13]=1.0;
    faceBottom[14]=1.0;
    faceBottom[15]=1.0;
    faceBottom[16]=1.0;
    faceBottom[17]=1.0;
    faceBottom[18]=1.0;
    faceBottom[19]=1.0;
    faceBottom[20]=1.0;
    faceBottom[21]=1.0;
    faceBottom[22]=1.0;
    faceBottom[23]=1.0;
    faceBottom[24]=1.0;
    faceBottom[25]=1.0;
    faceBottom[26]=1.0;
    faceBottom[27]=0.0;
    faceBottom[28]=0.0;
    faceBottom[29]=0.0;
    faceBottom[30]=0.0;
    faceBottom[31]=1.0;
    faceBottom[32]=0.0;
    faceBottom[33]=1.0;
    faceBottom[34]=0.0;
    faceBottom[35]=0.0;
    faceBottom[36]=0.0;
    faceBottom[37]=0.0;
    faceBottom[38]=1.0;
    faceBottom[39]=1.0;
    faceBottom[40]=1.0;
    faceBottom[41]=1.0;
    faceBottom[42]=1.0;
    faceBottom[43]=0.0;
    faceBottom[44]=1.0;
    faceBottom[45]=0.0;
    faceBottom[46]=1.0;
    faceBottom[47]=0.0;
    faceBottom[48]=1.0;
    faceBottom[49]=1.0;
    faceBottom[50]=1.0;
    faceBottom[51]=1.0;
    faceBottom[52]=1.0;
    faceBottom[53]=1.0;
    faceBottom[54]=1.0;
    faceBottom[55]=1.0;
    faceBottom[56]=1.0;
    faceBottom[57]=1.0;
    faceBottom[58]=0.0;
    faceBottom[59]=1.0;
    faceBottom[60]=1.0;
    faceBottom[61]=1.0;
    faceBottom[62]=1.0;
    faceBottom[63]=1.0;
    faceBottom[64]=1.0;
    faceBottom[65]=1.0;
    faceBottom[66]=0.0;
    faceBottom[67]=0.0;
    faceBottom[68]=1.0;
    faceBottom[69]=1.0;
    faceBottom[70]=1.0;
    faceBottom[71]=0.0;
    faceBottom[72]=1.0;
    faceBottom[73]=1.0;
    faceBottom[74]=1.0;
    faceBottom[75]=0.0;
    faceBottom[76]=0.0;
    faceBottom[77]=1.0;
    faceBottom[78]=1.0;
    faceBottom[79]=1.0;
    faceBottom[80]=1.0;
    faceBottom[81]=1.0;
    faceBottom[82]=1.0;
    faceBottom[83]=0.0;
    faceBottom[84]=0.0;
    faceBottom[85]=0.0;
    faceBottom[86]=1.0;
    faceBottom[87]=1.0;
    faceBottom[88]=1.0;
    faceBottom[89]=1.0;
    faceBottom[90]=1.0;
    faceBottom[91]=1.0;
    faceBottom[92]=1.0;
    faceBottom[93]=0.0;
    faceBottom[94]=1.0;
    faceBottom[95]=1.0;
    faceBottom[96]=1.0;
    faceBottom[97]=1.0;
    faceBottom[98]=1.0;
    faceBottom[99]=1.0;
    faceBottom[100]=1.0;
    faceBottom[101]=0.0;
    faceBottom[102]=1.0;
    faceBottom[103]=1.0;
    faceBottom[104]=1.0;
    faceBottom[105]=1.0;
    faceBottom[106]=0.0;
    faceBottom[107]=1.0;
    faceBottom[108]=1.0;
    faceBottom[109]=0.0;
    faceBottom[110]=0.0;
    faceBottom[111]=0.0;
    faceBottom[112]=1.0;
    faceBottom[113]=1.0;
    faceBottom[114]=0.0;
    faceBottom[115]=1.0;
    faceBottom[116]=1.0;
    faceBottom[117]=1.0;
    faceBottom[118]=1.0;
    faceBottom[119]=0.0;
    faceBottom[120]=1.0;
    faceBottom[121]=1.0;
    faceBottom[122]=0.0;
    faceBottom[123]=1.0;
    faceBottom[124]=0.0;
    faceBottom[125]=1.0;
    faceBottom[126]=1.0;
    faceBottom[127]=0.0;
    faceBottom[128]=1.0;
    faceBottom[129]=1.0;
    faceBottom[130]=1.0;
    faceBottom[131]=1.0;
    faceBottom[132]=0.0;
    faceBottom[133]=1.0;
    faceBottom[134]=1.0;
    faceBottom[135]=0.0;
    faceBottom[136]=1.0;
    faceBottom[137]=0.0;
    faceBottom[138]=1.0;
    faceBottom[139]=1.0;
    faceBottom[140]=0.0;
    faceBottom[141]=1.0;
    faceBottom[142]=1.0;
    faceBottom[143]=1.0;
    faceBottom[144]=0.0;
    faceBottom[145]=0.0;
    faceBottom[146]=1.0;
    faceBottom[147]=1.0;
    faceBottom[148]=0.0;
    faceBottom[149]=0.0;
    faceBottom[150]=0.0;
    faceBottom[151]=1.0;
    faceBottom[152]=1.0;
    faceBottom[153]=0.0;
    faceBottom[154]=0.0;
    faceBottom[155]=1.0;
    faceBottom[156]=1.0;
    faceBottom[157]=1.0;
    faceBottom[158]=1.0;
    faceBottom[159]=1.0;
    faceBottom[160]=1.0;
    faceBottom[161]=1.0;
    faceBottom[162]=1.0;
    faceBottom[163]=1.0;
    faceBottom[164]=1.0;
    faceBottom[165]=1.0;
    faceBottom[166]=1.0;
    faceBottom[167]=1.0;
    faceBottom[168]=1.0;
    faceLeft[0]=1.0;
    faceLeft[1]=1.0;
    faceLeft[2]=1.0;
    faceLeft[3]=1.0;
    faceLeft[4]=1.0;
    faceLeft[5]=1.0;
    faceLeft[6]=1.0;
    faceLeft[7]=1.0;
    faceLeft[8]=1.0;
    faceLeft[9]=1.0;
    faceLeft[10]=1.0;
    faceLeft[11]=1.0;
    faceLeft[12]=1.0;
    faceLeft[13]=1.0;
    faceLeft[14]=1.0;
    faceLeft[15]=1.0;
    faceLeft[16]=1.0;
    faceLeft[17]=0.0;
    faceLeft[18]=1.0;
    faceLeft[19]=1.0;
    faceLeft[20]=1.0;
    faceLeft[21]=0.0;
    faceLeft[22]=1.0;
    faceLeft[23]=1.0;
    faceLeft[24]=1.0;
    faceLeft[25]=1.0;
    faceLeft[26]=1.0;
    faceLeft[27]=1.0;
    faceLeft[28]=0.0;
    faceLeft[29]=0.0;
    faceLeft[30]=0.0;
    faceLeft[31]=1.0;
    faceLeft[32]=0.0;
    faceLeft[33]=1.0;
    faceLeft[34]=0.0;
    faceLeft[35]=0.0;
    faceLeft[36]=0.0;
    faceLeft[37]=1.0;
    faceLeft[38]=1.0;
    faceLeft[39]=1.0;
    faceLeft[40]=1.0;
    faceLeft[41]=0.0;
    faceLeft[42]=1.0;
    faceLeft[43]=1.0;
    faceLeft[44]=1.0;
    faceLeft[45]=0.0;
    faceLeft[46]=1.0;
    faceLeft[47]=1.0;
    faceLeft[48]=1.0;
    faceLeft[49]=0.0;
    faceLeft[50]=1.0;
    faceLeft[51]=1.0;
    faceLeft[52]=1.0;
    faceLeft[53]=1.0;
    faceLeft[54]=1.0;
    faceLeft[55]=1.0;
    faceLeft[56]=1.0;
    faceLeft[57]=1.0;
    faceLeft[58]=0.0;
    faceLeft[59]=1.0;
    faceLeft[60]=1.0;
    faceLeft[61]=1.0;
    faceLeft[62]=1.0;
    faceLeft[63]=1.0;
    faceLeft[64]=1.0;
    faceLeft[65]=1.0;
    faceLeft[66]=0.0;
    faceLeft[67]=0.0;
    faceLeft[68]=0.0;
    faceLeft[69]=1.0;
    faceLeft[70]=1.0;
    faceLeft[71]=0.0;
    faceLeft[72]=1.0;
    faceLeft[73]=1.0;
    faceLeft[74]=0.0;
    faceLeft[75]=0.0;
    faceLeft[76]=0.0;
    faceLeft[77]=1.0;
    faceLeft[78]=1.0;
    faceLeft[79]=1.0;
    faceLeft[80]=1.0;
    faceLeft[81]=0.0;
    faceLeft[82]=1.0;
    faceLeft[83]=0.0;
    faceLeft[84]=0.0;
    faceLeft[85]=0.0;
    faceLeft[86]=1.0;
    faceLeft[87]=0.0;
    faceLeft[88]=1.0;
    faceLeft[89]=1.0;
    faceLeft[90]=1.0;
    faceLeft[91]=1.0;
    faceLeft[92]=0.0;
    faceLeft[93]=1.0;
    faceLeft[94]=1.0;
    faceLeft[95]=1.0;
    faceLeft[96]=1.0;
    faceLeft[97]=1.0;
    faceLeft[98]=1.0;
    faceLeft[99]=1.0;
    faceLeft[100]=1.0;
    faceLeft[101]=1.0;
    faceLeft[102]=0.0;
    faceLeft[103]=1.0;
    faceLeft[104]=1.0;
    faceLeft[105]=0.0;
    faceLeft[106]=1.0;
    faceLeft[107]=1.0;
    faceLeft[108]=1.0;
    faceLeft[109]=1.0;
    faceLeft[110]=0.0;
    faceLeft[111]=1.0;
    faceLeft[112]=1.0;
    faceLeft[113]=1.0;
    faceLeft[114]=1.0;
    faceLeft[115]=0.0;
    faceLeft[116]=1.0;
    faceLeft[117]=1.0;
    faceLeft[118]=0.0;
    faceLeft[119]=0.0;
    faceLeft[120]=1.0;
    faceLeft[121]=1.0;
    faceLeft[122]=0.0;
    faceLeft[123]=0.0;
    faceLeft[124]=0.0;
    faceLeft[125]=1.0;
    faceLeft[126]=1.0;
    faceLeft[127]=0.0;
    faceLeft[128]=0.0;
    faceLeft[129]=1.0;
    faceLeft[130]=1.0;
    faceLeft[131]=1.0;
    faceLeft[132]=1.0;
    faceLeft[133]=1.0;
    faceLeft[134]=0.0;
    faceLeft[135]=0.0;
    faceLeft[136]=1.0;
    faceLeft[137]=0.0;
    faceLeft[138]=0.0;
    faceLeft[139]=1.0;
    faceLeft[140]=1.0;
    faceLeft[141]=1.0;
    faceLeft[142]=1.0;
    faceLeft[143]=1.0;
    faceLeft[144]=1.0;
    faceLeft[145]=1.0;
    faceLeft[146]=0.0;
    faceLeft[147]=0.0;
    faceLeft[148]=0.0;
    faceLeft[149]=0.0;
    faceLeft[150]=0.0;
    faceLeft[151]=0.0;
    faceLeft[152]=0.0;
    faceLeft[153]=1.0;
    faceLeft[154]=1.0;
    faceLeft[155]=1.0;
    faceLeft[156]=1.0;
    faceLeft[157]=1.0;
    faceLeft[158]=1.0;
    faceLeft[159]=1.0;
    faceLeft[160]=1.0;
    faceLeft[161]=1.0;
    faceLeft[162]=1.0;
    faceLeft[163]=1.0;
    faceLeft[164]=1.0;
    faceLeft[165]=1.0;
    faceLeft[166]=1.0;
    faceLeft[167]=1.0;
    faceLeft[168]=1.0;
    faceRight[0]=1.0;
    faceRight[1]=1.0;
    faceRight[2]=1.0;
    faceRight[3]=1.0;
    faceRight[4]=1.0;
    faceRight[5]=1.0;
    faceRight[6]=1.0;
    faceRight[7]=1.0;
    faceRight[8]=1.0;
    faceRight[9]=1.0;
    faceRight[10]=1.0;
    faceRight[11]=1.0;
    faceRight[12]=1.0;
    faceRight[13]=1.0;
    faceRight[14]=1.0;
    faceRight[15]=1.0;
    faceRight[16]=1.0;
    faceRight[17]=1.0;
    faceRight[18]=1.0;
    faceRight[19]=1.0;
    faceRight[20]=1.0;
    faceRight[21]=1.0;
    faceRight[22]=1.0;
    faceRight[23]=1.0;
    faceRight[24]=1.0;
    faceRight[25]=1.0;
    faceRight[26]=1.0;
    faceRight[27]=1.0;
    faceRight[28]=0.0;
    faceRight[29]=0.0;
    faceRight[30]=0.0;
    faceRight[31]=1.0;
    faceRight[32]=0.0;
    faceRight[33]=1.0;
    faceRight[34]=0.0;
    faceRight[35]=0.0;
    faceRight[36]=0.0;
    faceRight[37]=1.0;
    faceRight[38]=1.0;
    faceRight[39]=1.0;
    faceRight[40]=1.0;
    faceRight[41]=0.0;
    faceRight[42]=1.0;
    faceRight[43]=1.0;
    faceRight[44]=1.0;
    faceRight[45]=0.0;
    faceRight[46]=1.0;
    faceRight[47]=1.0;
    faceRight[48]=1.0;
    faceRight[49]=0.0;
    faceRight[50]=1.0;
    faceRight[51]=1.0;
    faceRight[52]=1.0;
    faceRight[53]=1.0;
    faceRight[54]=0.0;
    faceRight[55]=0.0;
    faceRight[56]=1.0;
    faceRight[57]=1.0;
    faceRight[58]=0.0;
    faceRight[59]=1.0;
    faceRight[60]=1.0;
    faceRight[61]=0.0;
    faceRight[62]=0.0;
    faceRight[63]=1.0;
    faceRight[64]=1.0;
    faceRight[65]=1.0;
    faceRight[66]=1.0;
    faceRight[67]=1.0;
    faceRight[68]=1.0;
    faceRight[69]=1.0;
    faceRight[70]=1.0;
    faceRight[71]=0.0;
    faceRight[72]=1.0;
    faceRight[73]=1.0;
    faceRight[74]=1.0;
    faceRight[75]=1.0;
    faceRight[76]=1.0;
    faceRight[77]=1.0;
    faceRight[78]=1.0;
    faceRight[79]=1.0;
    faceRight[80]=1.0;
    faceRight[81]=0.0;
    faceRight[82]=1.0;
    faceRight[83]=0.0;
    faceRight[84]=0.0;
    faceRight[85]=0.0;
    faceRight[86]=1.0;
    faceRight[87]=0.0;
    faceRight[88]=1.0;
    faceRight[89]=1.0;
    faceRight[90]=1.0;
    faceRight[91]=1.0;
    faceRight[92]=1.0;
    faceRight[93]=1.0;
    faceRight[94]=0.0;
    faceRight[95]=1.0;
    faceRight[96]=1.0;
    faceRight[97]=1.0;
    faceRight[98]=1.0;
    faceRight[99]=1.0;
    faceRight[100]=0.0;
    faceRight[101]=1.0;
    faceRight[102]=1.0;
    faceRight[103]=1.0;
    faceRight[104]=1.0;
    faceRight[105]=0.0;
    faceRight[106]=1.0;
    faceRight[107]=0.0;
    faceRight[108]=1.0;
    faceRight[109]=0.0;
    faceRight[110]=0.0;
    faceRight[111]=0.0;
    faceRight[112]=1.0;
    faceRight[113]=0.0;
    faceRight[114]=1.0;
    faceRight[115]=0.0;
    faceRight[116]=1.0;
    faceRight[117]=1.0;
    faceRight[118]=0.0;
    faceRight[119]=0.0;
    faceRight[120]=0.0;
    faceRight[121]=1.0;
    faceRight[122]=0.0;
    faceRight[123]=0.0;
    faceRight[124]=0.0;
    faceRight[125]=1.0;
    faceRight[126]=0.0;
    faceRight[127]=0.0;
    faceRight[128]=0.0;
    faceRight[129]=1.0;
    faceRight[130]=1.0;
    faceRight[131]=0.0;
    faceRight[132]=1.0;
    faceRight[133]=1.0;
    faceRight[134]=1.0;
    faceRight[135]=1.0;
    faceRight[136]=1.0;
    faceRight[137]=1.0;
    faceRight[138]=1.0;
    faceRight[139]=1.0;
    faceRight[140]=1.0;
    faceRight[141]=0.0;
    faceRight[142]=1.0;
    faceRight[143]=1.0;
    faceRight[144]=1.0;
    faceRight[145]=1.0;
    faceRight[146]=0.0;
    faceRight[147]=0.0;
    faceRight[148]=1.0;
    faceRight[149]=0.0;
    faceRight[150]=1.0;
    faceRight[151]=0.0;
    faceRight[152]=0.0;
    faceRight[153]=1.0;
    faceRight[154]=1.0;
    faceRight[155]=1.0;
    faceRight[156]=1.0;
    faceRight[157]=1.0;
    faceRight[158]=1.0;
    faceRight[159]=1.0;
    faceRight[160]=1.0;
    faceRight[161]=1.0;
    faceRight[162]=1.0;
    faceRight[163]=1.0;
    faceRight[164]=1.0;
    faceRight[165]=1.0;
    faceRight[166]=1.0;
    faceRight[167]=1.0;
    faceRight[168]=1.0;
}

mat3 _transpose(mat3 m) {
    return mat3(
        m[0][0], m[1][0], m[2][0],
        m[0][1], m[1][1], m[2][1],
        m[0][2], m[1][2], m[2][2]
    );
}
// --- Shared Globals (for passing data between functions) ---
mat3 g_rot; // Voxel cube's animation rotation
mat3 g_icosahedronRot;
mat3 g_icosahedronRot_inv;
vec3 g_icosahedronPos; 
vec2 g_glowDistanceShapes;
float g_polyhedronSize;
float g_voxelWorldSize;
float g_colorModifier;

// --- Raymarching Constants ---
const int maxRayMarchesShapes = 70;
const float toleranceShapes = .001;
const float maxRayLengthShapes = 80.0;
const float normalEpsilonShapes= 0.01;
const int maxBouncesInsides = 5;

// --- Forward Declarations ---
float dfShapes(vec3 p);
vec3 renderWorld(vec3 ro, vec3 rd, float time);
vec3 effect(vec2 p, vec2 pp, float time, float glow, vec4 camera_params);

// --- Utility Functions ---
vec3 hsv2rgb_approx(vec3 hsv) {
    return (cos(hsv.x*TAU+vec3(0.,4.,2.))*hsv.y+2.-hsv.y)*hsv.z/2.;
}

vec3 aces_approx(vec3 v) {
    v = max(v, 0.0);
    v *= 0.6;
    float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((v*(a*v+b))/(v*(c*v+d)+e), 0.0, 1.0);
}

mat3 animatedRotationMatrix(float time) {
    float angle1 = time*0.5, angle2 = time*0.707, angle3 = time*0.33;
    float c1=cos(angle1), s1=sin(angle1), c2=cos(angle2), s2=sin(angle2), c3=cos(angle3), s3=sin(angle3);
    return mat3(c1*c2, c1*s2*s3-c3*s1, s1*s3+c1*c3*s2, c2*s1, c1*c3+s1*s2*s3, c3*s1*s2-c1*s3, -s2, c2*s3, c2*c3);
}

mat3 rotationMatrixXYZ(vec3 angles) {
    vec3 c = cos(angles);
    vec3 s = sin(angles);
    mat3 rotX = mat3(1.0, 0.0, 0.0, 0.0, c.x, -s.x, 0.0, s.x, c.x);
    mat3 rotY = mat3(c.y, 0.0, s.y, 0.0, 1.0, 0.0, -s.y, 0.0, c.y);
    mat3 rotZ = mat3(c.z, -s.z, 0.0, s.z, c.z, 0.0, 0.0, 0.0, 1.0);
    return rotZ * rotY * rotX;
}

vec2 hash2( vec2 p ) {
    return fract(sin(vec2(dot(p, vec2(127.1,311.7)), dot(p, vec2(269.5,183.3))))*43758.5453);
}

// --- Voxel Cube Rendering Logic ---
vec3 GetColor(float v) {
    return vec3(0.5) + vec3(0.5)*cos( 6.28318*(vec3(0.6, 0.4, 0.3)*v+vec3(0.6, 0.4, 0.3)) );
}

bool map(in vec3 p, out float v, float time) {
    float CUBE_SIZE = 13.0;
    float last = CUBE_SIZE - 1.0;
    vec2 uv;
    int index = -1;
    float cellValue = 0.0;
    v = sin(time) * g_colorModifier;
    if (p.z > -EPS && p.z < EPS) { uv = p.xy; if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThan(uv, vec2(CUBE_SIZE)))) { index = int(uv.y) * int(CUBE_SIZE) + int(uv.x); cellValue = faceFront[index]; }
    } else if (p.z > last - EPS && p.z < last + EPS) { uv = p.xy; if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThan(uv, vec2(CUBE_SIZE)))) { index = int(uv.y) * int(CUBE_SIZE) + int(uv.x); cellValue = faceBack[index]; }
    } else if (p.y > -EPS && p.y < EPS) { uv = p.xz; if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThan(uv, vec2(CUBE_SIZE)))) { index = int(uv.y) * int(CUBE_SIZE) + int(uv.x); cellValue = faceBottom[index]; }
    } else if (p.y > last - EPS && p.y < last + EPS) { uv = p.xz; if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThan(uv, vec2(CUBE_SIZE)))) { index = int(uv.y) * int(CUBE_SIZE) + int(uv.x); cellValue = faceTop[index]; }
    } else if (p.x > -EPS && p.x < EPS) { uv = p.zy; if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThan(uv, vec2(CUBE_SIZE)))) { index = int(uv.y) * int(CUBE_SIZE) + int(uv.x); cellValue = faceLeft[index]; }
    } else if (p.x > last - EPS && p.x < last + EPS) { uv = p.zy; if (all(greaterThanEqual(uv, vec2(0.0))) && all(lessThan(uv, vec2(CUBE_SIZE)))) { index = int(uv.y) * int(CUBE_SIZE) + int(uv.x); cellValue = faceRight[index]; }
    } return cellValue > 0.5;
}

bool IRayAABox(in vec3 ro, in vec3 rd, in vec3 invrd, in vec3 bmin, in vec3 bmax, out vec3 p0, out vec3 p1) {
    vec3 t0 = (bmin - ro) * invrd; vec3 t1 = (bmax - ro) * invrd;
    vec3 tmin = min(t0, t1); vec3 tmax = max(t0, t1);
    float fmin = max(max(tmin.x, tmin.y), tmin.z); float fmax = min(min(tmax.x, tmax.y), tmax.z);
    p0 = ro + rd*fmin; p1 = ro + rd*fmax;
    return fmax >= fmin;
}

vec3 AABoxNormal(vec3 bmin, vec3 bmax, vec3 p) {
    vec3 c = (bmin + bmax) * 0.5; vec3 d = p - c; vec3 ad = abs(d);
    if (ad.x > ad.y && ad.x > ad.z) return vec3(sign(d.x), 0, 0);
    if (ad.y > ad.z) return vec3(0, sign(d.y), 0);
    return vec3(0, 0, sign(d.z));
}

bool traceVoxelGrid(in vec3 initial_ro, in vec3 rd, in vec3 invrd, in vec3 bmin, in vec3 bmax, out vec3 n, out vec3 p, out float v, float time) {
    n=vec3(0.); p=vec3(0.); v=0.; vec3 current_ro; vec3 exit_point;
    if (!IRayAABox(initial_ro, rd, invrd, bmin, bmax, current_ro, exit_point)) return false;
    if (dot(exit_point - current_ro, rd) < EPS) return false;
    vec3 ep = floor(current_ro + rd*EPS); bool ret = false;
    for (int i = 0; i < 64; ++i) {
        if (map(ep, v, time)) { ret = true; break; }
        vec3 dummy_p0; IRayAABox(current_ro - rd*2.0, rd, invrd, ep, ep+1.0, dummy_p0, current_ro);
        ep = floor(current_ro + rd*EPS);
        if (dot(exit_point - current_ro, rd) < EPS) { ret = false; break; }
    }
    if (ret) { n = AABoxNormal(ep, ep+1.0, current_ro); p = current_ro; }
    return ret;
}

float intersectVoxelCube(in vec3 ro, in vec3 rd, out vec3 p_hit, out vec3 n_hit, out float v_hit, float time) {
    float CUBE_SIZE = 13.0;
    vec3 bmin_world = -vec3(g_voxelWorldSize * 0.5); vec3 bmax_world = vec3(g_voxelWorldSize * 0.5);
    vec3 invrd = 1.0/rd; vec3 p_entry, p_exit;
    if (!IRayAABox(ro, rd, invrd, bmin_world, bmax_world, p_entry, p_exit)) return 1e10;
    vec3 ro_start = p_entry;
    if (dot(p_entry - ro, rd) < 0.0) ro_start = ro;
    vec3 ro_vox = (ro_start - bmin_world) / g_voxelWorldSize * CUBE_SIZE;
    vec3 rd_vox = rd / g_voxelWorldSize * CUBE_SIZE;
    vec3 invrd_vox = 1.0/rd_vox; vec3 n_vox, p_vox;
    vec3 bmin_vox = vec3(0.0); vec3 bmax_vox = vec3(CUBE_SIZE);
    if (traceVoxelGrid(ro_vox, rd_vox, invrd_vox, bmin_vox, bmax_vox, n_vox, p_vox, v_hit, time)) {
        p_hit = bmin_world + (p_vox / CUBE_SIZE) * g_voxelWorldSize;
        n_hit = normalize(n_vox);
        if(distance(ro, p_hit) > distance(ro, p_exit) + EPS) return 1e10;
        return distance(ro, p_hit);
    }
    return 1e10;
}

// --- Main Scene Rendering ---
vec3 voronoi( in vec2 x, float time ) {
    vec2 ip = floor(x); vec2 fp = fract(x);
    vec2 mg, mr; float md = 8.0;
    for( int j=-1; j<=1; j++ ) for( int i=-1; i<=1; i++ ) {
        vec2 g = vec2(float(i),float(j));
        vec2 o = hash2( ip + g );
        o = 0.5 + 0.5*sin( time + TAU*o );
        vec2 r = g + o - fp; float d = dot(r,r);
        if( d<md ) { md = d; mr = r; mg = g; }
    }
    md = 8.0;
    for( int j=-2; j<=2; j++ ) for( int i=-2; i<=2; i++ ) {
        vec2 g = mg + vec2(float(i),float(j));
        vec2 o = hash2( ip + g );
        o = 0.5 + 0.5*sin( time + TAU*o );
        vec2 r = g + o - fp;
        if( dot(mr-r,mr-r)>0.00001 ) md = min( md, dot( 0.5*(mr+r), normalize(r-mr) ) );
    }
    return vec3( md, mr );
}

vec3 renderWorld(vec3 ro, vec3 rd, float time) {
    float bottom = -g_polyhedronSize - 0.5;
    vec3 col = hsv2rgb_approx(vec3(0.6, clamp(0.3+0.9*rd.y,0.0, 1.0), 2.*clamp(2.0-2.*rd.y*rd.y, 0.0, 2.)));
    float bt = -(ro.y-bottom)/(rd.y);
    if (bt > 0.) {
        vec3 bp = ro + rd*bt;
        vec3 v = voronoi(bp.xz * 0.4, time);
        
        vec3 groundCol = hsv2rgb_approx(vec3(0.7, 0.2, 1.5));
        vec3 cellColor = groundCol;
        vec3 borderColor = groundCol * 0.15;
        vec3 bcol = mix(borderColor, cellColor, smoothstep(0.01, 0.015, v.x));
        bcol *= (0.9 + 0.1 * sin(v.x * 50.0));
        
        float bfade = mix(1.,0.2, exp(-0.3*max(bt-15., 0.)));
        bcol *= bfade;
        
        col = mix(col, bcol, exp(-0.008*bt));
    }
    return col;
}

float intersectContainerExit(vec3 ro, vec3 rd) {
    float t = 0.01;
    for(int i=0; i<32; i++) {
        vec3 p = ro + rd * t; float d = dfShapes(p);
        if(d > -toleranceShapes) { return t; }
        t -= d * 0.8;
        if(t > maxRayLengthShapes) break;
    }
    return maxRayLengthShapes;
}

vec3 renderInsides(vec3 ro, vec3 rd, float time) {
    vec3 agg = vec3(0.0); float ragg = 1.0; float tagg = 0.0;
    g_rot = animatedRotationMatrix(sqrt(0.5)*0.5*time);
    mat3 g_rot_inv = _transpose(g_rot);

    float beerHue = 0.75;
    vec3 beerFactor = -hsv2rgb_approx(vec3(beerHue+0.5, 0.75, 1.0));

    for (int bounce = 0; bounce < maxBouncesInsides; ++bounce) {
        if (ragg < 0.1) break;
        
        vec3 ro_ico_space = g_icosahedronRot_inv * (ro - g_icosahedronPos);
        vec3 rd_ico_space = g_icosahedronRot_inv * rd;
        
        vec3 ro_local = g_rot_inv * ro_ico_space;
        vec3 rd_local = g_rot_inv * rd_ico_space;

        vec3 p_voxel, n_voxel;
        float v_voxel;
        float t_voxel = intersectVoxelCube(ro_local, rd_local, p_voxel, n_voxel, v_voxel, time);
        float t_container = intersectContainerExit(ro, rd);
        vec3 beer = ragg * exp(0.1 * beerFactor * tagg);

        if (t_voxel < t_container) {
            tagg += t_voxel;
            vec3 ip = ro + rd * t_voxel;
            
            vec3 in_ = normalize( g_icosahedronRot * (g_rot * n_voxel) );
            vec3 ir = reflect(rd, in_);
            
            float ifre = 1.0 + dot(in_, rd); ifre *= ifre;
            ifre = mix(0.8, 1.0, ifre) * 0.8;
            
            vec3 voxel_color = GetColor(v_voxel);
            agg += voxel_color * beer;
            ragg *= ifre * 0.7;
            
            ro = ip + ir * 0.01;
            rd = ir;
        } else {
            tagg += t_container;
            vec3 ip = ro + rd * t_container;
            
            agg += renderWorld(ip, rd, time) * beer;
            break;
        }
    }
    return agg;
}

float sdIcosahedron(vec3 p, float r) {
    const float phi = 1.6180339887; const float invphi = 0.6180339887;
    p = abs(p);
    
    vec3 n1 = normalize(vec3(1.0, 1.0, 1.0));
    vec3 n2 = normalize(vec3(0.0, invphi, phi));

    float d = dot(p, n1);
    d = max(d, dot(p, n2));
    d = max(d, dot(p, n2.zxy));
    d = max(d, dot(p, n2.yzx));
    
    return d - r;
}

float dfShapes(vec3 p) {
    vec3 p_transformed = g_icosahedronRot_inv * (p - g_icosahedronPos);
    float d = sdIcosahedron(p_transformed, g_polyhedronSize);
    g_glowDistanceShapes = vec2(d);
    return d;
}

float rayMarchShapes(vec3 ro, vec3 rd) {
    float t = 0.0;
    for (int i = 0; i < maxRayMarchesShapes; ++i) {
        float d = dfShapes(ro + rd*t);
        if (d < toleranceShapes || t > maxRayLengthShapes) break;
        t += d;
    }
    return t;
}

vec3 normalShapes(vec3 pos) {
    const vec2 eps = vec2(normalEpsilonShapes, 0.0);
    return normalize(vec3(
        dfShapes(pos+eps.xyy)-dfShapes(pos-eps.xyy),
        dfShapes(pos+eps.yxy)-dfShapes(pos-eps.yxy),
        dfShapes(pos+eps.yyx)-dfShapes(pos-eps.yyx))
    );
}

vec3 renderShapes(vec3 ro, vec3 rd, float time, float glow) {
    float bottom = -g_polyhedronSize - 0.5;
    vec3 col = renderWorld(ro, rd, time);
    float bt = -(ro.y-bottom)/(rd.y);
    vec3 bp = ro+rd*bt;
    float bd = dfShapes(bp);
    g_glowDistanceShapes = vec2(1E3);
    float st = rayMarchShapes(ro, rd);
    float sglowDistance = g_glowDistanceShapes.x;

    if (st < maxRayLengthShapes && (bt < 0.0 || st < bt)) {
        vec3 sp = ro+rd*st;
        vec3 sn = normalShapes(sp);
        float sfre = 1.0 + dot(rd, sn); sfre *= sfre;
        sfre = mix(0.05, 1.0, sfre);
        
        const float eta = 1.0 / 1.8;
        vec3 srr = refract(rd, sn, eta);
        
        float beerHue = 0.75;
        vec3 reflCol = hsv2rgb_approx(vec3(beerHue, 0.33, 0.33));
        vec3 reflected_color = renderWorld(sp, reflect(rd, sn), time) * reflCol;
        
        if (dot(srr, srr) < 0.001) { // Total Internal Reflection
            col = reflected_color;
        } else {
            vec3 refracted_color = renderInsides(sp, srr, time);
            col = mix(refracted_color, reflected_color, sfre);
        }
    } else if (bt > 0.0) {
        col *= mix(1.0, 0.125, exp(-bd));
    }
    
    vec3 outerGlowCol = hsv2rgb_approx(vec3(0.16,0.5,.0002));
    col += outerGlowCol/max(sglowDistance, toleranceShapes) * glow;
    return col;
}

vec3 effect(vec2 p, vec2 pp, float time, float glow, vec4 camera_params) {
    // --- New Camera System ---
    float cam_pan_angle = (time * 4.0) + camera_params.x; // pan, degrees
    float cam_tilt_angle = camera_params.y; // tilt, degrees
    float cam_height = camera_params.z;
    float cam_dist = camera_params.w;

    vec3 la = g_icosahedronPos; // Look at point is now the object's center

    // Calculate camera position using spherical coordinates
    float pan_rad = cam_pan_angle * PI / 180.0;
    float tilt_rad = cam_tilt_angle * PI / 180.0;
    vec3 ro_offset;
    ro_offset.x = cos(tilt_rad) * sin(pan_rad);
    ro_offset.y = sin(tilt_rad);
    ro_offset.z = cos(tilt_rad) * cos(pan_rad);

    vec3 ro = la + ro_offset * cam_dist;
    ro.y += cam_height; // Apply height offset
    
    // Clamp camera to prevent going under floor
    ro.y = max(ro.y, la.y - g_polyhedronSize - 0.4);

    // Standard camera matrix setup
    vec3 ww = normalize(la - ro);
    vec3 uu = normalize(cross(vec3(0.0, 1.0, 0.0), ww ));
    vec3 vv = (cross(ww,uu));
    
    vec3 rd = normalize(-p.x*uu + p.y*vv + 2.0*ww);
    vec3 col = renderShapes(ro, rd, time, glow);

    // Vignette and color grading
    col -= 0.03*vec3(2.0,3.0,1.0)*(length(p)+0.25);
    col *= smoothstep(1.7, 0.8, length(pp));
    col = aces_approx(col);
    col = sqrt(col);
    return col;
}

void main() {
    initFaceData();
    float smoothingFactor = min(1.0, TIMEDELTA * transitionSpeed);

    // --- Pass 0: Time Buffer ---
    if (PASSINDEX == 0) {
        vec4 prevData = IMG_NORM_PIXEL(timeBuffer, vec2(0.5));
        float newTime, adjustedSpeed;
        
        if (FRAMEINDEX == 0) {
            newTime = 0.0;
            adjustedSpeed = speed;
        } else {
            float accumulatedTime = prevData.r;
            float currentSpeed = prevData.g;
            adjustedSpeed = mix(currentSpeed, speed, smoothingFactor);
            newTime = accumulatedTime + adjustedSpeed * TIMEDELTA;
        }
        gl_FragColor = vec4(newTime, adjustedSpeed, 0.0, 1.0);
    }
    // --- Pass 1: General Parameters Buffer ---
    else if (PASSINDEX == 1) {
        vec4 prevParamData = IMG_NORM_PIXEL(paramBuffer, vec2(0.5));
        vec4 currentParams;
        if (FRAMEINDEX == 0) {
            currentParams = vec4(polyhedronSize, voxelWorldSize, colorModifier, glowIntensity);
        } else {
            vec4 targetParams = vec4(polyhedronSize, voxelWorldSize, colorModifier, glowIntensity);
            currentParams = mix(prevParamData, targetParams, smoothingFactor);
        }
        gl_FragColor = currentParams;
    }
    // --- Pass 2: Object Transform Buffer ---
    else if (PASSINDEX == 2) {
        vec4 prevTransformData = IMG_NORM_PIXEL(transformBuffer, vec2(0.5));
        vec4 currentTransforms;
        if (FRAMEINDEX == 0) {
             currentTransforms = vec4(rotX, rotY, rotZ, objectY);
        } else {
            vec4 targetTransforms = vec4(rotX, rotY, rotZ, objectY);
            currentTransforms = mix(prevTransformData, targetTransforms, smoothingFactor);
        }
        gl_FragColor = currentTransforms;
    }
    // --- Pass 3: Camera Parameters Buffer ---
    else if (PASSINDEX == 3) {
        vec4 prevCamData = IMG_NORM_PIXEL(cameraBuffer, vec2(0.5));
        vec4 currentCamData;
        if(FRAMEINDEX == 0) {
            currentCamData = vec4(cameraPan, cameraTilt, cameraHeight, cameraDistance);
        } else {
            vec4 targetCamData = vec4(cameraPan, cameraTilt, cameraHeight, cameraDistance);
            currentCamData = mix(prevCamData, targetCamData, smoothingFactor);
        }
        gl_FragColor = currentCamData;
    }
    // --- Pass 4: Final Render ---
    else {
        // Retrieve smoothed values from all buffers
        vec4 timeData = IMG_NORM_PIXEL(timeBuffer, vec2(0.5));
        vec4 paramData = IMG_NORM_PIXEL(paramBuffer, vec2(0.5));
        vec4 transformData = IMG_NORM_PIXEL(transformBuffer, vec2(0.5));
        vec4 cameraData = IMG_NORM_PIXEL(cameraBuffer, vec2(0.5));

        // Set global object parameters
        g_polyhedronSize = paramData.r;
        g_voxelWorldSize = paramData.g;
        g_colorModifier = paramData.b;
        float effectiveGlow = paramData.a;
        
        // Set global object transformation
        float smoothedObjectY = transformData.w;
        
        // Clamp the object's Y position to prevent it from going through the floor.
        // The floor is at y = -polyhedronSize - 0.5. The object's lowest point is at y - polyhedronSize.
        // So, y - polyhedronSize must be >= -polyhedronSize - 0.5, which simplifies to y >= -0.5.
        smoothedObjectY = max(smoothedObjectY, -0.5);

        g_icosahedronPos = vec3(0.0, smoothedObjectY, 0.0);
        vec3 effectiveRot = transformData.xyz;
        g_icosahedronRot = rotationMatrixXYZ(effectiveRot);
        g_icosahedronRot_inv = _transpose(g_icosahedronRot);

        // Standard coordinate setup
        vec2 q = isf_FragNormCoord.xy;
        vec2 p = -1. + 2. * q;
        vec2 pp = p; // Store original p for vignette
        p.x *= RENDERSIZE.x/RENDERSIZE.y;
        
        // Render the final image
        float effectiveTime = timeData.r;
        vec3 col = effect(p, pp, effectiveTime, effectiveGlow, cameraData);
        
        gl_FragColor = vec4(col, 1.0);
    }
}
