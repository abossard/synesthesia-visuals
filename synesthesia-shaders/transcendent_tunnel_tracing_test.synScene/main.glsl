// COMMON:
#define TT (syn_Time*0.2+TIME*0.1)

float dot2(vec2 p) {
  return dot(p,p);
}

float dot2(vec3 p) {
  return dot(p,p);
}

// License: Unknown, author: Unknown, found: don't remember
float hash(float co) {
  return fract(sin(co*12.9898) * 13758.5453);
}

// Gaussian blur - using normalized texture() for resolution independence
vec3 gb(sampler2D pp, vec2 dir, vec2 uv) {
  const float blurriness = 100.;
  vec2 texelSize = 1.0 / RENDERSIZE;
  vec3 col = texture(pp, uv).xyz;
  float w, ws = 1., I;

  for(int i = 1; i < 9; ++i) {
    I = float(i);
    w = exp(-(I*I)/blurriness);
    vec2 off = float(i) * dir * texelSize;
    col += w * (texture(pp, uv - off).xyz + texture(pp, uv + off).xyz);
    ws += 2. * w;
  }
  col /= ws;
  return col;
}

// License: Unknown, author: Claude Brezinski, found: https://mathr.co.uk/blog/2017-09-06_approximating_hyperbolic_tangent.html
vec3 tanh_approx(vec3 x) {
  //  Found this somewhere on the interwebs
  //  return tanh(x);
  vec3 x2 = x*x;
  return clamp(x*(27.0 + x2)/(27.0+9.0*x2), -1.0, 1.0);
}





// Buffer A:
const float
  TAU=2.*PI
, PI_2=.5*PI
, MIN=-1.
, MAX=6.
;

// License: Unknown, author: Unknown, found: don't remember
float hash(vec2 co) {
  return fract(sin(dot(co.xy ,vec2(12.9898,58.233))) * 13758.5453);
}

// License: Unknown, author: Unknown, found: don't remember
vec2 hash2(float co) {
  return fract(sin(co*vec2(12.9898,78.233))*43758.5453);
}

// License: Unknown, author: catnip, found: FieldFX discord
vec3 point_on_sphere(vec2 r) {
  r=vec2(PI*2.*r.x, 2.*r.y-1.);
  return vec3(sqrt(1. - r.y * r.y) * vec2(cos(r.x), sin(r.x)), r.y);
}

// License: Unknown, author: catnip, found: FieldFX discord
vec3 uniform_lambert_approx(vec2 r, vec3 n) {
  return normalize(n*(1.001) + point_on_sphere(r)); // 1.001 required to avoid NaN
}

// License: MIT, author: Pascal Gilcher, found: https://www.shadertoy.com/view/flSXRV
float atan_approx(float y, float x) {
  float cosatan2 = x / (abs(x) + abs(y));
  float t = PI_2 - cosatan2 * PI_2;
  return y < 0.0 ? -t : t;
}

// License: MIT, author: Inigo Quilez, found: https://iquilezles.org/articles/intersectors/
float ray_unitsphere(vec3 ro, vec3 rd) {
  float 
    b=dot(ro, rd)
  , c=dot(ro, ro)-1.
  , h=b*b-c
  ;
  return -b-sqrt(h);
}

vec3 noisy_ray_dir(vec2 r, vec2 p, vec3 X, vec3 Y, vec3 Z) {
  p += (-1.+2.*r)/RENDERSIZE.y;
  return normalize(-p.x*X+p.y*Y+2.*Z);
}

mat2 rot(float a) {
  float
    c=cos(a)
  , s=sin(a)
  ;
  return mat2(c,s,-s,c);
}

vec4 fpass0(vec2 p, ivec2 xy) {
  bool 
    xc                   // Cylinder hit with pattern (emissive)
  , xe                   // Ray escape condition
  ;
  float
    an                   // Angular coordinate
  , at                   // Accumulated attenuation
  , bi                   // Loop counter for bounces
  , cf                   // Cylinder index with fractional time
  , ci                   // Loop counter for cylinders
  , ch                   // Cylinder height
  , fi                   // Fade-in factor for first cylinder
  , fo                   // Fade-out factor
  , fr                   // Fresnel/scale factor
  , id                   // Cylinder ID
  , ns =0.               // Sample count
  , sd                   // RNG seed
  , si                   // Discriminant/sqrt term for cylinder intersection
  , tn                   // Nearest intersection distance
  , ts                   // Sphere intersection distance
  , h0                   // Hash for cylinder
  , h1
  , T=TT+123.4         // Current time
  , NT=floor(T)          // Integer time
  , FT=fract(T)          // Fractional time
  , ir                   // Inner radius squared
  , a                    // Quadratic coefficient: dot(rd.xz, rd.xz)
  , b                    // Quadratic coefficient: dot(po.xz, rd.xz)
  , c                    // Quadratic coefficient: dot(po.xz, po.xz)
  , bb                   // b squared
  , ac                   // a times c
  , tc                   // Candidate intersection distance
  , ti                   // Cylinder side intersection distance
  , tt                   // Cylinder cap intersection distance
  ;
  
  fi=2.*smoothstep(1.,0.,FT);
  
  vec2 
    rn                   // Random 2D value
  ;
  vec3
    ro=vec3(0,5.,-4)+sin(vec3(0,-.234,.123)*T)  // Ray origin (camera position)
  , la=vec3(0)                // Look-at target
  , sc=vec3(0)                // Sphere center
  , UP=normalize(vec3(0.5*sin(.07*T),1,0))
  , Z =normalize(la-ro)       // Camera forward vector
  , X =normalize(cross(Z,UP)) // Camera right vector
  , Y =cross(X,Z)             // Camera up vector
  , co=vec3(0)                // Accumulated color
  , ip                        // Current intersection point
  , po                        // Path vertex position
  , rd                        // Path ray direction
  , no                        // Surface normal
  , rf                        // Reflected direction
  , ld                        // Lambert sampled direction
  , nc
  ;
  
  sd=fract(hash(p)+TT);
  
  sc.y=FT-.5;
  sc.y*=sc.y;
  sc.y=.25-sc.y;
  
  po=ro;
  rd=noisy_ray_dir(vec2(0),p,X,Y,Z);
  
  for(bi=0.;bi<32.;++bi) {
    ++sd;
    rn=hash2(sd);
    ts=ray_unitsphere(po-sc,rd);
    tn=1e3;
    if(ts>0.)    { tn=ts; no=po+rd*ts-sc;  }
    xc=false;

    a = dot(rd.xz, rd.xz);
    b = dot(po.xz, rd.xz);
    c = dot(po.xz, po.xz);
    bb=b*b;
    ac=a*c;
    
    id=MIN-1.-NT;
    fr=exp2(MIN-1.+FT);
    
    for(ci=MIN;ci<MAX;++ci) {
      ++id;
      fr*=2.;
      
      ch=.1*fr+.3;
      
      if(ci==MIN) {
        ch-=fi;
      }
      
      ir = 1.+.125*fr;
      ir*=ir;
      tc = 1e3;
      si = sqrt(bb - ac + a*ir);
      ti=(-b+si)/a;
      ip = po + rd*ti;
      if(si>=0. && ip.y <= ch && ti > 0. && ti < tc) {
        tc = ti;
        nc = -vec3(ip.x, 0, ip.z);
      }
      
      tt = (ch - po.y) / rd.y;
      ip = po + rd*tt;
      if(tt > 0. && tt < tc && dot(ip.xz, ip.xz) >= ir) {
        tc = tt;
        nc = vec3(0, 1, 0);
      }
      
      if(tc>0.&&tc<tn){ tn=tc; h0=hash(id),no=normalize(nc); xc=true; cf=ci+FT;si=id;}
    }
    h1=fract(8677.*h0);
    ip=po+rd*tn;
    xe=tn>20.||at<1e-1;
    an=atan_approx(ip.x,abs(ip.z))+(-1.+2.*h0)*T;
    xc = xc && sin(2.*an)>mix(.5,1.,h1);
    fo=smoothstep(MAX,MAX-2.,cf);
    if(xe||xc) {
      if(xc) {
        co+=
            at
          * (1.-.5*dot(rd,no))
          * (1.-.5*dot(rd,rf))
          * fo
          * (1.+sin(vec3(6,1,8)+.33*an))
          ;
      }
      po=ro;
      rd=noisy_ray_dir(rn,p,X,Y,Z);
      at=1.;
      ++ns;
      continue;
    }
    
    fr=1.+dot(rd,no);    
    fr=pow(fr,16.);
    
    rf=reflect(rd,no);
    ld=uniform_lambert_approx(rn,no);
    if(ts==tn) {
      co+=at*4.*pow(.5*(1.-dot(rd,rf)),16.)*vec3(0,.25,1.);
    }
    if(rn.x<fr||ts==tn) {
      rd=rf;
      at*=.75;
    } else {
      rd=ld;
      at*=.4;
    }
    po=ip+1e-2*no;
    at*=fo;
  }
  
  co/=max(ns,1.);
  co=max(co,0.);
  
  return vec4(co,1.);  
}


// void mainImage(out vec4 O, vec2 C) {
//   O=fpass0((2.*C-RENDERSIZE)/RENDERSIZE.y,ivec2(0));
// }





// Buffer B:
vec3 denoise(vec2 uv) {
  const int MAX = 2;
  const float DIV = 1./float(MAX*MAX);
  vec2 texelSize = 1.0 / RENDERSIZE;
  vec3 center = texture(BufferA, uv).xyz;
  vec3 s, sum = center;
  float w, weight = 1.0;
  
  for(int dy = -MAX; dy <= MAX; ++dy)
  for(int dx = -MAX; dx <= MAX; ++dx) {
    if(dx == 0 && dy == 0) continue;
    s = texture(BufferA, uv + vec2(dx, dy) * texelSize).xyz;
    w = exp(-float(dx*dx + dy*dy) * DIV - dot2(s - center) * 1E2);
    sum += s * w;
    weight += w;
  }
  return sum / weight;
}

vec4 fpass1(vec2 uv) {
  vec3 col = denoise(uv);
  vec3 pcol = texture(BufferB, uv).xyz;
  return vec4(mix(pcol, col, 0.4), 1.);
}

// void mainImage(out vec4 O, vec2 C) {
//   O=fpass1(vec2(0),ivec2(C));
// }




// Buffer C:
vec4 fpass2(vec2 uv) {
  return vec4(gb(BufferB, vec2(2.0, 0.0), uv), 1.);
}

// void mainImage(out vec4 O, vec2 C) {
//   O=fpass2(vec2(0),ivec2(C));
// }



// Buffer D:
vec4 fpass3(vec2 uv) {
  vec3 pcol = texture(BufferD, uv).xyz;
  return vec4(mix(gb(BufferC, vec2(0.0, 2.0), uv), pcol, 0.8), 1.);
}

// void mainImage(out vec4 O, vec2 C) {
//   O=fpass3(vec2(0),ivec2(C));
// }




// Image:
// CC0: Transcendent Tunnels Tracing Test
// Another attempt at learning more about path tracers.
// This time trying different techniques to reduce the path tracer noise

// Common   - Some common helper functions
// Buffer A - The core path tracer
// Buffer B - Denoiser
// Buffer C - Horizontal Gaussian blur
// Buffer D - Vertical Gaussian blur
// Image    - Tying it all together

// I am not sure if I like to glow or not.
#define APPLY_GLOW (glow_amt > 0.05)

vec4 fpass4(vec2 p, vec2 uv) {
  // Use normalized texture() for cross-resolution sampling (buffers are half-res)
  vec3 col = texture(BufferB, uv).xyz;
  vec3 bcol = texture(BufferD, uv).xyz;
  
  if (glow_amt>0.05) {
    col+=glow_amt*mix(1.,syn_BassHits,glow_bass)*bcol;
    col-=.025*vec3(1,2,0)/(1.+dot2(p));
  }
  // Normal tanh sometimes creates artifacts for big numbers. Especialy on Macbooks it seems.
  col=tanh_approx(col);
  col=max(col,0.);
  col=sqrt(col);
  return vec4(col, 1);
}

// void mainImage(out vec4 O, vec2 C) {
//   O=fpass4((2.*C-RENDERSIZE)/RENDERSIZE.y,ivec2(C));
// }





// RENDER ALL PASSES:

vec4 renderMain() {
    vec4 O = vec4(0.);
    if (PASSINDEX==0) O=fpass0(_uvc*zoom_amt*zoom_amt, ivec2(0)); 
    if (PASSINDEX==1) O=fpass1(_uv);
    if (PASSINDEX==2) O=fpass2(_uv);
    if (PASSINDEX==3) O=fpass3(_uv);
    if (PASSINDEX==4) O=fpass4(_uvc, _uv);
    return O;
}
