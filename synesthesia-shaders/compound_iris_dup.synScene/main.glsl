float time = syn_BPMTwitcher;
float jitter = sin(TIME*80.)*.1*pow((1.-fract(syn_BPMTwitcher)),1.)*syn_BassPresence;
vec2 mouse = vec2(0.5);
vec2 resolution = RENDERSIZE;

vec3 filmGrain(vec2 uv, float strength ){       
    float x = (uv.x + 4.0 ) * (uv.y + 4.0 ) * (TIME * 10.0);
  return  vec3(mod((mod(x, 13.0) + 1.0) * (mod(x, 123.0) + 1.0), 0.01)-0.005) * strength;

}

float sdf_smin(float a, float b, float k)
{
  float res = exp(-k*a) + exp(-k*b);
  return -log(max(0.0001,res)) / k;
}

float sdf_circ(vec2 pos, float rad)
{
  float r = distance(pos, vec2(0));
  return r-rad;
} 

float sdf_ring(vec2 pos, float rad)
{
  float thick = rad*.1*radius_ring;
  return length( vec2(length(pos)-rad) )-thick;
}

vec4 genObject() {
  vec2 pos = gl_FragCoord.xy / resolution - vec2(0.5, 0.5);
  pos.x *= resolution.x/resolution.y;
  
  vec3 color = vec3(0.0);
  
  float d = sdf_ring(pos, 0.05+pow(syn_MidPresence,4.0)*0.4);

  float ringTime = mod(floor(syn_BPMTwitcher), 8);
  if (motion_style < 0.5){
    ringTime = 8.0;
    jitter = syn_BassPresence*0.5;
    time = syn_CurvedTime*0.1;
  }

  for(int i=0; i<1+ringTime; i++)
  {
    float offset = float(i)/8.0*6.28;
    if (mod(i, 2)==0){
      offset+=PI;
    }
    float size = (0.1 + sin(offset*2.0+time*3.0)*0.05 + jitter*0.8);
    float next = sdf_ring(pos+vec2(sin(time+offset)*.3, cos(time+offset)*.3), size)*1.0;
    d = sdf_smin(d, next, 32.0-syn_BPMSin2*20.0);
    d = clamp(d, -100.0, 100.0);
  }

    color.r = 1.0;
    color.g = (1.0+d*10.0)*syn_HighPresence;
    color.b = 0.25;
    if (colorMode >= 1.0){
      color = color.gbr;
    } else if (colorMode >= 2.0){
      color = color.brg;
    }

    color *= smoothstep(0.01+blur_amount*0.1, 0.001, d);

  if (colored < 0.5){
    color = vec3(length(color));
  }

  color = mix(color, color-color*filmGrain(_uv*0.5,3.0)*100.0, syn_HighHits*syn_HighPresence);

  return vec4(color, d);
}


//Triangle Pass

float rando(float n)
{
  return fract(abs(sin(n*55.753)*367.34));   
}
float rando(vec2 n)
{
    return rando(dot(n,vec2(2.46,-1.21)));
}
float cycle(float n)
{
  return cos(fract(n)*2.0*3.141592653)*0.5+0.5;
}
float genTris(float size, vec2 motion)
{
  float a = radians(30+30*refract_angle);
  float zoom = size-size*zoomAmt*0.5;
  if (RENDERSIZE.x<1300){
    zoom *= 0.5;
  }
  vec2 c = (_uv*RENDERSIZE + motion );
  
  c = ((c+vec2(c.y,0.0)*cos(a))/zoom)+vec2(floor((c.x-c.y*cos(a))/zoom),0.0);

  float n = cycle(rando(floor(c*3.0))*0.2+rando(floor(c*2.0))*0.3+rando(floor(c))*0.5+surface_pulse);
  c = c*fract(_toPolar(_uvc).y*rando(floor(c*0.5)));
  float n2 = cycle(rando(floor(c*3.0))*0.2+rando(floor(c*2.0))*0.3+rando(floor(c))*0.5+surface_pulse);
  n = mix(n, n2, surface_fracture);
  n = mix(sqrt(n), n*0.5, surface_pulse);

  return n;
}

vec4 secondPass(){
  vec4 retCol;
  if (_isMediaActive()){
    retCol = _loadMediaAsMask();
  } else {
    float tris = genTris(400, vec2(sin(TIME*0.011), cos(TIME*0.0093))*3000.0);
    //tris *= syn_Presence;
    retCol = vec4(tris);
  }
  return retCol;
}




//Chromatic Aberration

float linterp( float t ) {
  return clamp( 1.0 - abs( 2.0*t - 1.0 ), 0.0, 1.0 );
}

float remap( float t, float a, float b ) {
  return clamp( (t - a) / (b - a), 0.0, 1.0 );
}
vec2 remap( vec2 t, vec2 a, vec2 b ) {
  return clamp( (t - a) / (b - a), 0.0, 1.0 );
}

vec3 spectrum_offset_rgb( float t ) {
  vec3 ret;
  float lo = step(t,0.5);
  float hi = 1.0-lo;
  float w = linterp( remap( t, 1.0/6.0, 5.0/6.0 ) );
  ret = vec3(lo,1.0,hi) * vec3(1.0-w, w, 1.0-w);

    return ret;
    //return smoothstep( vec3(0.0), vec3(1.0), ret );
    //return pow( ret, vec3(1.0/2.2) );
}

const float gamma = 2.2;
vec3 lin2srgb( vec3 c )
{
    return pow( c, vec3(gamma) );
}
vec3 srgb2lin( vec3 c )
{
    return pow( c, vec3(1.0/gamma));
}


vec3 yCgCo2rgb(vec3 ycc)
{
    float R = ycc.x - ycc.y + ycc.z;
  float G = ycc.x + ycc.y;
  float B = ycc.x - ycc.y - ycc.z;
    return vec3(R,G,B);
}

vec3 spectrum_offset_ycgco( float t )
{
  //vec3 ygo = vec3( 1.0, 1.5*t, 0.0 ); //green-pink
    //vec3 ygo = vec3( 1.0, -1.5*t, 0.0 ); //green-purple
    vec3 ygo = vec3( 1.0, 0.0, -1.25*t ); //cyan-orange
    //vec3 ygo = vec3( 1.0, 0.0, 1.5*t ); //brownyello-blue
    return yCgCo2rgb( ygo );
}

vec3 yuv2rgb( vec3 yuv )
{
    vec3 rgb;
    rgb.r = yuv.x + yuv.z * 1.13983;
    rgb.g = yuv.x + dot( vec2(-0.39465, -0.58060), yuv.yz );
    rgb.b = yuv.x + yuv.y * 2.03211;
    return rgb;
}


// ====

vec2 distort( vec2 uv, float t, vec2 min_distort, vec2 max_distort )
{
    vec2 dist = mix( min_distort, max_distort, t );
    // return radialdistort( uv, 2.0 * dist );
    // return barrelDistortion( uv, 1.75 * dist ); //distortion at center
    // return brownConradyDistortion( uv, 75.0 * dist.x );

    float triPattern = texture(secondBuffer,_uv).r*refraction;
    // float dxTri = dFdx(triPattern)+dFdy(triPattern);

    return uv+normalize(_uvc)*t*0.002*(1.0+syn_MidPresence)*(1.0+triPattern*3.0)*(1.0+aberration);
}

// ====

vec3 spectrum_offset_yuv( float t )
{
  //vec3 yuv = vec3( 1.0, 3.0*t, 0.0 ); //purple-green
    //vec3 yuv = vec3( 1.0, 0.0, 2.0*t ); //purple-green
    vec3 yuv = vec3( 1.0, 0.0, -1.0*t ); //cyan-orange
    //vec3 yuv = vec3( 1.0, -0.75*t, 0.0 ); //brownyello-blue
    return yuv2rgb( yuv );
}

vec3 spectrum_offset( float t )
{
    return spectrum_offset_rgb( t );
    //return srgb2lin( spectrum_offset_rgb( t ) );
    //return lin2srgb( spectrum_offset_rgb( t ) );

    //return spectrum_offset_ycgco( t );
    //return spectrum_offset_yuv( t );
}

// ====

float nrand( vec2 n )
{
  return fract(sin(dot(n.xy, vec2(12.9898, 78.233)))* 43758.5453);
}

vec3 render( vec2 uv )
{
  
    float triPattern = texture(secondBuffer,_uv).r*refraction;

    return srgb2lin(texture(firstBuffer, uv+(triPattern*0.05-0.025)).rgb );
}

vec4 chromaticAberration()
{ 
  vec2 uv = _uv;
    
  const float MAX_DIST_PX = 40.0;
  float max_distort_px = MAX_DIST_PX * (1.0-0.0/RENDERSIZE.x);
  vec2 max_distort = vec2(max_distort_px) / RENDERSIZE.xy;
  vec2 min_distort = 0.5 * max_distort;

  //vec2 oversiz = vec2(1.0);
  vec2 oversiz = distort( vec2(1.0), 1.0, min_distort, max_distort );
  uv = remap( uv, 1.0-oversiz, oversiz );

  vec3 sumcol = vec3(0.0);
  vec3 sumw = vec3(0.0);
  float rnd = nrand( uv + fract(TIME) );
  const int num_iter = 5;

  for ( int i=0; i<num_iter;++i ) {
    float t = (float(i)+rnd) / float(num_iter-1);
    vec3 w = spectrum_offset( t );
    sumw += w;
    vec2 uvd = distort(uv, t, min_distort, max_distort); //TODO: move out of loop
    sumcol += w * render(uvd);
  }

  sumcol.rgb /= sumw;
  
  vec3 outcol = sumcol.rgb;
  outcol = lin2srgb( outcol );
  outcol += rnd/255.0;

  // vec3 noise = filmGrain(_uv,20.0);
  //   outcol += noise*2.0;

  return vec4( outcol, 1.0);
}

// vec3 render2( vec2 uv )
// {
  
//     // float triPattern = texture(secondBuffer,_uv).r;

//     return srgb2lin(texture(forChromaticAberr, uv).rgb );
// }

// vec4 chromaticAberration2()
// { 
//   vec2 uv = _uv;
    
//   const float MAX_DIST_PX = 40.0;
//   float max_distort_px = MAX_DIST_PX * (1.0-0.0/RENDERSIZE.x);
//   vec2 max_distort = vec2(max_distort_px) / RENDERSIZE.xy;
//   vec2 min_distort = 0.5 * max_distort;

//   //vec2 oversiz = vec2(1.0);
//   vec2 oversiz = distort( vec2(1.0), 1.0, min_distort, max_distort );
//   uv = remap( uv, 1.0-oversiz, oversiz );

//   vec3 sumcol = vec3(0.0);
//   vec3 sumw = vec3(0.0);
//   float rnd = nrand( uv + fract(TIME) );
//   const int num_iter = 5;

//   for ( int i=0; i<num_iter;++i ) {
//     float t = (float(i)+rnd) / float(num_iter-1);
//     vec3 w = spectrum_offset( t );
//     sumw += w;
//     vec2 uvd = distort(uv, t, min_distort, max_distort); //TODO: move out of loop
//     sumcol += w * render2(uvd);
//   }

//   sumcol.rgb /= sumw;
  
//   vec3 outcol = sumcol.rgb;
//   outcol = lin2srgb( outcol );
//   outcol += rnd/255.0;

//   // vec3 noise = filmGrain(_uv,20.0);
//   //   outcol += noise*2.0;

//   return vec4( outcol, 1.0);
// }


float weight[5] = float[] (0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

vec4 gaussianBlur(bool horizontal, sampler2D image)
{             
    vec2 tex_offset = 1.0 / textureSize(image, 0); // gets size of single texel
    vec3 result = texture(image, _uv).rgb * weight[0]; // current fragment's contribution
    tex_offset *= filmGrain(_uv,20.0).xy;
    float triBlur = texture(secondBuffer, _uv).a * weight[0];

    if(horizontal)
    {
        for(int i = 1; i < 5; ++i)
        {
            result += texture(image, _uv + vec2(tex_offset.x * i * 2, 0.0)).rgb * weight[i];
            result += texture(image, _uv - vec2(tex_offset.x * i * 2, 0.0)).rgb * weight[i];
            triBlur += texture(secondBuffer, _uv + vec2(tex_offset.x * i * 2, 0.0)).r * weight[i];
            triBlur += texture(secondBuffer, _uv - vec2(tex_offset.x * i * 2, 0.0)).r * weight[i];
        }
    }
    else
    {
        for(int i = 1; i < 5; ++i)
        {
            result += texture(image, _uv + vec2(0.0, tex_offset.y * i * 2)).rgb * weight[i];
            result += texture(image, _uv - vec2(0.0, tex_offset.y * i * 2)).rgb * weight[i];
            triBlur += texture(secondBuffer, _uv + vec2(0.0, tex_offset.y * i * 2)).r * weight[i];
            triBlur += texture(secondBuffer, _uv - vec2(0.0, tex_offset.y * i * 2)).r * weight[i];
        }
    }
    // triBlur = texture(secondBuffer, _uv).a;

    return vec4(result, triBlur);
}

vec4 lastPass(){
  vec4 initialImg = texture(firstBuffer, _uv);
  vec4 distortedImg = texture(forHorBlur, _uv);
  vec4 blurredImg = texture(forLastPass, _uv);

   
  // vec3 noise = filmGrain(_uv,50.0);
  // triPattern.rgb += noise;
  float lightLines = 0.0;
  if (!_isMediaActive()){
    vec2 lightPos = vec2(sin(syn_Time*0.05), cos(syn_Time*0.05))*0.8;
    vec2 derivs = vec2(dFdy(-blurredImg.a),dFdy(blurredImg.a));
    lightLines = length(derivs);
    // float deriv = dot(vec2(clamp(dFdx(blurredImg.a)+dFdy(blurredImg.a),0.0,1.0),clamp(dFdx(-blurredImg.a)+dFdy(-blurredImg.a),0.0,1.0)),lightPos);
    lightLines *= 2.0*(0.2+syn_HighPresence);
    lightLines /= (0.5+distance(_uvc, lightPos)*2.5);
    lightLines*=(1.0+surface_pulse*5.0);
  }
  vec4 finalCol = blurredImg+lightLines*clamp(refraction,0.0,3.0);


  if (invert > 0.5){
    finalCol = 1.0-finalCol;
  }
  float fbm = _fbm(_uvc*10.0);
  finalCol += step(1.0-syn_HighPresence*0.1,fract(texture(secondBuffer, _uv)+syn_BeatTime*0.01))*(1.0-pow(distance(_uvc, vec2(sin(TIME), cos(syn_BassTime))),fbm*fbm));
  finalCol *= syn_FadeInOut;

  return finalCol;
}

vec4 renderMain () {
 if (PASSINDEX == 0.0){
    return genObject();
  }
  else if (PASSINDEX == 1.0){
    return secondPass();
  } 
  else if (PASSINDEX == 2.0){
    return chromaticAberration();
  } 
  else if (PASSINDEX == 3.0){
    return gaussianBlur(true, forHorBlur);
  }  
  else if (PASSINDEX == 4.0){
    return gaussianBlur(false, forVertBlur);
  }   
  else if (PASSINDEX == 5.0){
    return lastPass();
  } 
  return vec4(1.0, 0.0, 0.0, 1.0);
}
