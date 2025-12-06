/*{
 "CREDIT": "by mojovideotech",
 "CATEGORIES" : [
    "generator",
    "equirectangular"
  ],
  "DESCRIPTION" : "",
  "INPUTS" : [
    {
      "NAME" : "rate",
      "TYPE" : "float",
      "MAX" : 3,
      "DEFAULT" : 1,
      "MIN" : -3
    },
    {
      "NAME" : "g1",
      "TYPE" : "float",
      "MAX" : 40,
      "DEFAULT" : 24,
      "MIN" : 4
    },
    {
      "NAME" : "g2",
      "TYPE" : "float",
      "MAX" : 40,
      "DEFAULT" : 16,
      "MIN" : 4
    },
    {
      "NAME" : "rot1",
      "TYPE" : "float",
      "MAX" : 16,
      "DEFAULT" : 8,
      "MIN" : 1
    },
    {
      "NAME" : "rot2",
      "TYPE" : "float",
      "MAX" : 16,
      "DEFAULT" : 4,
      "MIN" : 1
    },
    {
      "NAME" : "colors",
      "TYPE" : "float",
      "MAX" : 10,
      "DEFAULT" : 4,
      "MIN" : 1
    },
    {
      "NAME" :    "flip",
      "TYPE" :    "bool",
      "DEFAULT" :   false
    },
    {
      "NAME" :    "flop",
      "TYPE" :    "bool",
      "DEFAULT" :   false
    }
  ],
  "ISFVSN" : "2"
}
*/

////////////////////////////////////////////////////////////
// Equirec_SpiralIntersect   by mojovideotech
//
// mod of 
// shadertoy.com\/4dyfW1 by iridule
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////


#define   twpi    6.283185307179586   // two pi, 2*pi
#define   pi    3.141592653589793   // pi

#define rotate(a) mat2(cos(a), sin(a), -sin(a), cos(a))
#define spiral(u, a, r, t, d) abs(sin(t + r * length(u) + a * (d * atan(u.y, u.x))))
#define sinp(a) 0.5 + sin(a) * 0.5

void main() 
{
  vec3 col;
  float T = TIME*rate;
  vec2 uv = gl_FragCoord.xy / RENDERSIZE.xy;
  float th = uv.y * pi, ph = uv.x * twpi;
  vec3 st = vec3(sin(th) * cos(ph), -cos(th), sin(th) * sin(ph));
  if (flip) { st.xy = st.yx; }
  if (flop) { st.xz = st.zx; }
 	st.xz *= rotate(-T / rot1);
  st.xy *= rotate(T / rot2);
  vec2 o = vec2(cos(T / rot1), sin(T / rot2));
	for (int i = 0; i < 3; i++) {
		T += 0.3 * spiral(vec2(o + st.zy), g1, 16.0 + 128.0 * o.x - o.y, -T / 100.0, 1.0)
             * spiral(vec2(o - st.xz), g2, 16.0 + 64.0 * o.x - o.y, T / 100.0, -1.0);
		col[i] = sin(colors * T - length(st.xy) * 10.0 * sinp(T));
	}
	gl_FragColor = vec4(col, 1.0); 
}
