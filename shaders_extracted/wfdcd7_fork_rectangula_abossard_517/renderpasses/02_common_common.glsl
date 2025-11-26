// Complex math! Beware that these functions are not all great for overflow,
// even though a GPU is precisely the sort of place where you ought to be 
// *very* concerned about overflow.
//
// This also includes a partial implementation of automatic differentiation
// for complex arithmetic using vec4 as a + bi --> vec4(a, b, da, db). This
// may be used to successfully avoid standard derivatives, though I just
// didn't find it worthwhile when standard derivatives are so easy and well
// supported.

#define PI 3.141592653589793238
#define TO_RADIANS 0.01745329251
#define HALF_PI 1.57079633
#define HALF_PI_INV 0.15915494309
#define PI_INV 0.31830988618
#define TWO_PI 6.28318530718

float hypot (vec2 z) {
  float x = abs(z.x);
  float y = abs(z.y);
  float t = min(x, y);
  x = max(x, y);
  t = t / x;
  return x * sqrt(1.0 + t * t);
}

vec2 cadd (vec2 a, vec2 b) {
  return a + b;
}

vec2 csub (vec2 a, vec2 b) {
  return a - b;
}

float cmod (vec2 z) {
  return hypot(z);
} 

vec2 csqrt (vec2 z) {
  float t = sqrt(2.0 * (cmod(z) + (z.x >= 0.0 ? z.x : -z.x)));
  vec2 f = vec2(0.5 * t, abs(z.y) / t);

  if (z.x < 0.0) f.xy = f.yx;
  if (z.y < 0.0) f.y = -f.y;

  return f;
}

/*
float sinh (float x) {
  return 0.5 * (exp(x) - exp(-x));
}

float cosh (float x) {
  return 0.5 * (exp(x) + exp(-x));
}*/

vec2 sinhcosh (float x) {
  vec2 ex = exp(vec2(x, -x));
  return 0.5 * (ex - vec2(ex.y, -ex.x));
}

float cabs (vec2 z) {
  return cmod(z);
}

vec2 clog(vec2 z) {
  return vec2(
    log(hypot(z)),
    atan(z.y, z.x)
  );
}

vec2 catan (vec2 z) {
  float a = z.x * z.x + (1.0 - z.y) * (1.0 - z.y);
  vec2 b = clog(vec2(1.0 - z.y * z.y - z.x * z.x, -2.0 * z.x) / a);
  return 0.5 * vec2(-b.y, b.x);
} 

vec2 catanh (vec2 z) {
  float oneMinus = 1.0 - z.x;
  float onePlus = 1.0 + z.x;
  float d = oneMinus * oneMinus + z.y * z.y;

  vec2 x = vec2(onePlus * oneMinus - z.y * z.y, z.y * 2.0) / d;

  vec2 result = vec2(log(hypot(x)), atan(x.y, x.x)) * 0.5;

  return result;
} 

vec2 cacos (vec2 z) {
  vec2 a = csqrt(vec2(
    z.y * z.y - z.x * z.x + 1.0,
    -2.0 * z.x * z.y
  ));

  vec2 b = clog(vec2(a.x - z.y, a.y + z.x));
  return vec2(HALF_PI - b.y, b.x);
} 

vec2 cacosh (vec2 z) {
  vec2 a = cacos(z);

  if (a.y <= 0.0) {
    return vec2(-a.y, a.x);
  }

  return vec2(a.y, -a.x);
} 

vec2 cacot (vec2 z) {
  return catan(vec2(z.x, -z.y) / dot(z, z));
} 

vec2 cacoth(vec2 z) {
  return catanh(vec2(z.x, -z.y) / dot(z, z));
} 

vec2 casin (vec2 z) {
  vec2 a = csqrt(vec2(
    z.y * z.y - z.x * z.x + 1.0,
    -2.0 * z.x * z.y
  ));

  vec2 b = clog(vec2(
    a.x - z.y,
    a.y + z.x
  ));

  return vec2(b.y, -b.x);
} 

vec2 casinh (vec2 z) {
  vec2 res = casin(vec2(z.y, -z.x));
  return vec2(-res.y, res.x);
} 

vec2 cacsch(vec2 z) {
  return casinh(vec2(z.x, -z.y) / dot(z, z));
} 

vec2 casec (vec2 z) {
  float d = dot(z, z);
  return cacos(vec2(z.x, -z.y) / dot(z, z));
} 

vec2 casech(vec2 z) {
  return cacosh(vec2(z.x, -z.y) / dot(z, z));
} 

vec2 cconj (vec2 z) {
  return vec2(z.x, -z.y);
} 

vec2 ccos (vec2 z) {
  return sinhcosh(z.y).yx * vec2(cos(z.x), -sin(z.x));
} 

vec2 ccosh (vec2 z) {
  return sinhcosh(z.x).yx * vec2(cos(z.y), sin(z.y));
} 

vec2 ccot (vec2 z) {
  z *= 2.0;
  vec2 sch = sinhcosh(z.y);
  return vec2(-sin(z.x), sch.x) / (cos(z.x) - sch.y);
} 

vec2 ccoth(vec2 z) {
  z *= 2.0;
  vec2 sch = sinhcosh(z.x);
  return vec2(sch.x, -sin(z.y)) / (sch.y - cos(z.y));
} 

vec2 ccsc (vec2 z) {
  float d = 0.25 * (exp(2.0 * z.y) + exp(-2.0 * z.y)) - 0.5 * cos(2.0 * z.x);

  return sinhcosh(z.y).yx * vec2(sin(z.x), -cos(z.x)) / d;
} 

vec2 ccsch (vec2 z) {
  vec2 sch = sinhcosh(z.x);
  float d = cos(2.0 * z.y) - (exp(2.0 * z.x) + exp(-2.0 * z.x)) * 0.5;
  return vec2(-cos(z.y), sin(z.y)) * sch / (0.5 * d);
} 

vec2 cdiv (vec2 a, vec2 b) {
  float e, f;
  float g = 1.0;
  float h = 1.0;

  if( abs(b.x) >= abs(b.y) ) {
    e = b.y / b.x;
    f = b.x + b.y * e;
    h = e;
  } else {
    e = b.x / b.y;
    f = b.x * e + b.y;
    g = e;
  }

  return (a * g + h * vec2(a.y, -a.x)) / f;
} 

vec2 cexp(vec2 z) {
  return vec2(cos(z.y), sin(z.y)) * exp(z.x);
} 

vec2 cinv (vec2 b) {
  float e, f;
  vec2 g = vec2(1, -1);

  if( abs(b.x) >= abs(b.y) ) {
    e = b.y / b.x;
    f = b.x + b.y * e;
    g.y = -e;
  } else {
    e = b.x / b.y;
    f = b.x * e + b.y;
    g.x = e;
  }

  return g / f;
} 

vec2 cmul (vec2 a, vec2 b) {
  return vec2(
    a.x * b.x - a.y * b.y,
    a.y * b.x + a.x * b.y
  );
}

vec2 cmul (vec2 a, vec2 b, vec2 c) {
  return cmul(cmul(a, b), c);
}

vec2 cmul (vec2 a, vec2 b, vec2 c, vec2 d) {
  return cmul(cmul(a, b), cmul(c, d));
}

vec2 cmul (vec2 a, vec2 b, vec2 c, vec2 d, vec2 e) {
  return cmul(cmul(a, b, c), cmul(d, e));
}

vec2 cmul (vec2 a, vec2 b, vec2 c, vec2 d, vec2 e, vec2 f) {
  return cmul(cmul(a, b, c), cmul(d, e, f));
} 

vec2 cpolar (vec2 z) {
  return vec2(
    atan(z.y, z.x),
    hypot(z)
  );
} 

vec2 cpow (vec2 z, float x) {
  float r = hypot(z);
  float theta = atan(z.y, z.x) * x;
  return vec2(cos(theta), sin(theta)) * pow(r, x);
}

vec2 cpow (vec2 a, vec2 b) {
  float aarg = atan(a.y, a.x);
  float amod = hypot(a);

  float theta = log(amod) * b.y + aarg * b.x;

  return vec2(
    cos(theta),
    sin(theta)
  ) * pow(amod, b.x) * exp(-aarg * b.y);
} 

vec2 csec (vec2 z) {
  float d = 0.25 * (exp(2.0 * z.y) + exp(-2.0 * z.y)) + 0.5 * cos(2.0 * z.x);
  return sinhcosh(z.y).yx * vec2(cos(z.x), sin(z.x)) / d;
} 

vec2 csech(vec2 z) {
  float d = cos(2.0 * z.y) + 0.5 * (exp(2.0 * z.x) + exp(-2.0 * z.x));
  vec2 sch = sinhcosh(z.x);

  return vec2(cos(z.y), -sin(z.y)) * sch.yx / (0.5 * d);
} 

vec2 csin (vec2 z) {
  return sinhcosh(z.y).yx * vec2(sin(z.x), cos(z.x));
} 

vec4 csincos (vec2 z) {
  float c = cos(z.x);
  float s = sin(z.x);
  return sinhcosh(z.y).yxyx * vec4(s, c, c, -s);
} 

vec2 csinh (vec2 z) {
  return sinhcosh(z.x) * vec2(cos(z.y), sin(z.y));
} 

vec2 csqr (vec2 z) {
  return vec2(
    z.x * z.x - z.y * z.y,
    2.0 * z.x * z.y
  );
} 

vec2 ctan (vec2 z) {
  vec2 e2iz = cexp(2.0 * vec2(-z.y, z.x));

  return cdiv(
    e2iz - vec2(1, 0),
    vec2(-e2iz.y, 1.0 + e2iz.x)
  );
} 

vec2 ctanh (vec2 z) {
  z *= 2.0;
  vec2 sch = sinhcosh(z.x);
  return vec2(sch.x, sin(z.y)) / (sch.y + cos(z.y));
}


vec4 cmul (vec4 a, vec4 b) {
  return vec4(
    cmul(a.xy, b.xy),
    cmul(a.xy, b.zw) + cmul(a.zw, b.xy)
  );
}

vec4 cmul (vec2 a, vec4 b) {
  return vec4(
    cmul(a.xy, b.xy),
    cmul(a.xy, b.zw)
  );
}

vec4 cmul (vec4 a, vec2 b) {
  return vec4(
    cmul(a.xy, b.xy),
    cmul(a.zw, b.xy)
  );
}

vec4 cmul (vec4 a, vec4 b, vec4 c) { return cmul(cmul(a, b), c); }
vec4 cmul (vec2 a, vec4 b, vec4 c) { return cmul(cmul(a, b), c); }
vec4 cmul (vec4 a, vec2 b, vec4 c) { return cmul(cmul(a, b), c); }
vec4 cmul (vec4 a, vec4 b, vec2 c) { return cmul(cmul(a, b), c); }
vec4 cmul (vec4 a, vec2 b, vec2 c) { return cmul(cmul(a, b), c); }
vec4 cmul (vec2 a, vec4 b, vec2 c) { return cmul(cmul(a, b), c); }
vec4 cmul (vec2 a, vec2 b, vec4 c) { return cmul(cmul(a, b), c); }

vec4 csqr (vec4 a) {
  return vec4(
    csqr(a.xy),
    2.0 * cmul(a.xy, a.zw)
  );
}
vec4 cdiv (vec4 a, vec4 b) {
  return vec4(
    cdiv(a.xy, b.xy),
    cdiv(cmul(b.xy, a.zw) - cmul(a.xy, b.zw), csqr(b.xy))
  );
}

vec4 cdiv (vec2 a, vec4 b) {
  return vec4(
    cdiv(a.xy, b.xy),
    cdiv(-cmul(a.xy, b.zw), csqr(b.xy))
  );
}

vec4 cdiv (vec4 a, vec2 b) {
  return vec4(
    cdiv(a.xy, b.xy),
    cdiv(cmul(b.xy, a.zw), csqr(b.xy))
  );
}

vec4 csub(vec4 a, vec4 b) {
  return a - b;
}

vec4 csub(vec2 a, vec4 b) {
  return vec4(a.xy - b.xy, -b.zw);
}

vec4 csub(vec4 a, vec2 b) {
  return vec4(a.xy - b.xy, a.zw);
}

vec4 cadd(vec4 a, vec4 b) {
  return a + b;
}

vec4 cadd(vec2 a, vec4 b) {
  return vec4(a.xy + b.xy, b.zw);
}

vec4 cadd(vec4 a, vec2 b) {
  return vec4(a.xy + b.xy, a.zw);
}


vec4 cinv(vec4 a) {
  vec2 ainv = cinv(a.xy);
  return vec4(ainv, cmul(a.zw, -csqr(ainv)));
}

vec4 cexp(vec4 a) {
  vec2 expa = cexp(a.xy);
  return vec4(expa, cmul(expa, a.zw));
}

vec4 csqrt(vec4 a) {
  float r = hypot(a.xy);
  float b = sqrt(2.0 * (r + a.x));
  float c = sqrt(2.0 * (r - a.x));
  float re = a.x >= 0.0 ? 0.5 * b : abs(a.y) / c;
  float im = a.x <= 0.0 ? 0.5 * c : abs(a.y) / b;
  vec2 s = vec2(re, a.y < 0.0 ? -im : im);
  return vec4(s, cmul(a.zw, 0.5 * cinv(s)));
}

/*vec4 cpow(vec4 a, float n) {
  float theta = atan(a.y, a.x);
  float r = hypot(a.xy);
  float tn = theta * n;
  float rn = pow(r, n);
  vec2 s = rn * vec2(sin(tn), cos(tn));
  float rn1 = pow(r, n - 1.0);
  float tn1 = theta * (n - 1.0);
  return vec4(s, cmul(a.zw, n * rn1 * vec2(sin(tn1), cos(tn1))));
}*/

vec4 clog(vec4 z) {
  return vec4(
    log(hypot(z.xy)),
    atan(z.y, z.x),
    cdiv(z.zw, z.xy)
  );
}

vec4 csin(vec4 a) {
  vec4 asincos = csincos(a.xy);
  return vec4(asincos.xy, cmul(asincos.zw, a.zw));
}

vec4 ccos(vec4 a) {
  vec4 asincos = csincos(a.xy);
  return vec4(asincos.zw, cmul(-asincos.xy, a.zw));
}

vec4 ctan(vec4 a) {
  return cdiv(csin(a), ccos(a));
}

vec4 casin(vec4 z) {
  vec4 s = clog(vec4(-z.y, z.x, -z.w, z.z) + csqrt(csub(vec2(1, 0), csqr(z))));
  return vec4(s.y, -s.x, s.w, -s.z);
}

vec4 cacos(vec4 z) {
  vec4 s = -casin(z);
  s.x += HALF_PI;
  return s;
}

vec4 catan(vec4 z) {
  vec2 s = clog(cdiv(cadd(vec2(0, 1), z.xy), csub(vec2(0, 1), z.xy)));
  return vec4(
     0.5 * vec2(-s.y, s.x),
     cmul(z.zw, cinv(cadd(vec2(1, 0), csqr(z))))
  );
}

vec4 csinh(vec4 z) {
  vec4 ez = cexp(z);
  return 0.5 * (ez - cinv(ez));
}

vec4 ccosh(vec4 z) {
  vec4 ez = cexp(z);
  return 0.5 * (ez + cinv(ez));
}

vec4 ctanh(vec4 z) {
  vec4 ez = cexp(z);
  vec4 ezinv = cinv(ez);
  return 0.5 * cdiv(ez - ezinv, ez + ezinv);
}

vec4 casinh(vec4 z) {
  return clog(cadd(z, csqrt(cadd(vec2(1, 0), csqr(z)))));
}

vec4 cacosh(vec4 z) {
  return clog(z + cmul(csqrt(cadd(z, vec2(1, 0))), csqrt(csub(z, vec2(1, 0)))));
}

vec4 catanh(vec4 z) {
  return 0.5 * clog(cdiv(cadd(z, vec2(1,  0)), csub(vec2(1, 0), z)));
}

// https://github.com/d3/d3-color
// Copyright 2010-2016 Mike Bostock
// All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification,
// are permitted provided that the following conditions are met:
// 
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// 
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// 
// * Neither the name of the author nor the names of contributors may be used to
//   endorse or promote products derived from this software without specific prior
//   written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
// ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
vec3 cubehelix(vec3 c) {
  vec2 sc = vec2(sin(c.x), cos(c.x));
  return c.z * (1.0 + c.y * (1.0 - c.z) * (
    sc.x * vec3(0.14861, 0.29227, -1.97294) + 
    sc.y * vec3(1.78277, -0.90649, 0.0)
  ));
}

vec3 rainbow(float t) {
  return cubehelix(vec3(
    TWO_PI * t - 1.74533,
    (0.25 * cos(TWO_PI * t) + 0.25) * vec2(-1.5, -0.9) + vec2(1.5, 0.8)
  ));
}
