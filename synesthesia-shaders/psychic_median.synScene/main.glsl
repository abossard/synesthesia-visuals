vec3 d = 1./vec3(RENDERSIZE, 1.);

const float pi = 3.14159265359;
const float eps = 1e-15;

float do_weather = float((media_shape==0) || (syn_MediaType==0));

float zap_ = syn_Intensity*do_weather*max(zap, auto_weather*float(syn_OnBeat==1));
float melt_ = do_weather*max(melt, auto_weather*syn_BassHits);
float burn_ = float(syn_Intensity>0.9)*do_weather*max(burn, auto_weather*syn_MidHits);
float seed_ = syn_Intensity*do_weather*max(seed, auto_weather*float(int(syn_BeatTime)%8==0));

float mean(vec3 x){
  return (x.r+x.g+x.b)/3;
}

vec3 sorted(vec3 x){
  if(x.r >= x.g && x.g >= x.b) return x.bgr;
  if(x.r <= x.g && x.g <= x.b) return x;
  if(x.g >= x.r && x.r >= x.b) return x.brg;
  if(x.g <= x.r && x.r <= x.b) return x.grb;
  if(x.r >= x.b && x.b >= x.g) return x.gbr;
  return x.rbg;
}

#define STEP(m) if (dot(m, m) <= min_dist && dot(p-(m), p-(m)) <= r*r){\
  min_dist = dot(m, m);\
  best_p = p - (m);\
}
vec4 circleTexel(in sampler2D s, vec2 p){
  ivec2 rs = ivec2(RENDERSIZE);
  ivec2 ts = textureSize(s, 0);
  float r = min(ts.x, ts.y)/2;
  //center coordinates
  p -= rs/2;
  // wrap coord into circle
  p -= step(r*r, dot(p, p)) * 2*r*normalize(p);
  // clamp to nearest pixel center within circle
  float min_dist = 1e15;
  vec2 best_p = p;
  vec2 m = fract(p-.5); //coord of p relative to southwest pixel center
  STEP(m)
  STEP(m-vec2(1, 0)) //se
  STEP(m-vec2(1, 1)) //ne
  STEP(m-vec2(0, 1)) //nw
  p = best_p;
  // uncenter
  p += ts/2;
  return texelFetch(s, ivec2(p), 0);
}

#define SWAP(i, j) if (dot(x[i]-c0, x[i]-c0) > dot(x[j]-c0, x[j]-c0)) {\
  t = x[i];\
  x[i] = x[j];\
  x[j] = t;\
}
vec4 fbMain(in sampler2D state, int index){
  int count = index + int(FRAMECOUNT)*4;
  ivec2 ts = textureSize(state, 0);
  int r = min(ts.x, ts.y)/2;
  if (length(_xy - ts/2) > r) return vec4(0.5);
  float r2 = length(_xy - ts/2);

  if(bool(media_shape) && syn_MediaType!=0){
    vec2 d_uv = (vec2(int(index/2), index%2) - 0.5) / RENDERSIZE;
    vec4 media = texture(syn_UserImage, d_uv+vec2((_uvc.x+1.)/2., (1.-_uvc.y)/2.));

    return media;
  }


  const float warp = 3;
  const float push = 0.25;

  vec2 xy = _xy; // _xy is coord of pixel center

  vec4 x[9];

  // vec4 spect = vec4(syn_BassLevel, syn_MidLevel, syn_MidHighLevel, syn_HighLevel);
  vec4 spect =
      - vec4(syn_BassPresence, syn_MidPresence, syn_MidHighPresence, syn_HighPresence)
      + vec4(syn_BassLevel, syn_MidLevel, syn_MidHighLevel, syn_HighLevel)
      + vec4(syn_BassHits, syn_MidHits, syn_MidHighHits, syn_HighHits) + syn_ToggleOnBeat;
  ivec4 ispect = ivec4(6*spect*pow(react, 1.));

  if (react>0){
    xy += vec2(0,1)*ispect.y*float(count%8==0); //fall
    xy += vec2(-sign(_uvc.x), 0)*float(count%32==0)*ispect.z; //rift
    xy -= ring*normalize(_uvc)*float(count%16==0)*sign(.25-length(_uvc))*ispect.w;
    xy -= expand*float(count%16==0)*(
      length(_uvc)*r>1 ?
      normalize(_uvc) :
      -normalize(_uvc)*r
      )*ispect.x;
  }

  xy += fall*vec2(0,1)*float(count%4==0);
  xy += rift*vec2(-sign(_uvc.x), 0)*float(count%16==0);
  xy -= ring*normalize(_uvc)*float(count%8==0)*sign(.25-length(_uvc));
  xy -= expand*float(count%8==0)*(
    length(_uvc)*r>1 ?
    normalize(_uvc) :
    -normalize(_uvc)*r
    );

  xy += swap*vec2(0.5)*ts;

  if(dive>0 && count%4==0){
    xy = (xy-ts/2)*2/3 + ts/2;
  }

  for (int i=-1; i<=1; i++){
    for (int j=-1; j<=1; j++){
      x[i+1+3*(j+1)] = circleTexel(state, xy+vec2(i, j));
    }
  }
  vec4 c0 = x[4];
  vec4 t;
  //sort by similarity to c0
  SWAP(0, 1); SWAP(2, 3); SWAP(0, 2); SWAP(1, 3); SWAP(1, 2); SWAP(4, 5);
  SWAP(7, 8); SWAP(6, 8); SWAP(6, 7); SWAP(4, 7); SWAP(4, 6); SWAP(5, 8);
  SWAP(5, 7); SWAP(5, 6); SWAP(0, 5); SWAP(0, 4); SWAP(1, 6); SWAP(1, 5);
  SWAP(1, 4); SWAP(2, 7); SWAP(3, 8); SWAP(3, 7); SWAP(2, 5); SWAP(2, 4);
  SWAP(3, 6); SWAP(3, 5); SWAP(3, 4);

  vec4 m[3];
  // m[0:3] contain adaptive blur toward most similar, median, and most dissimilar neighbors
  for (int j=0; j<3; j++){
    m[j] = vec4(0);
    float z = 0;
    for (int i=0; i<9; i++){
      float w = pow(2, -4*length(x[4*j]-x[i]));
      z += w;
      m[j] += w*x[i];
    }
    m[j]/=z;
  }

  // n's contain far neighbors offset by m's colors
  vec4 n0 = circleTexel(state, xy+warp*(m[0].xy-m[0].zw));
  vec4 n1 = circleTexel(state, xy+warp*(m[1].xy-m[1].zw));
  vec4 n2 = circleTexel(state, xy+warp*(m[2].xy-m[2].zw));

  vec4 color = c0 - (normalize(m[1]-m[2]) + normalize(m[1]-m[0]))*push;
  // vec4 color = c0 - (normalize(2*m[1]-m[2]-m[0]))*push;

  color = clamp(color, min(n0, min(n1, n2)), max(n0, max(n1, n2)));
  // color = clamp(color, 0, 1);

  color = mix(color, m[2], pow(melt_*float(count%4 > 0), 4));
  color = mix(color, x[8], pow(burn_, 4));

  return color;
}

vec4 intervention(sampler2D state){
  ivec2 ts = textureSize(state, 0);
  return fract(circleTexel(state, _xy+vec2(0,-1)) + circleTexel(state, _xy+vec2(0,1)).gbar + .5);
}

vec4 processColor(vec4 c){
  vec4 s = abs(c-.5)*2;
  c.a = pow(max(s.r, max(s.g, max(s.b, s.a))), .25);
  c.b = sqrt(c.b);
  return c;
}
vec4 prePix(){
  vec4 c0 = texelFetch(post0, ivec2(_xy), 0);
  mat4 cs = mat4(
    circleTexel(fb0, _xy),
    circleTexel(fb1, _xy),
    circleTexel(fb2, _xy),
    circleTexel(fb3, _xy)
    );
  // vec4 c = (cs[0]+cs[1])/2;
  // float r = length(abs(cs[0]-c)+abs(cs[1]-c));
  vec4 c = (cs[0]+cs[1]+cs[2]+cs[3])/4;
  float r = length(abs(cs[0]-c)+abs(cs[1]-c)+abs(cs[2]-c)+abs(cs[3]-c));
  c = processColor(c);
  c.r = r;
  c = FRAMECOUNT>0
    ? mix(c, c0, (1-seed_)*(1-melt_*0.25)*(1-zap_)*pow(smoothing, .25))
    : c;
  return c;
}

vec4 postPix(in sampler2D state){
  ivec2 ts = textureSize(state, 0);
  const int log_n = 6;
  const int n = 1<<log_n;
  const vec2 offset = vec2(0, -64);
  vec4 c;
  vec2 d = zoom>1 ? (0.5-pan -_uvc )/zoom : vec2(0, -1);
  float ld = length(d);
  vec2 xy = (_xy + pan*RENDERSIZE*(zoom-1))/zoom;

  float phi = undulate*(smoothing>0 ?
    2*pi*syn_CurvedTime/16
    : pi/8*syn_CurvedTime);

  vec2 xyo = xy-offset+ts;

  for (int i=0; i<n; i++){
    ivec2 coord = ivec2(xyo+d*i)%ts;
    vec4 cand = texelFetch(state, coord, 0);

    float h = (n-3)*ld*cand.a*pow(sin(_uv.y*pi + cand.g*3*pi + phi)*.5+.5, 2);

    float ii = i*ld;

    // ivec2 media_coord = ivec2(xyo+offset+d*i)%ts;
    vec2 media_coord = vec2((_uvc.x+1.)/2., (1.-_uvc.y)/2. - i*d.y/ts.y);
    vec4 media = texture(syn_UserImage, media_coord);

    if (h < ii+1 && h>=ii){
      //top
      if (!bool(media_color) || syn_MediaType==0){
        c = mix(sqrt(vec4(1-cand.b, cand.b, 1, 1)), vec4(1,.8,0,0), cand.r)*cand.a;
        c = mix(c, c*vec4(0.5, 0.7, 0.9, 1), _uv.y-h/n);
      }
      else{
        c = media;//texture(syn_UserImage, (vec2(coord.x, 1-coord.y)-offset)/RENDERSIZE);
      }
    }else if (h>=ii+1){
      //side
      float m = (h-ii-1)/h;
      float sqm = sqrt(m);
      c = vec4(sqm, (1-sqm)*cand.b, 1-m*m, 1)*cand.g+cand.r*vec4(1,.5,0,0);
      if (bool(media_color) && syn_MediaType!=0){
        c = (.5*c + .5)*media;//texelFetch(syn_UserImage, coord, 0);
      }
    }
    else{
      //shadow effect
      c *= zoom > 1 ? 0.997 : 1-pow(2, (floor(h)-ii-1)/ld);
      // c *= 0.01*texture(syn_UserImage, (-coord-offset)/RENDERSIZE)+0.99;

    }
  }
  if (syn_MediaType==0)
    return clamp(0.5+(c-.5)*1.333, 0, 1);
  else
    return clamp(0.55+(c-.5)*1.111, 0, 1);

}

vec4 postMain(in sampler2D state){
  vec4 c = texelFetch(state, ivec2(_uv*textureSize(state, 0)), 0);
  return c;
}

vec4 initialCondition(){
  ivec2 ts = ivec2(RENDERSIZE);
  ivec2 ixy = ivec2(_xy);
  if (ts/2-1==ixy+ivec2(-1,-1)) return vec4(0,0,0,0);
  if (ts/2-1==ixy+ivec2(-1, 0)) return vec4(0,0,0,1);
  if (ts/2-1==ixy+ivec2(-1, 1)) return vec4(0,0,1,0);
  if (ts/2-1==ixy+ivec2(-1, 2)) return vec4(0,0,1,1);
  if (ts/2-1==ixy+ivec2( 0,-1)) return vec4(0,1,0,0);
  if (ts/2-1==ixy+ivec2( 0, 0)) return vec4(0,1,0,1);
  if (ts/2-1==ixy+ivec2( 0, 1)) return vec4(0,1,1,0);
  if (ts/2-1==ixy+ivec2( 0, 2)) return vec4(0,1,1,1);
  if (ts/2-1==ixy+ivec2( 1,-1)) return vec4(1,0,0,0);
  if (ts/2-1==ixy+ivec2( 1, 0)) return vec4(1,0,0,1);
  if (ts/2-1==ixy+ivec2( 1, 1)) return vec4(1,0,1,0);
  if (ts/2-1==ixy+ivec2( 1, 2)) return vec4(1,0,1,1);
  if (ts/2-1==ixy+ivec2( 2,-1)) return vec4(1,1,0,0);
  if (ts/2-1==ixy+ivec2( 2, 0)) return vec4(1,1,0,1);
  if (ts/2-1==ixy+ivec2( 2, 1)) return vec4(1,1,1,0);
  if (ts/2-1==ixy+ivec2( 2, 2)) return vec4(1,1,1,1);
  return vec4(0.5);
}

vec4 renderMain () {
  if (FRAMECOUNT<=2){
    return initialCondition();
  }
  if (PASSINDEX == 0.0){
    if (seed_>0) return initialCondition();
    if (zap_>0 || burn_>=0.99) return intervention(fb2);
    return fbMain(fb3, 0);
  }
  else if (PASSINDEX == 1.0){
    return fbMain(fb0, 1);
  }
  else if (PASSINDEX == 2.0){
    return fbMain(fb1, 2);
  }
  else if (PASSINDEX == 3.0){
    return fbMain(fb2, 3);
  }
  else if (PASSINDEX == 4.0){
    return prePix();
  }
  else if (PASSINDEX == 5.0){
    return postPix(post0);
  }
  else if (PASSINDEX == 6.0){
    return postMain(post1);
  }

  return vec4(1.0, 0.0, 0.0, 1.0);
}
