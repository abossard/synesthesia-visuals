vec3 threeColMix(vec3 col1, vec3 col2, vec3 col3, float mixVal){
    mixVal *= 2.0;
    float mix1 = clamp(mixVal,0.0,1.0);
    float mix2 = clamp(mixVal-1.0, 0.0, 1.0);
    return mix(mix(col1, col2, mix1), mix(col2, col3, mix2), step(1.0, mixVal));
}

// ****************** PASS 0 ***********************
#define pi2_inv 0.159154943091895335768883763372

vec2 lower_left(vec2 uv)
{
    return fract(uv * 0.5);
}

vec2 lower_right(vec2 uv)
{
    return fract((uv - vec2(1, 0.)) * 0.5);
}

vec2 upper_left(vec2 uv)
{
    return fract((uv - vec2(0., 1)) * 0.5);
}

vec2 upper_right(vec2 uv)
{
    return fract((uv - 1.) * 0.5);
}


vec4 BlurB(vec2 uv, int level)
{
    if(level <= 0)
    {
        return texture(buffB2, fract(uv));
    }

    uv = lower_left(uv);
    for(int depth = 1; depth < 8; depth++)
    {
        if(depth >= level)
        {
            break;
        }
        uv = lower_right(uv);
    }
    vec4 col = texture(buffD, uv);
    // col = mix(col, col.barg, color_layer);
    return col;
}

vec2 GradientB(vec2 uv, vec2 d, vec4 selector, int level){
    vec4 dX = 0.5*BlurB(uv + vec2(1.,0.)*d, level) - 0.5*BlurB(uv - vec2(1.,0.)*d, level);
    vec4 dY = 0.5*BlurB(uv + vec2(0.,1.)*d, level) - 0.5*BlurB(uv - vec2(0.,1.)*d, level);
    // dX = mix(dX, dX.barg, color_layer);
    // dY = mix(dY, dY.barg, color_layer);
    return vec2( dot(dX, selector), dot(dY, selector) );
}


vec2 rot90(vec2 vector){
    return vector.yx*vec2(1,-1);
}

vec2 complex_mul(vec2 factorA, vec2 factorB){
    return vec2( factorA.x*factorB.x - factorA.y*factorB.y, factorA.x*factorB.y + factorA.y*factorB.x);
}

vec2 spiralzoom(vec2 domain, vec2 center, float n, float spiral_factor, float zoom_factor, vec2 pos){
    vec2 uv = domain - center;
    float d = length(uv);
    return vec2( atan(uv.y, uv.x)*n*pi2_inv + d*spiral_factor, -log(d)*zoom_factor) + pos;
}

vec2 complex_div(vec2 numerator, vec2 denominator){
    return vec2( numerator.x*denominator.x + numerator.y*denominator.y,
                numerator.y*denominator.x - numerator.x*denominator.y)/
        vec2(denominator.x*denominator.x + denominator.y*denominator.y);
}

float circle(vec2 uv, vec2 aspect, float scale){
    return clamp( 1. - length((uv-0.5)*aspect*scale), 0., 1.);
}

float sigmoid(float x) {
    return 2./(1. + exp2(-x)) - 1.;
}

float smoothcircle(vec2 uv, vec2 aspect, float radius, float ramp){
    return 0.5 - sigmoid( ( length( (uv - 0.5) * aspect) - radius) * ramp) * 0.5;
}

float conetip(vec2 uv, vec2 pos, float size, float min)
{
    vec2 aspect = vec2(1.,RENDERSIZE.y/RENDERSIZE.x);
    return max( min, 1. - length((uv - pos) * aspect / size) );
}

float warpFilter(vec2 uv, vec2 pos, float size, float ramp)
{
    return 0.5 + sigmoid( conetip(uv, pos, size, -16.) * ramp) * 0.5;
}

vec2 vortex_warp(vec2 uv, vec2 pos, float size, float ramp, vec2 rot)
{
    vec2 aspect = vec2(1.,RENDERSIZE.y/RENDERSIZE.x);

    vec2 pos_correct = 0.5 + (pos - 0.5);
    vec2 rot_uv = pos_correct + complex_mul((uv - pos_correct)*aspect, rot)/aspect;
    float f1lter = warpFilter(uv, pos_correct, size, ramp);
    return mix(uv, rot_uv, f1lter);
}

vec2 vortex_pair_warp(vec2 uv, vec2 pos, vec2 vel)
{
    vec2 aspect = vec2(1.,RENDERSIZE.y/RENDERSIZE.x);
    float ramp = 4.;

    float d = 0.425;

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

vec2 kaleidoscope(vec2 uvIn, float n) {
  vec2 uv = uvIn;
  float angle = PI/n;
  
  float r = length(uv);
  float a = atan(uv.y, uv.x)/angle;
  
  a = mix(fract(a), 1.0 - fract(a), mod(floor(a), 2.0))*angle;
  
  return vec2(cos(a), sin(a))*r;
}

vec2 autoSliceTransform(vec2 uv)
{
    vec2 diagPos = _rotate(_uvc, PI*0.25);
    float gridderX = floor(mod(diagPos.x*30.0*0.35,2.0));
    float gridderY = floor(mod(diagPos.y*20.0*0.35,2.0));
    float tinyGridX = floor(mod(diagPos.x*30.0*0.35,2.0));
    float tinyGridY = floor(mod(diagPos.y*40.0*0.35,2.0));
    int beatMode = int(mod(syn_BeatTime,4.0));
    float singer = -1+2.0*floor(mod(syn_BeatTime*0.5,2.0));

    vec2 gridder;

    switch(beatMode)
    {
    case 0: gridder = gridderX*vec2(0.0,1.0); break;
    case 1: gridder = gridderY*vec2(1.0,0.0); break;
    case 2: gridder = tinyGridX*vec2(0.0,1.0); break;
    case 3: gridder = tinyGridY*vec2(1.0,0.0); break;
    }
// gridder = _rotate(gridder, PI*0.25);
    return uv+gridder*pow(syn_HighHits,2.0)*0.01*singer*pow(syn_HighPresence+syn_BassPresence,2.0);
}

// *************** PASS 0 *****************
// Turing Sim

void mainImage1( inout vec4 fragColor, in vec2 fragCoord )
{
    vec4 data = vec4(0.0);
    data.a = dot(_loadUserImage().rgb,vec3(1.0))/3.0;
    float mask = 1.0;
    float flashing = flashing;
    // float paint_on = paint_on;
    // auto_slice = data.g;

    vec2 uv = fragCoord.xy / RENDERSIZE.xy;
    vec4 noise = texture(colornoise, fragCoord.xy / RENDERSIZE.xy + fract(vec2(42,56)*TIME));
    vec4 prev = texture(buffB2, uv);

    if((FRAMECOUNT<10)||(reset_sim>0.5))
    {
        fragColor = noise*mask;
        return;
    }

    // float zoomAmt = 0.999+(inOrOut*(1.0-abs(in_out))+in_out*2.0)*0.0045*pow(syn_BassLevel,2.0);
    float zoomAmt = 1.0+zoom_in_out*0.01+bass_zoom*0.02*pow(syn_BassLevel,2.0);


    uv = 0.5 + (uv - 0.5)*zoomAmt;

    vec2 pixelSize = 1./RENDERSIZE.xy;
    vec2 aspect = vec2(1.,RENDERSIZE.y/RENDERSIZE.x);
    if (auto_slice > 0.5){
        uv = autoSliceTransform(uv);
    }

    //uv = uv - vec2(0.0,GradientB(uv, pixelSize, vec4(-128,-128.,-128.,-128.), 1)*syn_HighHits*0.0001);
    float logo = dot(_loadUserImage().rgb, vec3(1.0))*1.0;

    uv -= vec2(-_uvc.x*0.0075*syn_BassHits, _uvc.y*0.015*syn_HighHits)*(1.0-logo)*rising;

    if (uv != clamp(uv, 0.0, 1.0)){
        uv = uv*0.8;
    }

    float fbmmer = _fbm(_uvc*20.0-vec2(0.0,syn_BassTime*0.15));
    float fbmmer2 = _fbm(_uvc*4.0-vec2(0.0,syn_MidTime*0.21));
    vec2 roto = _rotate(vec2(pow(0.75+syn_MidLevel*0.25,2.0)*2.0,0.0), fbmmer*1*PI+fbmmer2*2*PI+syn_HighTime*0.35);
    // vec2 roto = _rotate(vec2(1.0,0.0), prev.g*16*PI);
    uv -= roto*extra_liquid*extra_liquid*0.005;
    // uv += roto*0.01*extra_liquid;
    uv += _rotate(vec2(1.0,0.0), 3*PI*_fbm(vec3(_uvc*0.75, syn_BassTime*0.4)))*0.0035*warper*pow(syn_BassLevel, 1.5);

    uv += prev.r*_rotate(vec2(1.0,0.0), 4*PI*pow(_fbm(vec3(_uvc*4.0, syn_MidHighTime)), 2.0))*0.005*fritzer*pow(syn_HighHits,1.5);
    float portalDir = sign(portal);
    float portalAmt = abs(portal)*abs(portal);
    // vec2 altSpot = 0.05*pow(syn_BassLevel,2.0)*vec2(sin(syn_BassTime*0.1*2*PI), cos(syn_CurvedTime*0.4));
    _uv2uvc(uv);
    // uv += altSpot;
    uv /= mix(1.0, 1.0+length(_uvc)*portalDir*0.5, portalAmt*portalAmt);
    _uvc2uv(uv);

    vec4 old = BlurB(uv, 0).rgbr;
    float lenMod = mix(length(_uvc)*2.1, clamp(0.3/(0.1+pow(length(_uvc)*1.0,3.0)),0.0,2.0), center_vig);
    old = mix(old, BlurB(uv, 1), vignette*vignette*lenMod);
    fragColor = old;
    fragColor += (1.0-pow(smoke, 0.5))*((BlurB(uv+vec2((-0.45+fragColor.r)*sign(_uvc.x)*(0.2+data.g*0.5),length(fragColor))*drips*0.004, 1) 
        - 
        BlurB(uv, 2))*1.0*(1.0+faster_growth*4.0)); 
    // fragColor = mix(fragColor, fragColor-0.3, data.a*media_mask);
    // fragColor = mix(fragColor, fragColor-media_mask)
    float hasMedia = clamp(syn_MediaType, 0.0, 1.0);
    float medA = clamp(pow(data.a*1.2,2.0),0.0,1.0);
    float medS = clamp(pow((1.0-data.a)*1.5,2.0),0.0,1.0);
    float medFeed = media_feed*hasMedia;
    fragColor.r = mix(fragColor.r*(1.0+medFeed*0.2), clamp(pow(fragColor.r, 1.75),0.0,1.0), medFeed*medS);
    fragColor.g = mix(fragColor.g*(1.0+medFeed*0.2), clamp(pow(fragColor.r, 1.75),0.0,1.0), medFeed*medS);
    fragColor.r = mix(fragColor.r, 0.8, medFeed*medA);
    fragColor.g = mix(fragColor.g, 0.2, medFeed*medA);

    // fragColor.r -= media_feed*medA*0.3;
    // fragColor += media_feed*medA*0.2;
    // if (paint_on > 0.5){
    //     vec2 stepuvc = _uvc;
    //     if (_uv.x<0.5){
    //         stepuvc.x = -stepuvc.x;
    //     }
    //     vec2 pol = _toPolarTrue(stepuvc);
    //     pol.x += syn_BassTime*0.005;
    //     pol.y += syn_Time*0.005;

    //     float stepper = 0.5+0.5*sin(pol.x*30.0+pol.y*10.0*PI);
    //     float stepper2 = 0.5+0.5*sin(-pol.x*30.0-pol.y*20.0*PI);
    //     stepper+=sin(stepper*PI+stepper2*PI+TIME*0.1);
    //     stepper = sin(stepper);
    //     fragColor.ra = mix(fragColor.ra, vec2(0.5, length(fragColor)*2.0), stepper);

    // }

    // vec2 polPos = _toPolarTrue(_uvc);
    vec2 uvs = _uv;
    // uvs = mix(uvs, vec2(1.2+_uvc.x+_uvc.y, 1.2+_uvc.x-_uvc.y)*0.4, sweep_mod);
    // fragColor.rgba = mix(fragColor.rgba, vec4(0.7, 0.1, length(fragColor)*2.0,0.1), _pulse(uvs.y-fragColor.g*0.05, down_sweep*1.3-0.1, 0.1)*step(0.001, down_sweep));
    // fragColor.rgba = mix(fragColor.rgba, fragColor-0.2, _pulse(uvs.y-fragColor.g*0.05, down_sweep*1.3-0.1, 0.1)*step(0.001, down_sweep));
    // fragColor.rgba = mix(fragColor.rgba, fragColor-0.2, _pulse(1.0-uvs.y+fragColor.g*0.05, down_sweep*1.3-0.1, 0.1)*step(0.001, down_sweep));
    // fragColor.rgba = mix(fragColor.rgba, fragColor-0.9, _pulse(uvs.y, down_sweep*1.3-0.1, 0.2)*step(0.001, down_sweep));
    // fragColor.rgba = mix(fragColor.rgba, fragColor-0.9, _pulse(1.0-uvs.y, down_sweep*1.3-0.1, 0.2)*step(0.001, down_sweep));

    fragColor.r *= 1.0-0.4*(1.0-fbmmer)*isolate_layers*0.9;
    fragColor.g *= 1.0-0.6*fbmmer*isolate_layers*0.9;
    // fragColor.g -= fragColor.r;
    // fragColor.r -= fragColor.g;

    if (syn_MediaType > 0.5){
        // fragColor.r -= fragColor.r*data.b;
        // fragColor.b += fragColor.g*data.b;
        // fragColor.g = mix(fragColor.g, data.b, syn_HighHits);

    }
    // fragColor *= mask;
    // if (data.a > 0.5){
        // fragColor = mix(fragColor, vec4(1.0,-0.1,0.1,0.1), data.a*media_mask);
        fragColor = mix(fragColor, (fragColor*3.0-fragColor.gbrr*3.1)*(1.0+media_dazzle), data.a*media_dazzle*media_dazzle*hasMedia);
    // }
    // if (data.g>0.5){
    //     fragColor.b = -fragColor.b;
    // }
    // if (data.r>0.5){
    //     fragColor.r = pow(fragColor.r, 2.0);
    // }

    // fragColor = mix(fragColor, fragColor.gbar, syn_BassLevel*0.1);

    float inLifeHelper = -1.0*clamp(zoom_in_out, -1.0, 0.0);
    inLifeHelper = max(inLifeHelper, portal);

    // fragColor.r += inLifeHelper*(1.0/(length(_uvc)*2.0+0.2))*fbmmer;
    // fragColor.g += inLifeHelper*(1.0/(length(_uvc)*2.0+0.2))*fbmmer;
    fragColor = clamp(fragColor, 0., 1.);
    float s1 = 1.0/(length(_uvc+vec2(0.003, 0.003))*500.0+0.2);
    float s2 = 1.0/(length(_uvc+vec2(0.003,-0.003))*500.0+0.2);
    float s3 = 1.0/(length(_uvc                   )*500.0+0.2);
    float s4 = 1.0/(length(_uvc-vec2(0.003,-0.003))*500.0+0.2);
    float s5 = 1.0/(length(_uvc-vec2(0.003, 0.003))*500.0+0.2);

    s1 = clamp(s1-1, 0.0, 1.0);
    s2 = clamp(s2-1, 0.0, 1.0);
    s3 = clamp(s3-1, 0.0, 1.0);
    s4 = clamp(s4-1, 0.0, 1.0);
    s5 = clamp(s5-1, 0.0, 1.0);
    float sTot = clamp(s1+s2+s3+s4+s5, 0.0, 1.0);
    fragColor = mix(fragColor, fragColor-vec4(0.2,0.4,0.6,0.8), inLifeHelper*sTot);

    // fragColor += inLifeHelper;

    // fragColor = noise; // reset
}



// *************** PASS 2 *****************
vec4 blur_horizontal(sampler2D channel, vec2 uv, float scale)
{
    float h = scale / RENDERSIZE.x;
    vec4 sum = vec4(0.0);

    sum += texture(channel, fract(vec2(uv.x - 4.0*h, uv.y)) ) * 0.05;
    sum += texture(channel, fract(vec2(uv.x - 3.0*h, uv.y)) ) * 0.09;
    sum += texture(channel, fract(vec2(uv.x - 2.0*h, uv.y)) ) * 0.12;
    sum += texture(channel, fract(vec2(uv.x - 1.0*h, uv.y)) ) * 0.15;
    sum += texture(channel, fract(vec2(uv.x + 0.0*h, uv.y)) ) * 0.16;
    sum += texture(channel, fract(vec2(uv.x + 1.0*h, uv.y)) ) * 0.15;
    sum += texture(channel, fract(vec2(uv.x + 2.0*h, uv.y)) ) * 0.12;
    sum += texture(channel, fract(vec2(uv.x + 3.0*h, uv.y)) ) * 0.09;
    sum += texture(channel, fract(vec2(uv.x + 4.0*h, uv.y)) ) * 0.05;

    return sum/0.98; // normalize
}

vec4 blur_horizontal_left_column(vec2 uv, int depth)
{
    float h = pow(2., float(depth)) / RENDERSIZE.x;    
    vec2 uv1, uv2, uv3, uv4, uv5, uv6, uv7, uv8, uv9;

    uv1 = fract(vec2(uv.x - 4.0 * h, uv.y) * 2.);
    uv2 = fract(vec2(uv.x - 3.0 * h, uv.y) * 2.);
    uv3 = fract(vec2(uv.x - 2.0 * h, uv.y) * 2.);
    uv4 = fract(vec2(uv.x - 1.0 * h, uv.y) * 2.);
    uv5 = fract(vec2(uv.x + 0.0 * h, uv.y) * 2.);
    uv6 = fract(vec2(uv.x + 1.0 * h, uv.y) * 2.);
    uv7 = fract(vec2(uv.x + 2.0 * h, uv.y) * 2.);
    uv8 = fract(vec2(uv.x + 3.0 * h, uv.y) * 2.);
    uv9 = fract(vec2(uv.x + 4.0 * h, uv.y) * 2.);

    if(uv.y > 0.5)
    {
        uv1 = upper_left(uv1);
        uv2 = upper_left(uv2);
        uv3 = upper_left(uv3);
        uv4 = upper_left(uv4);
        uv5 = upper_left(uv5);
        uv6 = upper_left(uv6);
        uv7 = upper_left(uv7);
        uv8 = upper_left(uv8);
        uv9 = upper_left(uv9);
    }
    else{
        uv1 = lower_left(uv1);
        uv2 = lower_left(uv2);
        uv3 = lower_left(uv3);
        uv4 = lower_left(uv4);
        uv5 = lower_left(uv5);
        uv6 = lower_left(uv6);
        uv7 = lower_left(uv7);
        uv8 = lower_left(uv8);
        uv9 = lower_left(uv9);
    }

    for(int level = 0; level < 8; level++)
    {
        if(level >= depth)
        {
            break;
        }

        uv1 = lower_right(uv1);
        uv2 = lower_right(uv2);
        uv3 = lower_right(uv3);
        uv4 = lower_right(uv4);
        uv5 = lower_right(uv5);
        uv6 = lower_right(uv6);
        uv7 = lower_right(uv7);
        uv8 = lower_right(uv8);
        uv9 = lower_right(uv9);
    }

    vec4 sum = vec4(0.0);

    sum += texture(buffD, uv1) * 0.05;
    sum += texture(buffD, uv2) * 0.09;
    sum += texture(buffD, uv3) * 0.12;
    sum += texture(buffD, uv4) * 0.15;
    sum += texture(buffD, uv5) * 0.16;
    sum += texture(buffD, uv6) * 0.15;
    sum += texture(buffD, uv7) * 0.12;
    sum += texture(buffD, uv8) * 0.09;
    sum += texture(buffD, uv9) * 0.05;

    return sum/0.98; // normalize
}

void mainImage2( inout vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord.xy / RENDERSIZE.xy;

    if(uv.x < 0.5)
    {
        vec2 uv_half = fract(uv*2.);
        if(uv.y > 0.5)
        {
            fragColor = blur_horizontal(buffB2, uv_half, 1.);
        }
        else
        {
            fragColor = blur_horizontal(buffB2, uv_half, 1.);
        }
    }
    else
    {
        for(int level = 0; level < 8; level++)
        {
            if((uv.x > 0.5 && uv.y > 0.5) || (uv.x <= 0.5))
            {
                break;
            }
            vec2 uv_half = fract(uv*2.);
            fragColor = blur_horizontal_left_column(uv_half, level);
            uv = uv_half;
        }
    }
}


// *************** PASS 4 *****************

vec4 blur_vertical_upper_left(sampler2D channel, vec2 uv)
{
    float v = 1. / RENDERSIZE.y;
    vec4 sum = vec4(0.0);
    sum += texture(channel, upper_left(vec2(uv.x, uv.y - 4.0*v)) ) * 0.05;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y - 3.0*v)) ) * 0.09;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y - 2.0*v)) ) * 0.12;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y - 1.0*v)) ) * 0.15;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y + 0.0*v)) ) * 0.16;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y + 1.0*v)) ) * 0.15;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y + 2.0*v)) ) * 0.12;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y + 3.0*v)) ) * 0.09;
    sum += texture(channel, upper_left(vec2(uv.x, uv.y + 4.0*v)) ) * 0.05;
    return sum/0.98; // normalize
}

vec4 blur_vertical_lower_left(sampler2D channel, vec2 uv)
{
    float v = 1. / RENDERSIZE.y;
    vec4 sum = vec4(0.0);
    sum += texture(channel, lower_left(vec2(uv.x, uv.y - 4.0*v)) ) * 0.05;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y - 3.0*v)) ) * 0.09;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y - 2.0*v)) ) * 0.12;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y - 1.0*v)) ) * 0.15;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y + 0.0*v)) ) * 0.16;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y + 1.0*v)) ) * 0.15;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y + 2.0*v)) ) * 0.12;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y + 3.0*v)) ) * 0.09;
    sum += texture(channel, lower_left(vec2(uv.x, uv.y + 4.0*v)) ) * 0.05;
    return sum/0.98; // normalize
}

vec4 blur_vertical_left_column(vec2 uv, int depth)
{
    float v = pow(2., float(depth)) / RENDERSIZE.y;

    vec2 uv1, uv2, uv3, uv4, uv5, uv6, uv7, uv8, uv9;

    uv1 = fract(vec2(uv.x, uv.y - 4.0*v) * 2.);
    uv2 = fract(vec2(uv.x, uv.y - 3.0*v) * 2.);
    uv3 = fract(vec2(uv.x, uv.y - 2.0*v) * 2.);
    uv4 = fract(vec2(uv.x, uv.y - 1.0*v) * 2.);
    uv5 = fract(vec2(uv.x, uv.y + 0.0*v) * 2.);
    uv6 = fract(vec2(uv.x, uv.y + 1.0*v) * 2.);
    uv7 = fract(vec2(uv.x, uv.y + 2.0*v) * 2.);
    uv8 = fract(vec2(uv.x, uv.y + 3.0*v) * 2.);
    uv9 = fract(vec2(uv.x, uv.y + 4.0*v) * 2.);

    if(uv.y > 0.5)
    {
        uv1 = upper_left(uv1);
        uv2 = upper_left(uv2);
        uv3 = upper_left(uv3);
        uv4 = upper_left(uv4);
        uv5 = upper_left(uv5);
        uv6 = upper_left(uv6);
        uv7 = upper_left(uv7);
        uv8 = upper_left(uv8);
        uv9 = upper_left(uv9);
    }
    else{
        uv1 = lower_left(uv1);
        uv2 = lower_left(uv2);
        uv3 = lower_left(uv3);
        uv4 = lower_left(uv4);
        uv5 = lower_left(uv5);
        uv6 = lower_left(uv6);
        uv7 = lower_left(uv7);
        uv8 = lower_left(uv8);
        uv9 = lower_left(uv9);
    }

    for(int level = 0; level < 8; level++)
    {
        if(level > depth)
        {
            break;
        }

        uv1 = lower_right(uv1);
        uv2 = lower_right(uv2);
        uv3 = lower_right(uv3);
        uv4 = lower_right(uv4);
        uv5 = lower_right(uv5);
        uv6 = lower_right(uv6);
        uv7 = lower_right(uv7);
        uv8 = lower_right(uv8);
        uv9 = lower_right(uv9);
    }

    vec4 sum = vec4(0.0);

    sum += texture(buffC, uv1) * 0.05;
    sum += texture(buffC, uv2) * 0.09;
    sum += texture(buffC, uv3) * 0.12;
    sum += texture(buffC, uv4) * 0.15;
    sum += texture(buffC, uv5) * 0.16;
    sum += texture(buffC, uv6) * 0.15;
    sum += texture(buffC, uv7) * 0.12;
    sum += texture(buffC, uv8) * 0.09;
    sum += texture(buffC, uv9) * 0.05;

    return sum/0.98; // normalize
}

void mainImage3( inout vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord.xy / RENDERSIZE.xy;
    vec2 uv_orig = uv;
    vec2 uv_half = fract(uv*2.);
    if(uv.x < 0.5)
    {
        if(uv.y > 0.5)
        {
            fragColor = blur_vertical_upper_left(buffC, uv_half);
        }
        else
        {
            fragColor = blur_vertical_lower_left(buffC, uv_half);
        }
    }
    else
    {
        for(int level = 0; level < 8; level++)
        {
            if((uv.x > 0.5 && uv.y >= 0.5) || (uv.x < 0.5))
            {
                break;
            }
            vec2 uv_half = fract(uv*2.);
            fragColor = blur_vertical_left_column(uv_half, level);
            fragColor = fragColor.rgba;
            uv = uv_half;
        }  
    }
}

// *************** Main Image Pass *****************

void mainImage4( inout vec4 fragColor, in vec2 fragCoord )
{
    vec2 uv = fragCoord.xy / RENDERSIZE.xy;

    vec2 pixelSize = 1. / vec2(1600.0,900.0);
    vec2 aspect = vec2(1.,RENDERSIZE.y/RENDERSIZE.x);

    // vec2 d = pixelSize*(2.+mode*2.0);
    vec2 d = pixelSize*(2.0);

    vec4 dx = (BlurB(uv + vec2(1,0)*d, 1) - BlurB(uv - vec2(1,0)*d, 1))*0.5;
    vec4 dy = (BlurB(uv + vec2(0,1)*d, 1) - BlurB(uv - vec2(0,1)*d, 1))*0.5;

    d = pixelSize*1.;
    dx += BlurB(uv + vec2(1,0)*d, 0) - BlurB(uv - vec2(1,0)*d, 0);
    dy += BlurB(uv + vec2(0,1)*d, 0) - BlurB(uv - vec2(0,1)*d, 0);
    vec2 lightSize=vec2(0.5);

    // *** Color Regime 0 ***
    vec3 midHighCol = -vec3(-0.2,0.4,0.8)*1.5;
    vec3 midCol = vec3(1.0,0.7,0.5)*1.0;
    vec3 bassCol1 = vec3(0.0,-1.0,1.0)*1.0;    
    vec3 bassCol2 = vec3(0.7,-1,1.4)*0.5;
    vec3 highCol1 = vec3(0.5,0.5,1.0)*0.6;
    vec3 highCol2 = vec3(0.0,0.5,0.7)*0.6;


    float colMixIn = color_palette;
    float mixer = colMixIn;
    mixer = smoothstep(0.25, 0.75, clamp(mixer, 0.0, 1.0));

    // *** Color Regime 1 ***
    midHighCol = mix(midHighCol, _normalizeRGB(46, 9, 39), mixer);
    bassCol1 = mix(bassCol1, vec3(0.7,0.3,0.1), mixer);
    highCol1 = mix(highCol1, _normalizeRGB(4, 117, 111), mixer);
    bassCol2 = mix(bassCol2, _normalizeRGB(225, 70, 7), mixer);
    highCol2 = mix(highCol2, _normalizeRGB(255, 140, 0), mixer);
    midCol = mix(midCol, _normalizeRGB(4, 117, 111), mixer);

    colMixIn = colMixIn - 1.0;
    mixer = smoothstep(0.25, 0.75, clamp(colMixIn, 0.0, 1.0));

    // *** Color Regime 2 ***
    midHighCol = mix(midHighCol, vec3(0.0,0.0,1.0)*0.5*0.0, mixer);
    bassCol1 = mix(bassCol1,vec3(0.4,0.8,0.0)*1.0, mixer);
    highCol1 = mix(highCol1,vec3(0.2,0.4,0.15)*1.0, mixer);
    bassCol2 = mix(bassCol2,vec3(1.0,0.7,0.2)*1.4, mixer);
    highCol2 = mix(highCol2,vec3(1.0,0.7,0.0)*(0.4-0.4*flashing+syn_HighHits*flashing), mixer);
    midCol = mix(midCol,vec3(0.3,0.2,0.15)*0.5, mixer);

    colMixIn = colMixIn - 1.0;
    mixer = smoothstep(0.25, 0.75, clamp(colMixIn, 0.0, 1.0));

    // *** Color Regime 3 ***
    midHighCol = mix(midHighCol, _normalizeRGB(151, 9, 79), mixer);
    bassCol1 = mix(bassCol1, _normalizeRGB(151, 9, 79), mixer);
    highCol1 = mix(highCol1, _normalizeRGB(200, 255, 255)*0.9, mixer);
    bassCol2 = mix(bassCol2, _normalizeRGB(62, 9, 79), mixer);
    highCol2 = mix(highCol2, _normalizeRGB(255, 134, 50), mixer);
    midCol = mix(midCol, _normalizeRGB(22, 1, 85), mixer);

    colMixIn = colMixIn - 1.0;
    mixer = smoothstep(0.25, 0.75, clamp(colMixIn, 0.0, 1.0));

    // *** Color Regime 4 ***
    midHighCol = mix(midHighCol, _normalizeRGB(40, 28, 150), mixer);
    bassCol1 = mix(bassCol1, -_normalizeRGB(155, 155, 155), mixer);
    highCol1 = mix(highCol1, _normalizeRGB(5, 136*0.99, 163*0.99), mixer);
    bassCol2 = mix(bassCol2, _normalizeRGB(5, 163*0.6, 136*0.9), mixer);
    highCol2 = mix(highCol2, _normalizeRGB(20, 140, 140), mixer);
    midCol = mix(midCol, _normalizeRGB(107, 12, 34), mixer);

    colMixIn = colMixIn - 1.0;
    mixer = smoothstep(0.25, 0.75, clamp(colMixIn, 0.0, 1.0));

    // *** Color Regime 5 ***
    midHighCol = mix(midHighCol, vec3(-1.0), mixer);
    bassCol1 = mix(bassCol1, vec3(1.0), mixer);
    highCol1 = mix(highCol1, vec3(-1.0), mixer);
    bassCol2 = mix(bassCol2, vec3(1.0), mixer);
    highCol2 = mix(highCol2, vec3(mix(1.0,syn_HighHits,flashing)), mixer);
    midCol = mix(midCol, vec3(1.0), mixer);

    // // *** Color Regime 5 ***
    // midHighCol = mix(midHighCol, _normalizeRGB(1, 28, 68).brg, mixer);
    // bassCol1 = mix(bassCol1, _normalizeRGB(0, 163, 136).rgb, mixer);
    // highCol1 = mix(highCol1, -_normalizeRGB(60, 190, 190).rgb, mixer);
    // bassCol2 = mix(bassCol2, _normalizeRGB(0, 30, 136).rgb, mixer);
    // highCol2 = mix(highCol2, _normalizeRGB(88, 140, 200), mixer);
    // midCol = mix(midCol, _normalizeRGB(40,10,93), mixer);

    // colMixIn = colMixIn - 1.0;
    // mixer = smoothstep(0.25, 0.75, clamp(colMixIn, 0.0, 1.0));


    //Media Col
    float mColMix = media_color*clamp(syn_MediaType, 0.0, 1.0);
    midHighCol = mix(midHighCol, texture(syn_UserImage, _uv*0.035+vec2(0.3,0.3)+vec2(0.1,0.0)*TIME*0.012).rgb*1.2, mColMix);
    bassCol1 = mix(bassCol1, texture(syn_UserImage, _uv*0.035+vec2(0.4,0.4)-vec2(0.1,0.0)*TIME*0.013).rgb*1.2, mColMix);
    highCol1 = mix(highCol1, texture(syn_UserImage, _uv*0.035+vec2(0.5,0.5)+vec2(0.1,0.0)*TIME*0.014).rgb*1.2, mColMix);
    bassCol2 = mix(bassCol2, texture(syn_UserImage, _uv*0.035+vec2(0.6,0.6)-vec2(0.1,0.0)*TIME*0.015).rgb*1.2, mColMix);
    highCol2 = mix(highCol2, texture(syn_UserImage, _uv*0.035+vec2(0.7,0.7)+vec2(0.1,0.0)*TIME*0.016).rgb*1.2, mColMix);
    midCol = mix(midCol, texture(syn_UserImage, _uv*0.035+vec2(0.8,0.8)-vec2(0.1,0.0)*TIME*0.017).rgb*1.2, mColMix);

    vec2 zoneMids = vec2(sin(syn_MidTime*0.23), cos(syn_MidTime*0.17));
    vec2 zoneMidHighs = vec2(sin(syn_MidHighTime*0.23), cos(syn_MidHighTime*0.17));
    vec2 zoneHighs = vec2(sin(syn_HighTime*0.23), cos(syn_HighTime*0.17));

    midHighCol *= mix(1.0,(0.4+0.7*syn_MidHighPresence*distance(zoneMidHighs, _uvc)*0.5), 1.0-color_presence);
    bassCol1 *= mix(1.0,(0.3+0.7*pow(syn_BassLevel,2.0)), 1.0-color_presence);
    bassCol2 *= mix(1.0,(0.2+0.8*syn_BassPresence*1.0), 1.0-color_presence);
    highCol1 *= mix(1.0,(0.2+0.8*syn_HighPresence), 1.0-color_presence);
    midCol *= mix(1.0,(0.2+0.9*distance(zoneMids, _uvc)*syn_MidPresence), 1.0-color_presence);

    if (flashing > 0.5){
        highCol2 *= (0.1+0.9*syn_HighHits*(0.77+syn_Presence*0.23)*distance(zoneHighs, _uvc));
        // if (((color_palette>1.99)&&(color_palette<2.99))||(color_palette>4.0)){
        //     highCol1 *= (0.1+0.9*syn_HighHits*(0.77+syn_Presence*0.23)*distance(zoneHighs, _uvc));
        // }
    } else {
        highCol2 *= ((0.5+syn_Presence*0.5)*distance(zoneHighs, _uvc));
    }
    
    vec4 media = _loadUserImage();
    float logo = dot(media.rgb, vec3(1.0))/3.0;
    // bassCol2 *= (1.0-logo);
    // bassCol1 *= (1.0-logo);

    // highCol1 *= (1.0-media_mult*clamp(syn_MediaType, 0.0, 1.0)*(1.0-logo));
    // highCol2 *= (1.0-media_mult*clamp(syn_MediaType, 0.0, 1.0)*(1.0-logo));

    vec3 finalColor = vec3(0.0);
    finalColor = mix(finalColor, midCol*1.5, clamp(BlurB(uv + GradientB(uv, pixelSize, vec4(-0.,32.,-128.,0.)*(1.0-logo), 0)*pixelSize, 0).y,0.0,1.0));
    finalColor = mix(finalColor, bassCol1, clamp(abs(GradientB(uv, pixelSize*2.0, vec4(2.0,0.0,0.0,0.0),0).y),0.0,1.0));
    finalColor = mix(finalColor, midHighCol, clamp(BlurB(uv, 4).a,0.0,1.0));
    finalColor = mix(finalColor, bassCol2, clamp(BlurB(uv, 0).x*BlurB(uv + GradientB(uv, pixelSize*2.5, vec4(-256.,32.,-128.,32.)*0.2, 1)*pixelSize, 1).x,0.0,1.0));
    finalColor = mix(finalColor, highCol1, clamp(dot(GradientB(uv, pixelSize*1., vec4(0., 10., 0., 0.), 1), vec2(sin(syn_HighTime*1.0), cos(syn_HighTime*1.0))),0.0,1.0));

    finalColor = mix(finalColor, highCol2*2.0, clamp(BlurB(uv, 1).b*dot(GradientB(uv, pixelSize*2.0, vec4(1.,0.,0.,0.), 0), vec2(sin(syn_HighTime*2.0), cos(syn_HighTime*2.0)))*5.,0.0,1.0));

    // float h1Mix = clamp(dot(GradientB(uv, pixelSize*1., vec4(0., 10., 0., 0.), 1), vec2(sin(syn_HighTime*1.0), cos(syn_HighTime*1.0))),0.0,1.0);
    // finalColor = mix(finalColor, highCol1, clamp(dot(GradientB(uv, pixelSize*1., vec4(1., 10., 0., 0.), 1), vec2(sin(syn_HighTime*1.0), cos(syn_HighTime*1.0))),0.0,1.0)); 

    // float lum = dot(finalColor, vec3(1.0))/3.0;
    // lum = pow(lum, 1.5)*9.0;
    // lum = clamp(lum, 0.0, 1.0);
    // finalColor = finalColor2;
    // finalColor += finalColor2*(1.0-lum);

    finalColor *= mix(1.0,(0.6+(sin(_uvc.x*5.0+TIME*0.1)*_uv.y+cos(_uvc.x*4.7-TIME*0.47)+cos(_uvc.x*11.0+TIME*0.89)*(1.0-_uv.y))/6.0),1.0-color_presence);
    finalColor += pow(finalColor,vec3(2.0))*(0.88);

    // finalColor = _loadUserImage(finalColor.rg*0.05).rgb;

    vec2 vigPos = _uv*(1.0 - uv.yx);   //vec2(1.0)- uv.yx; -> 1.-u.yx; Thanks FabriceNeyret !
    float vig = vigPos.x*vigPos.y * 15.0; // multiply with sth for intensity
    vig = pow(vig, 0.25); // change pow for modifying the extend of the  vignette

    finalColor = clamp(finalColor, 0.0, 1.0);

    // finalColor = _rgb2hsv(finalColor);
    // finalColor.g += BlurB(uv, 3).r+TIME*0.1;
    // finalColor = _hsv2rgb(finalColor);
    float lumF = dot(finalColor.rgb, vec3(1.0))/3.0;
    fragColor = vec4(finalColor,1.0);
    // media = mix(vec4(1.0), media_mult);
    float hasMedia = clamp(syn_MediaType, 0.0, 1.0);

    fragColor = vec4(threeColMix(fragColor.rgb, fragColor.rgb*0.5+fragColor.rgb*media.rgb, fragColor.rgb*media.rgb*1.25, media_mult*hasMedia),1.0) + media*media_add*hasMedia;
    // fragColor += media*media_mask;
    // fragColor *= vig;

       // fragColor = vec4(BlurB(uv, 0)); // simple bypass
       // fragColor -= vec4(0.5,0.5,0.5,0.0)*fragColor.a;
       // fragColor = vec4(BlurB(uv, 0).a); // simple bypass
       // fragColor = texture(buffD, _uv); // raw Gaussian pyramid
}

vec4 renderMain(void)
{
  if (PASSINDEX == 0.0){
    //buffB
    vec4 fragColor = vec4(0.0);
    mainImage1(fragColor, gl_FragCoord.xy);
    return fragColor;
  }else if (PASSINDEX == 1.0){
    return texture(buffB, _uv);
  }
  else if (PASSINDEX == 2.0){
    //buffC
    vec4 fragColor = vec4(0.0);
    mainImage2(fragColor, gl_FragCoord.xy);
    return fragColor;
  }
  else if (PASSINDEX == 3.0){
    //buffD
    vec4 fragColor = vec4(0.0);
    mainImage3(fragColor, gl_FragCoord.xy);
    return fragColor;
  }
  else if (PASSINDEX == 4.0){
    //Image
    vec4 fragColor = vec4(0.0);
    mainImage4(fragColor, gl_FragCoord.xy);
    // return texture(buffD, _uv);
    return fragColor;
  }
}
