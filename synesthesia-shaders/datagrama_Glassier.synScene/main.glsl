vec3 iResolution = vec3(RENDERSIZE.x, RENDERSIZE.y, 0.0);
float time = TIME;

// ****************** PASS 0 ***********************
// main reaction-diffusion loop

// actually the diffusion is realized as a separated two-pass Gaussian blur kernel and is stored in buffer C

vec2 complex_mul(vec2 factorA, vec2 factorB){
  return vec2( factorA.x*factorB.x - factorA.y*factorB.y, factorA.x*factorB.y + factorA.y*factorB.x);
}

float sigmoid(float x) {
  return 2./(1. + exp2(-x)) - 1.;
}

float conetip(vec2 uv, vec2 pos, float size, float min)
{
  vec2 aspect = vec2(1.,iResolution.y/iResolution.x);
  return max( min, 1. - length((uv - pos) * aspect / size) );
}

float warpf1lter(vec2 uv, vec2 pos, float size, float ramp)
{
  return 0.5 + sigmoid( conetip(uv, pos, size, -16.) * ramp) * 0.5;
}

vec2 vortex_warp(vec2 uv, vec2 pos, float size, float ramp, vec2 rot)
{
  vec2 aspect = vec2(1.,iResolution.y/iResolution.x);

  vec2 pos_correct = 0.5 + (pos - 0.5);
  vec2 rot_uv = pos_correct + complex_mul((uv - pos_correct)*aspect, rot)/aspect;
  float f1lter = warpf1lter(uv, pos_correct, size, ramp);
  return mix(uv, rot_uv, f1lter);
}

vec2 vortex_pair_warp(vec2 uv, vec2 pos, vec2 vel){
  vec2 aspect = vec2(1.,iResolution.y/iResolution.x);
  float ramp = 5.;

  float d = 0.2;

  float l = length(vel);
  vec2 p1 = pos;
  vec2 p2 = pos;

  if(l > 0.){
    vec2 normal = normalize(vel.yx * vec2(-1., 1.))/aspect;
    p1 = pos - normal * d / 2.;
    p2 = pos + normal * d / 2.;
  }

  float w = l / d * 2.;

  // two overlapping rotations that would annihilate when they were not displaced.
  vec2 circle1 = vortex_warp(uv, p1, d, ramp, vec2(cos(w),sin(w)));
  vec2 circle2 = vortex_warp(uv, p2, d, ramp, vec2(cos(-w),sin(-w)));

  return (circle1 + circle2) / 2.;
}

vec3 _grad3(vec3 col1, vec3 col2, vec3 col3, float mixVal){
    mixVal *= 2.0;
    float mix1 = clamp(mixVal,0.0,1.0);
    float mix2 = clamp(mixVal-1.0, 0.0, 1.0);
    return mix(mix(col1, col2, mix1), mix(col2, col3, mix2), step(1.0, mixVal));
}
float lum(vec3 colIn){
  return dot(colIn, vec3(1.0))/3.0;
}
void mainImage0(out vec4 fragColor, in vec2 fragCoord)
{
  vec4 dat = vec4(0.0);
  float logoLum = lum(_loadUserImage().rgb);
  dat.g = mix(pow(logoLum,1.6), clamp(0.9-pow(logoLum, 0.5),0.0,1.0), invert_glow_mask);
  dat.b = _loadUserImageAsMask().r;
  // dat.g = 1.0-dat.a;
  // vec2 modifiedCenter = 0.75+vec2(sin(syn_BeatTime*2*PI*0.0215),cos(syn_BeatTime*2*PI*0.0237))*1.5;
  // modifiedCenter.x *= RENDERSIZE.x/RENDERSIZE.y;
  // vec2 pos = _uv*vec2(1.2, 1.0);
  // modifiedCenter *= vec2(1.2, 1.0);
  // vec2 modPos = pos-modifiedCenter;
  // modPos = modPos*modPos;
  // float moddero = modPos.x-modPos.y;

  // float bkgNoiseRegime = mod(floor(syn_BeatTime+moddero),4.0)*2.0+4.0;

  float logo = logoLum;
  // if (syn_MediaType < 0.5){
  //   logo = 0.0;
  // }

  vec2 uv = _uv;
  vec2 pixelSize = 1.0/RENDERSIZE.xy;
  vec4 noise = vec4(_noise(_uv*1000.0));
  uv += _rotate(_uvc,noise.r*0.02)*0.002*in_out; //get rid of lines that are too regular
  vec2 aspect = vec2(1.0,RENDERSIZE.y/RENDERSIZE.x);

  vec2 flowVec = manual_position;
  if (auto_move>0.5){
    flowVec = vec2((sin(syn_Time*2*PI*0.025*0.65)),(cos(syn_HighTime*2*PI*0.075*0.65)));
  }
  // float twitcher = (syn_HighHits)*impulse_amt;
  uv = vortex_pair_warp(uv, (flowVec+1.0)*0.5, normalize(flowVec)*(pow(max(0.0,syn_BassLevel-0.2),2.0))*0.025*impulse_amt);

  vec4 oldData = texture(buffA2, _uv);


  if (churning_on > 0.5){
    float churnMask = dat.b;
    flowVec = vec2(sin(TIME*0.5),1.0)*(-1.0+2.0*step(fract(_uvc.x*(30.0+10.0*sin(TIME*0.5))),0.5))*0.75;
    // flowVec *= ((1.0-logo)*face_or_total);
    uv = vortex_pair_warp(uv, (flowVec+1.0)*0.5, flowVec*0.01*mix(churnMask, (1.0-churnMask), invert_churning_mask));     
  }
  if (ornate_on > 0.5){
    flowVec = mix(vec2(0.0,1.0)*_uvc, vec2(0.0), 0.0);
    // uv = uv + _uvc*syn_BassLevel*0.0005;
    // uv = uv - _uvc*syn_HighHits*0.001;
    float amt = (1.0+100.0*pow(ornate_dist,2.0));

    uv = vortex_pair_warp(uv, fract(_uvc*amt), flowVec*(0.003*ornate_power*2.0));     
  }

  // get the gradients from the blurred image

  if (liquify_on >0.5){
    float m2 = mod(manual_pulse, 2.0);
    uv += _rotate(vec2(0.0,-1.0+2.0*m2), pow(_fbm(_uvc*10.0),2.0)*4*PI+manual_pulse*PI*0.5)*0.001*(1.0-auto_pulse);
    uv += _rotate(vec2(0.0,1.0), _fbm(vec3(_uvc*10.0, syn_BeatTime*0.4))*4*PI)*auto_pulse*0.001*(-1.0+2.0*m2);
  }

  vec2 d = pixelSize*4.0;
  d = mix(d, d*0.5, ornate_on);

  vec4 dx = (texture(buffC, fract(uv + vec2(1,0)*d)) - texture(buffC, fract(uv - vec2(1,0)*d))) * 0.5;
  vec4 dy = (texture(buffC, fract(uv + vec2(0,1)*d)) - texture(buffC, fract(uv - vec2(0,1)*d))) * 0.5;

  // if (flowing == 1.0){
  //   dy.x += distance(uv*aspect, vec2(0.5,0.0));
  // }


  float distFunc = 0.0;
  vec2 flowOut;

  vec2 uv_red = uv + vec2(dx.x, dy.x)*pixelSize*8.0; // add some diffusive expansion


  uv_red = mix(uv_red, uv - vec2(dx.x, dy.x)*pixelSize*8.0, pow(shock_back,2.0)); // add some diffusive expansion

  //green
  vec2 uv_green = uv + vec2(dx.y, dy.y)*pixelSize*8.0; // add some diffusive expansion
  uv_green -= vec2(dx.y, dy.y)*pixelSize*(7.0+oldData.r*10.0);
  uv_green += -normalize(_uvc)*0.00005;
  float gTearF = fract(1.0-glow_tear_scr+0.01);
  float gTearC = floor(glow_tear_scr);
  uv_green -= _rotate(vec2(sign((-1.0+mod(gTearC,2)*2.0)*_rotate(_uvc, gTearC*PI*0.0/4.0)).x)*(gTearF*_pulse(length(_uvc), 1.0-gTearF, 0.2)), -gTearC*PI*2.0/4.0)*0.01;

  uv_green = mix(uv_green, uv - vec2(dx.y, dy.y)*pixelSize*8.0, pow(shock_back,2.0)); // add some diffusive expansion

  vec4 new_red = vec4(0.0);
  new_red.r = texture(buffA2, fract(uv_red)).r + (noise.x*0.5) * (0.0035) - 0.002; // stochastic dec
  new_red.r -= (texture(buffC, fract(uv_red + (noise.xy-0.5)*pixelSize)).r -
              texture(buffA2, fract(uv_red + (noise.xy-0.5)*pixelSize))).r * 0.047 ; // reaction-diffusion

  float new_green = 0.0;

  new_green = texture(buffA2, fract(uv_green)).g + (noise.y*0.1) * (0.0035) - 0.0025; // stochastic dec
  new_green -= (texture(buffC, fract(uv_green + (noise.ba-0.5)*pixelSize)).g -
              texture(buffA2, fract(uv_green + (noise.ba-0.5)*pixelSize))).g * 0.047 ; // reaction-diffusion

  float modder = pow(syn_BassLevel,2.0);
  modder = mix(modder, 0.7, churning_on);
  // modder = mix(modder, 0.0, squares_on);

  logo = pow(logo, 2.0);
  float revTime = 0.2*syn_BassTime+TIME*0.3;
  vec2 uvM = _uv;
  if (uvM.x>0.5){
    uvM.x = 1.0-uvM.x;
  }
  uvM *= vec2(3.6/0.9, 1.0);
  vec2 uvm = vec2(abs(_uvc.x), _uvc.y);
  float noi = _fbm(vec3(uvm*2.0,revTime));
  noi = pow(noi, 3.0);
  // float revTime = 0.5*TIME;
  logo *= mix(clamp(0.75-sin(uvM.x*7.9+revTime*0.4+noi*PI)+sin(uvM.y*13.7+revTime*0.74)+sin(uvM.y*3.17+revTime*0.85+noi)+sin(uvM.x*3.17+revTime)+sin(uvM.y*0.17+length(_uvc)*4.5+syn_BassTime*0.15+noi*2*PI),0.0,1.0), 1.0, 1.0-partial_reveal);

  // float noi2 = clamp(sin(uvM.x*1.9-revTime*0.4+sin(_uv.y-revTime))+sin(uvM.y*2.7+_uv.x*0.1+revTime*0.74), 0.0, 1.0);
  // logo *= mix(0.5+0.5*sin(pow(noi,2.0)*2*PI+noi2*PI), 1.0, 1.0-partial_reveal);
  // logo *= mix(
  //   clamp(-0.2+0.21*sin(uvM.x*1.9+revTime*0.4+0.27*sin(_uv.y+revTime))+0.23*sin(uvM.y*2.7+_uv.x*0.1+revTime*0.74)+0.5*(sin(uvM.y*8.07+syn_HighTime*0.15+0.992*sin(_uv.y*3.39+revTime)))+0.33*sin(uvM.x*1.17+revTime)+0.43*sin(uvM.y*1.17+length(_uvc)*4.5+syn_BassTime*0.15)
  //     ,0.0,1.0)
  //   , 1.0, 1.0-partial_reveal);

  logo *= media_feed*media_feed*mix(0.1,0.9,media_feed)*mix(1.0,pow(min(syn_BassHits+syn_BassLevel*0.5,1.0), 2.0), feed_audio_pulse);

  vec4 blurInput = texture(buffC, _uv);

  new_red -= blurInput*0.001*((1.0-logo)*5.0);

  // if (new_red < modder){
    // give it some extra fire where it isn't very alive
    float thingIsOn = min(liquify_on+churning_on+ornate_on, 1.0);
    new_red *= 1.0+abs(in_out)*0.003+thingIsOn*0.004*0.5;
    new_red = mix(new_red, sqrt(new_red*blurInput*1.5), clamp(logo,0.0,1.0)*0.5);
    // new_red = mix(new_red, new_red*(1.0+logo*0.5+churning_on*5.0), pow(_fbm(_uvc*100.0+TIME*0.1),4.0));
  // }

  if (glow_audio_pulse>0.5){
    float pulsTime = syn_BassTime*0.4+new_red.r*5.0;
      new_green = new_green+dat.g*0.6*media_glow_feed*media_glow_feed*mix(1.0, pow(syn_HighHits,1.0), glow_audio_pulse)*0.5*clamp(1.0+sin(_uv.x*7.9-pulsTime+_uvc.y*27.0*sin(_uv.y+pulsTime*0.1))+sin(_uv.y*13.7-pulsTime*0.74+sin(_uv.x*23.33+syn_CurvedTime*0.2))+sin(_uv.y*19.17+pulsTime*0.85)+sin(_uv.x*4.17+pulsTime),0.0,1.0);
  } else {
      new_green = new_green+dat.g*0.5*media_glow_feed*media_glow_feed;
      new_green -= (1.0-dat.g)*media_glow_feed*0.05;
  }

  // new_red = mix(new_red, step(fract(_uv.y*10.0),0.5), _sqPulse(_uv.x, 0.61, 0.1));
  // new_red += noise.x*(1.0-logo)*0.01;
  // new_red += texture(buffA2, _uv).r*0.1*((1.0-logo)*10.0);


  if ((FRAMECOUNT<=4)||(reset_sim > 0.7)){
    fragColor = noise;
  }
  else{
    fragColor.r = clamp(new_red.r, 0., 1.);
    fragColor.g = clamp(new_green, 0., 1.);
    fragColor.g += _pulse(new_red.r,glow_flicker_fast,0.1)*glow_flicker_fast;
    fragColor.g += 0.2*_pulse(new_red.r+_uv.y*0.1,glow_flicker_slow,0.1)*glow_flicker_slow;
    fragColor.r = clamp(fragColor.r, 0., 1.);
    fragColor.g = clamp(fragColor.g, 0., 1.);
    // float decay = 0.97;
    // fragColor.g = 0.0;

  }

  // float old = oldData.b;
  // fragColor.b = texture(syn_UserImage, _invertYAxisVideo(_uv)).g+oldData.b*0.5-texture(syn_UserImage, _invertYAxisVideo(_uv)).g*0.5;
  // fragColor.b = clamp(fragColor.b, 0.0, 1.0);

  // if (dot(logoCol, vec3(1.0))/3.0 > 0.7){
  //   fragColor.r = mix(fragColor.r - 0.009, 0.7, grabFrame+0.05);
  // }

  // if ((image_block<0.5)&&(length(logoCol)*1.5>1.0)){
  //   fragColor.r -= 0.009;
  // }

  // if (image_block>=0.5){
  //   if (logoCol.r>0.5){
  //     fragColor.r = 1.0*syn_BassLevel;
  //   }
  // }

  // fragColor.r *= dot(vec3(1.0),logoCol)/3.0;

  //    fragColor = noise; // need a restart?
}

// *************** PASS 1 *****************
// horizontal Gaussian blur pass

void horizontalBlur(out vec4 fragColor, in vec2 fragCoord) {
  vec2 pixelSize = 1./ iResolution.xy;
  vec2 uv = fragCoord.xy * pixelSize;

  float h = pixelSize.x;
  vec4 sum = vec4(0.0);
  sum += texture(buffA2, fract(vec2(uv.x - 4.0*h, uv.y)) ) * 0.05;
  sum += texture(buffA2, fract(vec2(uv.x - 3.0*h, uv.y)) ) * 0.09;
  sum += texture(buffA2, fract(vec2(uv.x - 2.0*h, uv.y)) ) * 0.12;
  sum += texture(buffA2, fract(vec2(uv.x - 1.0*h, uv.y)) ) * 0.15;
  sum += texture(buffA2, fract(vec2(uv.x + 0.0*h, uv.y)) ) * 0.16;
  sum += texture(buffA2, fract(vec2(uv.x + 1.0*h, uv.y)) ) * 0.15;
  sum += texture(buffA2, fract(vec2(uv.x + 2.0*h, uv.y)) ) * 0.12;
  sum += texture(buffA2, fract(vec2(uv.x + 3.0*h, uv.y)) ) * 0.09;
  sum += texture(buffA2, fract(vec2(uv.x + 4.0*h, uv.y)) ) * 0.05;

  fragColor.xyz = sum.xyz/0.98; // normalize
  fragColor.a = 1.;
}



// *************** PASS 2 *****************
// vertical Gaussian blur pass
void verticalBlur(out vec4 fragColor, in vec2 fragCoord){
  vec2 pixelSize = 1./ iResolution.xy;
  vec2 uv = fragCoord.xy * pixelSize;

  float v = pixelSize.y;
  vec4 sum = vec4(0.0);
  sum += texture(buffB, fract(vec2(uv.x, uv.y - 4.0*v)) ) * 0.05;
  sum += texture(buffB, fract(vec2(uv.x, uv.y - 3.0*v)) ) * 0.09;
  sum += texture(buffB, fract(vec2(uv.x, uv.y - 2.0*v)) ) * 0.12;
  sum += texture(buffB, fract(vec2(uv.x, uv.y - 1.0*v)) ) * 0.15;
  sum += texture(buffB, fract(vec2(uv.x, uv.y + 0.0*v)) ) * 0.16;
  sum += texture(buffB, fract(vec2(uv.x, uv.y + 1.0*v)) ) * 0.15;
  sum += texture(buffB, fract(vec2(uv.x, uv.y + 2.0*v)) ) * 0.12;
  sum += texture(buffB, fract(vec2(uv.x, uv.y + 3.0*v)) ) * 0.09;
  sum += texture(buffB, fract(vec2(uv.x, uv.y + 4.0*v)) ) * 0.05;

  fragColor.xyz = sum.xyz/0.98; // normalize
  fragColor.a = 1.;
}


// *************** PASS 4 *****************
void mainImage4( out vec4 fragColor, in vec2 fragCoord ){
  vec2 uv = _uv;
  vec2 simRes = vec2(1600.0, 900.0);
  vec2 pixelSize = 1.0 / simRes.xy;
  vec2 aspect = vec2(1.0,simRes.y/simRes.x);

  vec2 lightSize=vec2(4.0);

  vec3 baseCol = vec3(1.0,0.3,0.1);
  vec3 newSpawnCol = vec3(0.15,0.1,0.05);
  vec3 topLightCol = vec3(0.1,0.9,0.8)*2.0;
  vec3 botLightCol = vec3(0.9,0.6,0.3)*1.5;
  vec3 motionCol = vec3(-0.3,-0.3,0.0);
  vec3 glowCol = vec3(0.0,0.9,0.7);

  float colMixer = color_palette;
  float mixer = smoothstep(0.25, 0.75, clamp(colMixer, 0.0, 1.0));

  float cm = clamp(mixer, 0.0, 1.0);
  // *** Color Regime 1 ***
  baseCol = mix(baseCol, vec3(1.1,0.55,0.1), cm);
  newSpawnCol = mix(newSpawnCol, vec3(1.1,0.75,0.1)*1.1, cm);
  topLightCol = mix(topLightCol, vec3(2.1,1.4,0.2)*1.1, cm);
  botLightCol = mix(botLightCol, vec3(0.9,0.0,0.6)*1.1, cm);
  motionCol = mix(motionCol, vec3(-1.0), cm);
  glowCol = mix(glowCol, mix(vec3(1.1,0.55,0.1), vec3(1.0,0.2,1.4), smoothstep(0.3,1.1,_uv.y)), cm)*0.95;

  colMixer = colMixer-1.0;
  mixer = smoothstep(0.25, 0.75, clamp(colMixer, 0.0, 1.0));
  cm = clamp(mixer, 0.0, 1.0);

  // *** Color Regime 2 ***
  baseCol = mix(baseCol, vec3(1.5,0.3,1.5)*1.0, cm);
  newSpawnCol = mix(newSpawnCol, vec3(0.2+(abs(_uvc.x*1.0))*0.2,0.0,0.8-0.65*(1.0-_uv.y*1.0))*1.5, cm);
  topLightCol = mix(topLightCol, vec3(0.6,0.7,1.0)*1.4, cm);
  botLightCol = mix(botLightCol, vec3(1.0,0.9,0.3)*1.4, cm);
  motionCol = mix(motionCol, vec3(1.0,0.77,0.0)*1.0, cm);
  glowCol = mix(glowCol, vec3(0.7+_uv.y*0.3,0.8-_uv.y*0.2,0.05)*1.0, cm);

  colMixer = colMixer-1.0;
  mixer = smoothstep(0.25, 0.75, clamp(colMixer, 0.0, 1.0));
  cm = clamp(mixer, 0.0, 1.0);


  // *** Color Regime 3 ***
  baseCol = mix(baseCol, _normalizeRGB(217, 0, 100)*2.0, cm);
  newSpawnCol = mix(newSpawnCol, _normalizeRGB(4, 117, 111)*1.8, cm);
  topLightCol = mix(topLightCol, _normalizeRGB(255, 75, 40)*2.0, cm);
  botLightCol = mix(botLightCol, _normalizeRGB(0, 140, 140)*2.0, cm);
  motionCol = mix(motionCol, _normalizeRGB(4, 117, 111)*2.0, cm);
  glowCol = mix(glowCol, _normalizeRGB(217, 200, 0)*1.0, cm);

  // lightSize = mix(lightSize, lightSize/pow(0.05+syn_HighLevel,5.0)*2.0, cm);
  // lightSize /= pow(syn_HighLevel,5.0)*2.0;

  colMixer = colMixer-1.0;
  mixer = smoothstep(0.25, 0.75, clamp(colMixer, 0.0, 1.0));
  cm = clamp(mixer, 0.0, 1.0);

  // *** Color Regime 4 ***
  baseCol = mix(baseCol, _normalizeRGB(100, 200, 100), cm);
  newSpawnCol = mix(newSpawnCol, _normalizeRGB(22, 127, 250)*2.0, cm);
  topLightCol = mix(topLightCol, _normalizeRGB(100, 76, 100)*2.0, cm);
  botLightCol = mix(botLightCol, _normalizeRGB(22, 127, 220)*2.0, cm);
  motionCol = mix(motionCol, _normalizeRGB(10, 30, 137)*2.0, cm);
  glowCol = mix(glowCol, _normalizeRGB(100, 200, 100), cm);

  // if (color_palette > _uv.x*5.0){
  //   fragColor = vec4(1.0);
  //   return;
  // }

    topLightCol *= 0.65;
    botLightCol *= 0.65;
    // topLightCol *= (0.6+0.4*sin(TIME+PI))*10.0;
    // botLightCol *= (0.6+0.4*sin(TIME))*10.0; 
  
  baseCol *= 1.5;

  // get the gradients from the blurred image
  vec2 d = pixelSize*2.0;
  vec4 dx = (texture(buffC, uv + vec2(1,0)*d) - texture(buffC, uv - vec2(1,0)*d))*0.5;
  vec4 dy = (texture(buffC, uv + vec2(0,1)*d) - texture(buffC, uv - vec2(0,1)*d))*0.5;

  // // add the pixel gradients
  d = pixelSize;
  dx += texture(buffA2, uv + vec2(1,0)*d) - texture(buffA2, uv - vec2(1,0)*d);
  dy += texture(buffA2, uv + vec2(0,1)*d) - texture(buffA2, uv - vec2(0,1)*d);

  vec2 lightMirPos = uv;
  if (_uv.x > 0.5){
    lightMirPos.x = 1.0-lightMirPos.x;
  }

  float lightsPos = syn_Time*0.1+syn_HighTime*0.1;

  // vec2 lightPos1 = mix(vec2(0.5, 1.0), vec2(0.5, 0.75)
  //   vec2(
  //     0.25+cos(lightsPos*0.5)*0.65, 
  //     0.5+sin(lightsPos*0.75)*0.65), lights_rot*0.0);
  // vec2 lightPos2 = mix(vec2(0.25, -1.0), 
  //   vec2(
  //     0.25+cos(lightsPos*0.65+PI/2)*0.65, 
  //     0.5+sin(lightsPos*0.85+PI)*0.65), lights_rot*0.0);
  vec2 lightPos1 = mix(vec2(0.5, 1.0), vec2(0.5, 0.75), lights_rot);
  vec2 lightPos2 = mix(vec2(0.25, -1.0), vec2(0.4, -0.75), lights_rot);
  lightPos1 = mix(lightPos1, _rotate(lightPos1*0.85, lightsPos), lights_rot);
  lightPos2 = mix(lightPos2, _rotate(lightPos2*0.85, lightsPos), lights_rot);

  vec2 displacement = vec2(dx.x,dy.x)*lightSize; // using only the red gradient as displacement vector
  // float light = pow(max(1.-distance(0.5+(uv-0.5)*aspect*lightSize + displacement*5.0,vec2(0.5)),0.),2.);
  float light1 = 2.-distance(0.5+(lightMirPos-lightPos1)*aspect*lightSize + displacement*5.0,vec2(0.5,1.5));
  light1 = max(light1,0.0);

  float light2 = 2.-distance(0.5+(lightMirPos-lightPos2)*aspect*lightSize + displacement*5.0,vec2(0.5,1.5));
  light2 = max(light2,0.0);

  // recolor the red channel
  vec3 surface = vec3(texture(buffA2,uv+vec2(dx.x,dy.x)*pixelSize*10.0).r);

  // float hasMedia = min(syn_MediaType, 1.0);
  // float sur2 = 0.0;
  // if(hasMedia<0.5){
  //   sur2 = pow(surface.r,2.0);
  // }

  float edgesOg = texture(buffA2,uv+vec2(dx.x,dy.x)*mix(pixelSize, pixelSize/pixelSize.y, soft_flat*0.6)).r;
  vec3 edges = vec3(pow(edgesOg,1.0+20.0*(1.0-0.5*soft_flat)));
  // glowCol = _grad3(glowCol, motionCol, topLightCol, edges.r*5.0);
  // float nrm = length(vec2(dx.x,dy.x))+length(vec2(dx.y,dy.y));
  // baseCol = _grad3(baseCol, baseCol, vec3(1.0), nrm*1000.0);
  vec2 flashingLights = vec2(1.4, 1.4);
  if (flashing_lights > 0.5){
    flashingLights = vec2(0.3+syn_HighHits*1.4, 0.4+pow(syn_BassLevel,2.0)*1.4);
  }
  vec3 lightCol = topLightCol*light1*flashingLights.r + botLightCol*light2*flashingLights.g;
  lightCol *= 1.0;

  // and add the light map
  vec3 finalColor = surface*baseCol + lightCol;
  // finalColor += (sur2*(light1)+sur2*(light2))*newSpawnCol*30.0;

  float darkener = (1.-texture(buffA2,uv+vec2(dx.x,dy.x)*pixelSize*lightSize.x).x);
  finalColor -= darkener;

  float newSpawn = clamp(texture(buffA2, _uv).r,0.0,1.0);
  finalColor = mix(finalColor, edges*newSpawnCol, newSpawn);

  // finalColor = vec3(newSpawn);
  //   fragColor = vec4(finalColor, 1.0);
  // float hasMedia = min(syn_MediaType, 1.0);

  // if(hasMedia<0.5){
  //   newSpawn = pow(clamp(texture(buffA2, _uv).r,0.0,1.0),0.2);
  //   finalColor += newSpawn*glowCol;
  // }
  // return;

  float recentlyTouched = texture(buffA2, _uv).g;
  // finalColor = mix(finalColor, finalColor*dot(_loadUserImage().rgb*pow(recentlyTouched,10.0), vec3(1.0))/3.0, 0.0);
  // finalColor = mix(finalColor, motionCol, recentlyTouched*0.4);

  // if (color_inv>0.5){
  //   finalColor = pow(finalColor, vec3(1.000001));
  // }

  // finalColor += vec3(0.3,1.0,0.0)*abs(_uvc.y)*dot(vec3(1.0),finalColor)*1.0;

  // finalColor -= _loadUserImage().rgb*(0.7+syn_BassLevel*0.6);

  finalColor += (pow(recentlyTouched,2.0))*glowCol*2.5*pow(1.0-edgesOg,1.5);

  fragColor = vec4(finalColor, 1.0);
  // fragColor = vec4(texture(buffA2, uv));
}

vec4 renderMain(void)
{
  if (PASSINDEX == 0.0){
    //buffA2
    vec4 fragColor = vec4(0.0);
    mainImage0(fragColor, gl_FragCoord.xy);
    return fragColor;
  }
  else if (PASSINDEX == 1.0){
    //buffB
    return texture(buffA, _uv);
  }
  else if (PASSINDEX == 2.0){
    //buffB
    vec4 fragColor = vec4(0.0);
    horizontalBlur(fragColor, gl_FragCoord.xy);
    return fragColor;
  }
  else if (PASSINDEX == 3.0){
    //buffC
    vec4 fragColor = vec4(0.0);
    verticalBlur(fragColor, gl_FragCoord.xy);
    return fragColor;
  }
  else if (PASSINDEX == 4.0){
    //Image
    vec4 fragColor = vec4(0.0);
    mainImage4(fragColor, gl_FragCoord.xy);
    // return texture(buffC, _uv);
    vec4 final = fragColor;
    // final = vec4(texture(buffA, _uv).b);
    return final;
  }
}
