// This file is released under CC0 1.0 Universal (Public Domain Dedication).
// To the extent possible under law, Mårten Rånge has waived all copyright
// and related or neighboring rights to this work.
// See <https://creativecommons.org/publicdomain/zero/1.0/> for details.

// License: WTFPL, author: sam hocevar, found: https://stackoverflow.com/a/17897228/418488
const vec4 hsv2rgb_K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
vec3 hsv2rgb(vec3 c) {
  vec3 p = abs(fract(c.xxx + hsv2rgb_K.xyz) * 6.0 - hsv2rgb_K.www);
  return c.z * mix(hsv2rgb_K.xxx, clamp(p - hsv2rgb_K.xxx, 0.0, 1.0), c.y);
}
// License: WTFPL, author: sam hocevar, found: https://stackoverflow.com/a/17897228/418488
//  Macro version of above to enable compile-time constants
#define HSV2RGB(c)  (c.z * mix(hsv2rgb_K.xxx, clamp(abs(fract(c.xxx + hsv2rgb_K.xyz) * 6.0 - hsv2rgb_K.www) - hsv2rgb_K.xxx, 0.0, 1.0), c.y))

#ifdef KODELIFE
const float
  bar_height    =.15
, bar_visibility=1.0
, hoff          = 0.725
, motion_blur   = 0.25
;

const vec2
  travel_speed=vec2(3,0)
;

const vec3
, sunColor   = HSV2RGB(vec3(hoff+0.0, 0.9, .0005))
, topColor   = HSV2RGB(vec3(hoff+0.0, 0.9, .0001))
, glowColor0 = HSV2RGB(vec3(hoff+0.0, 0.9, .0001))
, glowColor2 = HSV2RGB(vec3(hoff+0.3, .95, .001))
, diffColor  = HSV2RGB(vec3(hoff+0.0, 0.5, .25))
, glowCol1   = HSV2RGB(vec3(hoff+0.2, .85, .0125))
, barCol     = HSV2RGB(vec3(hoff+0.15,.90, 1.))
;
#endif

const float
  TAU                 = 2.*PI
, MAX_RAY_LENGTH_HI   = 60.0
, TOLERANCE_HI        = 1e-4
, MAX_RAY_MARCHES_HI  = 70.
, NORM_OFF            = 5e-3
;

#define ROT(a)              mat2(cos(a), sin(a), -sin(a), cos(a))
#define SCA(a)              vec2(sin(a), cos(a))

#define ROTY(a)               \
  mat3(                       \
    +cos(a) , 0.0 , +sin(a)   \
  , 0.0     , 1.0 , 0.0       \
  , -sin(a) , 0.0 , +cos(a)   \
  )

#define ROTZ(a)               \
  mat3(                       \
    +cos(a) , +sin(a) , 0.0   \
  , -sin(a) , +cos(a) , 0.0   \
  , 0.0     , 0.0     , 1.0   \
  )

#define ROTX(a)               \
  mat3(                       \
    1.0 , 0.0     , 0.0       \
  , 0.0 , +cos(a) , +sin(a)   \
  , 0.0 , -sin(a) , +cos(a)   \
  )


const float
  PERIOD=300.
;

const vec2
  PATHA = (TAU/PERIOD*vec2(3,2))
, PATHB = (vec2(2, 3))
;

const mat2
  R45 = ROT(-PI/4.)
;

const mat3
  rotx = ROTX(radians(-51.8))
, rr0  = rotx
, rr1  = rr0*ROTY(PI/2.0)
;

const vec3
  n0   = normalize(vec3(.0, 0.0, 1.0))*rr0
, c0   = vec3(0.0)
, n1   = normalize(vec3(.0, 0.0, 1.0))*rr1
, c1   = vec3(0.0)
;

const vec4
  dim0 = vec4(n0, -dot(c0, n0))
, dim1 = vec4(n1, -dot(c1, n1))
;

vec3 path(float z) {
  return vec3(sin(z*PATHA)*PATHB, z);
}

vec3 dpath(float z) {
  return vec3(PATHA*PATHB*cos(PATHA*z), 1);
}

vec3 ddpath(float z) {
  return vec3(-PATHA*PATHA*PATHB*sin(PATHA*z), 0);
}

// License: Unknown, author: Claude Brezinski, found: https://mathr.co.uk/blog/2017-09-06_approximating_hyperbolic_tangent.html
float tanh_approx(float x) {
  //  Found this somewhere on the interwebs
  //  return tanh(x);
  float x2 = x*x;
  return clamp(x*(27.0 + x2)/(27.0+9.0*x2), -1.0, 1.0);
}

// License: Unknown, author: Claude Brezinski, found: https://mathr.co.uk/blog/2017-09-06_approximating_hyperbolic_tangent.html
vec3 tanh_approx(vec3 x) {
  //  Found this somewhere on the interwebs
  //  return tanh(x);
  vec3 x2 = x*x;
  return clamp(x*(27.0 + x2)/(27.0+9.0*x2), -1.0, 1.0);
}

float beat() {
#ifdef KODELIFE
  return pow(1.-fract(TIME),2.);
#else
  return tanh_approx(dot(pow(vec2(syn_BassLevel,syn_BassHits), vec2(bass_pow, bass_pow*0.75)), bass_mix));
#endif
}

float freq(float x,float off) {
#ifdef KODELIFE
  return beat()*(.5+.5*sin(99.*x))*2.;
#else
  return texture(syn_Spectrum,abs(x)+off).y;
#endif
}

float wave(float x) {
#ifdef KODELIFE
  return (.5+.25*sin(x*10.+TIME));
#else
  return (texture(syn_Spectrum,x).w-.5)*2.;
#endif
}

void rot(inout vec2 p, float a) {
  float
    c=cos(a)
  , s=sin(a)
  ;
  p=vec2(c*p.x+s*p.y,c*p.y-s*p.x);
}

// License: MIT, author: Inigo Quilez, found: https://www.iquilezles.org/www/articles/smin/smin.htm
float pmin(float a, float b, float k) {
  float h = clamp(0.5+0.5*(b-a)/k, 0.0, 1.0);
  return mix(b, a, h) - k*h*(1.0-h);
}

float pmax(float a, float b, float k) {
  return -pmin(-a, -b, k);
}

float rayPlane(vec3 ro, vec3 rd, vec4 p) {
  return -(dot(ro,p.xyz)+p.w)/dot(rd,p.xyz);
}

float length4(vec2 p) {
  p*=p;
  return sqrt(sqrt(dot(p,p)));
}

float segment(vec2 p) {
  float
    d0=length4(p)
  , d1=abs(p.x)
  ;

  return p.y>=0.?d0:d1;
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/distfunctions/
float flatTorus( vec3 p, vec2 t) {
  p=p.xzy;
  vec2 q = vec2(length(p.xz)-t.x,p.y);
  return length4(q)-t.y;
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/distfunctions/
float cappedTorus(vec3 p, vec2 sc, vec2 t) {
  float
    ra = t.x
  , rb = t.y
  ;
  p.x = abs(p.x);
  float k = (sc.y*p.x>sc.x*p.y) ? dot(p.xy,sc) : length(p.xy);
  return sqrt(dot(p,p) + ra*ra - 2.0*ra*k) - rb;
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/distfunctions2d/
float arc(vec2 p, vec2 sc, float ra, float rb) {
  // sc is the sin/cos of the arc's aperture
  p.x = abs(p.x);
  return ((sc.y*p.x>sc.x*p.y) ? length(p-sc*ra) :
                                abs(length(p)-ra)) - rb;
}

const mat3
  roty      = ROTY(radians(10.0))
, rotline   = transpose(roty)*ROTX(0.027)
;

const vec3
  sunDir     = normalize(vec3(0,-0.01, 1))*roty
, lightPos   = vec3(0, -60, -200)*roty
;

vec2 planeCoord(vec3 p, vec3 c, vec3 up, vec4 dim) {
  vec3
    d = p - c
  , xx = (cross(up,dim.xyz))
  , yy = (cross(xx,dim.xyz))
  ;
  return vec2(dot(d,xx), dot(d,yy));
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/www/articles/distfunctions2d/distfunctions2d.htm
float triIso(vec2 p, vec2 q) {
  p.x = abs(p.x);
  vec2 a = p - q*clamp( dot(p,q)/dot(q,q), 0.0, 1.0 );
  vec2 b = p - q*vec2( clamp( p.x/q.x, 0.0, 1.0 ), 1.0 );
  float s = -sign( q.y );
  vec2 d = min( vec2( dot(a,a), s*(p.x*q.y-p.y*q.x) ),
                vec2( dot(b,b), s*(p.y-q.y)  ));
  return -sqrt(d.x)*sign(d.y);
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/intersectors/
vec2 rayBox(vec3 ro, vec3 rd, vec3 boxSize, out vec3 outNormal)  {
  vec3 m = 1.0/rd; // can precompute if traversing a set of aligned boxes
  vec3 n = m*ro;   // can precompute if traversing a set of aligned boxes
  vec3 k = abs(m)*boxSize;
  vec3 t1 = -n - k;
  vec3 t2 = -n + k;
  float tN = max( max( t1.x, t1.y ), t1.z );
  float tF = min( min( t2.x, t2.y ), t2.z );
  if( tN>tF || tF<0.0) return vec2(-1.0); // no intersection
  outNormal = (tN>0.0) ? step(vec3(tN),t1)  : // ro ouside the box
                         step(t2,vec3(tF))  ;  // ro inside the box
  outNormal *= -sign(rd);
  return vec2( tN, tF );
}

vec3 sky(vec3 ro, vec3 rd) {
  float
    hd = max(abs(rd.y+0.15), 0.00066)
  , i
  ;
  vec3
    col = 0.*sunColor/(1.+1e-5 - dot(sunDir, rd))
  ;

  vec2
    p=vec2(atan(rd.x,rd.z),rd.y+.15)
  , c=p
  , P
  ;
  if (p.y>0.) {
    const float SZ=.05,I=1.;
    float
      n=round(c.x/SZ)
    , d=1e3
    ;
    c.x-=n*SZ;
    for(i=-I;i<=I;++i) {
      P=c;
      P-=vec2(
        i*SZ
      , .2*(freq((n+i)*SZ,SZ))-.25+bar_height
      );
      d=min(d,segment(P)-SZ*.4);
    }

    col+=bar_visibility*1e-3/max(d,1e-3)*(barCol+2.*sqrt(max(0.,-d)));
  }
  
  col += 1e2*inversesqrt(hd)*glowColor0;
  col += glowColor2/hd;

  return col;
}

vec3 glow(vec3 ro, vec3 rd, float beat) {
  vec3
    bn
  , bro = ro
  ;
  bro.y += -1000.0+70.0;
  vec2
    bi = rayBox(bro, rd, vec3(90.0, 1000.0, 90.0), bn)
  ;
  float
    lightDist = distance(lightPos, ro)
  ;
  vec3
    lightDir  = normalize(lightPos-ro)
  ;
  float
    g3        = 1.+1e-5 - dot(lightDir, rd)
  ;

  vec3
    col = 8.*glowColor0/(g3)
  , rrd = rd*rotline
  ;

  if (bi != vec2(-1)) {
    float bdi = tanh_approx(0.00125*(bi.y-bi.x));
    col += 1000.0*glowColor0*(bdi/max(rrd.y, 0.005));
  }

  float sx = abs(rrd.x);
  rrd.y += mix(0.00, 0.0125, beat)*(wave(0.5*sx));
  col += 20.0*glowColor0/(abs(mix(mix(20.0, 0.25, beat)*rrd.y*rrd.y, abs(rrd.y), tanh_approx(4.0*sx)))+mix(2.0, 0.5, beat)*sx*sx*sx+0.0001);

  col *= mix(1.0, 4.0, beat);
  float cm = smoothstep(0.05, 1.0-syn_HighHits*0.0, (dot(col, vec3(1.0))/3.0));
  col += cm*500.0*glowCol1*syn_HighHits*media_opacity*dot(_textureMedia(mix(scale_media*rrd.xy*3.0*vec2(-0.625,1.0)+vec2(0.5), scale_media*rrd.yz*vec2(0.05,1.5)*100.0, media_mode)).rgb, vec3(1.0))/3.0;
  return col;
}

vec3 side(vec3 col, vec3 ro, vec3 rd, float t, vec4 dim, vec3 c) {
  const vec2 tri =vec2(485, sqrt(3.0)*356.0);
  vec3
    n = dim.xyz
  , p = ro + rd*t
  , r = reflect(rd, n)
  , ldiff = p - lightPos
  , ld = normalize(ldiff)
  , rcol0 = sky(p, r)
  ;

  float dcol = max(dot(ld, n), 0.0);
  dcol *= dcol;
  vec2
    pp = planeCoord(p, c, vec3(0, 1, 0), dim)
  , p0 = pp
  , p1 = pp
  ;
  float
    d0 = triIso(p0, tri)
  , d1 = triIso(p1, 0.11*tri)
  , d = d0
  , hf = smoothstep(-600.0, -400.0, p.y)
  ;
  vec3
    bcol = col
  , pcol = 3.0*diffColor*dcol
  ;
  pcol += rcol0;
  pcol = mix(clamp(col, 0.0, 0.1), pcol, hf);
  col = mix(col, pcol, smoothstep(9., 0., d));
  col += topColor/max(0.00005*(d1-1.), 0.000025)*hf;
  return col;
}

vec3 pyramid(vec3 col, vec3 ro, vec3 rd) {
  float
    t0  = rayPlane(ro, rd , dim0)
  , t1  = rayPlane(ro, rd , dim1)
  ;

  if (t1 > 0.0) {
    col = side(col, ro, rd, t1, dim1, c1);
  }
  if (t0 > 0.0) {
    col = side(col, ro, rd, t0, dim0, c0);
  }


  return col;
}

vec2 g_gd;

// License: Unknown, author: Unknown, found: don't remember
float hash(float co) {
  return fract(sin(co*12.9898) * 13758.5453);
}

void warpWorld(inout vec3 p){
  vec3
    warp = path(p.z)
  , dwarp = normalize(dpath(p.z))
  , ddwarp = ddpath(p.z)
  ;
  p.xy -= warp.xy;
  p -= dwarp*dot(vec3(p.xy, 0), dwarp)*0.5*vec3(1,1,-1);
  rot(p.xy,-50.*ddwarp.x);
}

vec2 dfArcs(vec3 p) {
  const vec2
    sc=SCA(PI/16.)
  ;

  vec3
    p1 = p
  ;
  float
    n1 = floor(.25*p1.z+.5)
  , h1 = hash(mod(n1+.125*PERIOD,.25*PERIOD)-.125*PERIOD)
  , sh1 = -1.+2.*h1
  ;
  p1.z-=4.*n1;
  vec3
    p2 = p1
    ;
  rot(p1.xy,.25*TIME*sh1);
  p1.xy = abs(p1.xy);
  p1.xy *= R45;
  float
    d1 = cappedTorus(p1, sc, vec2(3, 0.225))
  , d2 = flatTorus(p2, vec2(3, .09))
  ;

  return vec2(d1, d2);
}

float df(vec3 p, float t) {
  warpWorld(p);
  vec3 p0 = p;
  p0.y -= 3.0;
  p0.y = -p0.y;
  vec2 dd1 = dfArcs(p);
  float
    d0 = arc(p0.xy, SCA(PI/6.0), 6.0, 0.8)
  , d = d0
  ;
  d = pmax(d, 0.25-dd1.y, 0.125);
  d = min(d, dd1.x);
  d = min(d, dd1.y);
  float gd = dd1.x;
  if (gd<g_gd.x) {
    g_gd=vec2(gd,t);
  }

  return d;
}

float df(vec3 p) {
  return df(p,0.);
}

vec3 normal(vec3 pos) {
  vec2  eps = vec2(NORM_OFF,0.0);
  return normalize(vec3(
    df(pos+eps.xyy) - df(pos-eps.xyy)
  , df(pos+eps.yxy) - df(pos-eps.yxy)
  , df(pos+eps.yyx) - df(pos-eps.yyx)
  ));
}

float rayMarch(vec3 ro, vec3 rd, float initt, out float iter) {
  float
    t = initt
  , i
  ;
  for (i = 0.; i < MAX_RAY_MARCHES_HI; ++i) {
    float d = df(ro + rd*t,t);
    if (d < TOLERANCE_HI || t > MAX_RAY_LENGTH_HI) {
      break;
    }
    t += d;
  }
  iter = i;
  return min(t,MAX_RAY_LENGTH_HI);
}


vec3 render0(vec3 ro, vec3 rd, float beat) {
  const
    vec3 ro_ = vec3(0.0, 0.0, -2700.0)*roty
  ;
  const
    mat3 rrd = ROTX(-0.2)
  ;

  rd *= rrd;
  ro = ro_;

  vec3
    glowCol = glow(ro, rd, beat)
  , col = sky(ro, rd)
  ;

  col = pyramid(col, ro, rd);
  col += glowCol;
  col=clamp(col,0.,4.);
  return col;
}

vec3 g_X,g_Y,g_Z;
vec2 toScreenSpace(vec3 ro, vec3 p3) {
  vec3 toPoint = p3 - ro;

  float
    X = dot(toPoint, g_X)
  , Y = dot(toPoint, g_Y)
  , Z = dot(toPoint, g_Z)
  ;

  vec2 p = vec2(
     -2.0 * X / Z
    , 2.0 * Y / Z
  );

  p.x*=RENDERSIZE.y/RENDERSIZE.x;

  vec2 uv = p*.5+.5;

  return uv;

}

vec3 render1(
    vec3 ro
  , vec3 rd
  , vec2 sp
  , vec2 q
  , out float depth
  ) {
  g_gd = vec2(1E3);
  float
    B = beat()
  , iter
  , t = rayMarch(ro, rd, 0.0, iter)
  , hd
  ;
  vec2
    gd=g_gd
  ;
  hd=smoothstep(0.,0.01,gd.x);
  vec3
    ggcol   = glowCol1/(max(gd.x, 1e-3))
  , skyCol  = render0(ro, rd, B)
  , col     = vec3(0)
  , rcol    = vec3(0)
  ;
  ggcol=clamp(ggcol,0.,4.);

  float
    tt = max(t/MAX_RAY_LENGTH_HI-.3,0.)
  , sfo = 1.-exp(-9.*tt*tt)
  ;
  depth=1e3;
  if (t < MAX_RAY_LENGTH_HI) {
    vec3
      p = ro+rd*t
    , n = normal(p)
    , r = reflect(rd, n)
    ;
    depth = p.z-ro.z;
    float
      fre0 = 1.+dot(rd, n)
    , fre  = fre0
    ;
    fre *= fre;

    float
      dif = max(dot(sunDir, n),0.)
    , ao = 1.0-iter/float(MAX_RAY_MARCHES_HI)
    , fo = mix(0.2, 0.5, ao)
    ;

    vec3 wp = p;
    warpWorld(wp);
    vec2 dd = dfArcs(wp);

    float hit = min(dd.x, dd.y);
    if (hit > .05) {
      g_gd = vec2(1E3);
      float
        riter
      , rt = rayMarch(p+.1*n, r, 0.3,riter)
      ;
      vec2
        rgd=g_gd
      ;
      vec3 rggcol = 0.5/(max(rgd.x*rgd.x, 1e-3))*(glowCol1);
      rggcol=clamp(rggcol,0.,4.);
      rcol = rggcol;
      rcol *= smoothstep(0.66, 0.1, tt);
      if (rt < MAX_RAY_LENGTH_HI) {
//        rcol += diffColor*.2;
      } else {
        rcol += .5*render0(p, r, B);
      }
    }
    rcol += 4.0*hd/max(dd.x*dd.x, 0.01)*((diffColor+0.5)*glowCol1);
    col += dif*dif*fo*1e5*(sunColor*diffColor);
    col += fre*rcol;
  }

  col += ggcol;
  col = mix(
      mix(col,col*.25*vec3(2,1,3),sfo)
    , skyCol+hd*smoothstep(MAX_RAY_LENGTH_HI, MAX_RAY_LENGTH_HI*.5, gd.y)*ggcol
    , sfo
    );


  vec3 rrd = rd*rotline;
  float flash = dot(rrd, normalize(vec3(0.0, -0.2, -1.0)))+1.0005;
  col += smoothstep(.5, 1., B*B)/flash*(0.01*vec3(.5, .25, 1.0));
  
  return col;
}


vec4 fpass0() {
  vec2
    q = _uv
  , pp=-1.+2.*q
  , p = 2.*_uvc
  ;

  float
#ifdef KODELIFE
    t=TIME*travel_speed.x
#else
  t = st
  // t=dot(vec2(TIME,syn_BassTime),travel_speed)
#endif
  , z=mod(t, PERIOD)-PERIOD*.5
  , depth
  ;

  vec3
    ro = path(z)
  , Z  = normalize(dpath(z))
  , dd = ddpath(z)
  , X  = normalize(cross(vec3(0, 1, 0)+10.*dd, Z))
  , Y  = cross(Z,X)
  , rd = normalize(-p.x*X + p.y*Y + 2.*Z)
  , col
  ;
  g_X=X;
  g_Y=Y;
  g_Z=Z;

  col= render1(ro, rd, p, q, depth);
//  col= render0(ro, rd, beat());

  col -= .025*(.25+length(pp))*vec3(2,3,1);
  col *= smoothstep(1.5, 0.5, length(pp));

  //col=vec3(10000.*abs(toScreenSpace(ro,ro+rd*1.)-q),0);
  //col = texture(pass0,toScreenSpace(ro,ro+rd*1.)).xyz;
  col = max(col,0.);
  return vec4(col,depth);
}

vec3 reduceNoise(sampler2D tex, ivec2 xy) {
  const vec3
    luma = vec3(0.2126, 0.7152, 0.0722)
  ;
  vec3
    c = texelFetch(tex, xy, 0).xyz
  , a = vec3(0)
  ;
  a += texelFetch(tex, xy + ivec2( 0,  1), 0).xyz;
  a += texelFetch(tex, xy + ivec2( 0, -1), 0).xyz;
  a += texelFetch(tex, xy + ivec2( 1,  0), 0).xyz;
  a += texelFetch(tex, xy + ivec2(-1,  0), 0).xyz;
//#define MORE
#ifdef MORE
  a += texelFetch(tex, xy + ivec2( 1,  1), 0).xyz;
  a += texelFetch(tex, xy + ivec2( 1, -1), 0).xyz;
  a += texelFetch(tex, xy + ivec2(-1, -1), 0).xyz;
  a += texelFetch(tex, xy + ivec2(-1,  1), 0).xyz;
  a/=8.;
#else
  a/=4.;
#endif
  float
    cl=dot(luma,c)
  , al=dot(luma,a)
  ;
  return cl > al ? a : c;
}

vec4 fpass1() {
  vec2
    q = _uv
  ;

  vec3
    col=reduceNoise(pass0,ivec2(_xy))
  , pcol=texture(syn_FinalPass,q).xyz
  ;
  col=clamp(col,0.,9.);
  col=tanh_approx(col);
  col=sqrt(col);

  col=mix(col,clamp(pcol.xyz,0.,1.),motion_blur);
  return vec4(col, 1);
}


vec4 renderMain() {
  switch(PASSINDEX) {
    case 0:
      return fpass0();
    case 1:
      return fpass1();
    default:
      return vec4(0);
  }
}

