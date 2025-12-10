vec3 iResolution = vec3(RENDERSIZE.x, RENDERSIZE.y, 0.0);
vec3 iChannelResolution = iResolution;
float iGlobalTime = TIME*1.0;
int iFrame = int(FRAMECOUNT);
float time = TIME;
vec2 resolution = RENDERSIZE;
vec4 iMouse = vec4(0.5);

vec3 hsv(float h,float s,float v) {
  return mix(vec3(1.),clamp((abs(fract(h+vec3(3.,2.,1.)/3.)*6.-3.)-1.),0.,1.),s)*v;
}
float circle(vec2 p, float r) {
  return smoothstep(0.1+syn_Presence*0.3, 0.0, abs(length(p)-r)); // try changing the 0.1 to 0.3
}
float r3 = sqrt(3.0);
vec4 pulseCircles(vec2 uv) {
  // vec2 uv = -1.0 + 2.0*_xy.xy / RENDERSIZE.xy;
  // uv.x *= RENDERSIZE.x/RENDERSIZE.y;
  uv *= 10.0;
  float r = smoothstep(-0.7, 0.7, sin(random_spot*2.57-length(uv)*0.1))+1.0;
  vec2 rep = vec2(4.0,r3*4.0);
  vec2 p1 = mod(uv, rep)-rep*0.5;
  vec2 p2 = mod(uv+vec2(2.0,0.0), rep)-rep*0.5;
  vec2 p3 = mod(uv+vec2(1.0,r3), rep)-rep*0.5;
  vec2 p4 = mod(uv+vec2(3.0,r3), rep)-rep*0.5;
  vec2 p5 = mod(uv+vec2(0.0,r3*2.0), rep)-rep*0.5;
  vec2 p6 = mod(uv+vec2(2.0,r3*2.0), rep)-rep*0.5;
  vec2 p7 = mod(uv+vec2(1.0,r3*3.0), rep)-rep*0.5;
  vec2 p8 = mod(uv+vec2(3.0,r3*3.0), rep)-rep*0.5;
  
  float c = 0.0;
  c += circle(p1, r);
  c += circle(p2, r);
  c += circle(p3, r);
  c += circle(p4, r);
  c += circle(p5, r);
  c += circle(p6, r);
  c += circle(p7, r);
  c += circle(p8 , r);
  return vec4(hsv(r+0.7, 1.0, c), 1.0);
}

vec4 renderPass()
{
    vec4 fragColor = vec4(0.0);
    float zoom = 0.5;
    vec2 uv = zoom * (_xy - RENDERSIZE.xy / 2.0);
        
    float time = syn_HighTime * 3.1415 * 0.05;
    
    // uv += move_in;
    
    float pi = acos(-1.);
   
    float m = 1.;
    float n = 8.;
    float p = 1.;
    
    float img = 0.0;

    if (_isMediaActive()){
      img = dot(_loadMedia().rgb, vec3(1.0))/3.0;   
    }
    
    int points = 2+int(stacked_layers);
    const int iters = 8;
    float value = 0.;
    float value2 = 0.;
    float value3 = 0.;
    vec3 value4 = vec3(1.0,0.0,syn_BassLevel);

    vec2 uv2 = uv;

    vec2 oldVal = vec2(0.0);


    for(int j = 0; j < iters; j++){
      // time = mix(time, -time, mod(j, 2));
      // uv2 = _rotate(uv2, syn_Time*0.01*j);
      uv = _rotate(uv, 100.0*j+spin)*(1.0+length(uv)*0.0005*distortion);
      uv += move_xy;
      uv2 = _rotate(uv2, 100.0*j+spin)*(1.0+length(uv2)*0.0005*distortion);
      uv2 += move_xy*0.1;
      uv.y += img*10.0;

      for(int i = 0; i < points ; i++){
              uv.y += img*1.0;

        float zoom = mod(script_bass_time*0.2+j,iters);
        // zoom -= img.r;

        float angle = pi / float(points) * float(i);
        float w = uv.x * sin(angle) + uv.y * cos(angle);
        float w2 = uv2.x * sin(angle) + uv2.y * cos(angle);

        // w /= random_spot;

        float divisor = 1.0+pow(zoom,3.0);
        float mixer = (1.0-smoothstep(iters-2, iters-1, zoom))*smoothstep(0, 1, zoom);

        w /= divisor;
        w2 /= divisor;

        // w /= ((-0.5+random_spot)*4.0+_uvc.y*2.0);

        float sinHolder = sin(w + time + syn_BassPresence);
        float sinHolder2 = sin(w2 + time + random_spot*i);

        // sinHolder = -1.0+2.0*step(sinHolder, 0.0);
        // sinHolder = sinHolder;

        value += sinHolder*mixer;
        value2 += smoothstep(sinHolder2, 0.0, 0.1)*mixer;
        // value3 += pow(oldVal.x, 2.0);
        value3 += _pulse(value, 0.1+syn_Presence, 0.1);
        value4 = mix(value4, cross(value4+syn_Presence*0.2, vec3(sinHolder, sinHolder2, 0.5)), mixer);
      };

      oldVal = vec2(value, value3);
    }
       
    value /= iters;
    value2 /= iters;
    // value3 /= iters;

    // value2 = step(1.0-value2, 0.0);
    
    float geometry = (sin(value * pi / 2.) + 1.) * 0.5;
    float goop = (sin(value2 * pi / 2.) + 1.) * 0.5;
    // float fractal = (sin(value3 * pi / 2.) + 1.) * 0.5;
    float fractal = value3;
    // goop = value2;

    goop = clamp(goop, 0.0, 1.0);
    fractal = clamp(fractal, 0.0, 1.0);


    fragColor = vec4(geometry, fractal, 0.5+0.5*cos(value*10.0+uv2.y*0.01), goop);


    fragColor = mix(fragColor, vec4(abs(min(value4,2.0)),1.0), pearlescence);
    // fragColor = vec4(abs(value4), 1.0);
    // fragColor.a = goop;
    return fragColor;

}



vec4 renderMain(void)
{
  if (PASSINDEX == 0.0){
    return renderPass();
  } else if (PASSINDEX == 1.0){
    vec4 data = texture(firstBuff, _uv);
    
    float v = 0.0;
    float patSel = pattern;
    float patMix = smoothstep(0.25, 0.75, clamp(patSel, 0.0, 1.0));
    v = mix(data.r, data.b, patMix);
    patSel -= 1.0;
    patMix = smoothstep(0.25, 0.75, clamp(patSel, 0.0, 1.0));
    v = mix(v, clamp(data.a,0.0,1.0), patMix);
    patSel -= 1.0;
    patMix = smoothstep(0.25, 0.75, clamp(patSel, 0.0, 1.0));
    v = mix(v, clamp(data.g,0.0,1.0), patMix);

    // finalCol += data.g*vec4(1.0);
    // finalCol += clamp(data.b,0.0,1.0)*vec4(1.0,0.0,0.0,1.0);
    // v += clamp(data.a,0.0,1.0);

    // slight vignetting
    v *= exp(-0.6 * length(_uvc)) * 1.2;
    
    vec2 colPos = _uv + vec2(sin(TIME*0.1), cos(TIME*0.2))*10.0;

    // use texture channel0 for color? why not.
    vec3 cexp = texture(colorNoise, colPos * 0.001).xyz * 3.0 + texture(colorNoise, colPos * 0.01).xyz;//vec3(1.0, 2.0, 4.0);
    cexp *= 1.4;
    
    vec3 finalCol = vec3(pow(v, cexp.x), pow(v, cexp.y), pow(v, cexp.z)) * 2.0;

    // finalCol.rgb = _rgb2hsv(finalCol.rgb);
    // // finalCol.r += data.g;
    // finalCol.r += clamp(data.b,0.0,1.0);
    // finalCol.g += clamp(data.b,0.0,1.0);
    // finalCol.b -= clamp(data.b,0.0,1.0);

    finalCol *= (0.5+0.5*pulseCircles(_uvc*1.5 + v).rgb);

    finalCol = mix(finalCol, data.rgb, pearlescence);
    return vec4(finalCol,1.0);
  }
}
