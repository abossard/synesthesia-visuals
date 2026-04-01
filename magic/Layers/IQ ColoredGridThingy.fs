/*{
  "CREDIT": "by mojovideotech",
  "CATEGORIES": [
    "Patterns"
  ],
  "DESCRIPTION": "Automatically converted from https://www.shadertoy.com/view/4dBSRK by iq.  Some sort of undefined colored grid thingy.",
  "IMPORTED": [],
  "INPUTS": [
    {
      "MAX": [
        2,
        2
      ],
      "MIN": [
        0.01,
        0.01
      ],
      "DEFAULT": [
        1,
        1
      ],
      "NAME": "seed",
      "TYPE": "point2D"
    },
    {
      "NAME": "speed",
      "TYPE": "float",
      "DEFAULT": 1,
      "MIN": 0.5,
      "MAX": 15
    },
    {
      "NAME": "size",
      "TYPE": "float",
      "DEFAULT": 4,
      "MIN": 2,
      "MAX": 20
    }
  ]
}*/

// IQ_ColoredGridThingy by mojovideotech
// source : www.shadertoy.com/view/4dBSRK
// created by IQ : www.iquilezles.org/
// interactive mods by DoctorMojo : www.mojovideotech.com/

///////////////////////////////////

// Created by inigo quilez - iq/2014
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.

void main()
{
    vec2  px = (22.0-size)*(-RENDERSIZE.xy + 2.0*gl_FragCoord.xy) / RENDERSIZE.y;
    
    float id = 0.5 + 0.5*cos(TIME*speed + sin(dot(floor(px+0.5),vec2(113.1*seed.x,17.81)))*43758.545*seed.y);
    
    vec3  co = 0.5 + 0.5*cos(TIME*speed + 3.5*id + vec3(0.0,1.57,3.14) );
    
    vec2  pa = smoothstep( 0.0, 0.2, id*(0.5 + 0.5*cos(6.2831*px)) );
    
    gl_FragColor = vec4( co*pa.x*pa.y, 1.0 );
}