//Sphere Chaser - Psybernautics (Alex Tiemann) - 2024
#define FAR 100.
#include "lygia/filter/boxBlur/2D_fast9.glsl"

float smin( float a, float b, float k )
{
    float h = max(k-abs(a-b),0.0);
    return min(a, b) - h*h*0.25/k;
}


vec3 re(vec3 p, float d) 
{return mod(p - d * .5, d) - d * .5;}


void amod(inout vec2 p, float d) 
{
    float a = re(vec3(atan(p.y, p.x)), d).x;
    p = vec2(cos(a), sin(a)) * length(p);
}


float sdBox( vec3 p, vec3 b )
{
  vec3 q = abs(p) - b;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0);
}


float sdSphereOrCage(vec3 p) {
    float sphere_scale = mix(0.25, 1.5, _sphere_space);
    float size = sphere_scale+0.125*syn_BassLevel*sphere_scale;
    float morph = syn_BassPresence;
    float morph2 = -morph*0.5;

    return sdBox(p, vec3(size+morph2, size+morph2, size+morph)) - PI*0.01325;


}

vec2 oracle(vec3 p) {

    float sphere_space = mix(10.0, 30.0, _sphere_space);
    vec3 q = p;
    q.z -= sphere_space+20.0;
    vec2 result = vec2(4.0);
 
    q.xy += vec2(2.0,2.0);

    vec3 q1 = q;

    q1.xy -= vec2(2.0, 4.0);
    q1.xy -= vec2(syn_MidHighPresence)*(vec2(2.0,-4.0));
    q1.z -= cos(bass_time)*4.0;
    q1.xy = _rotate(q1.xy, mid_time - const_time*0.1);
    q1.xz = _rotate(q1.xz, -midHigh_time);
    amod(q1.xy, 2.0*PI / 4.0);
    q1.x -= sphere_space - 2.0*syn_MidPresence;

    q.xy -= vec2(syn_BassPresence)*(vec2(2.0,4.0));
    q.z -= cos(mid_time)*4.0;
    q.yz = _rotate(q.yz, midHigh_time);
    q.xy = _rotate(q.xy, -bass_time + const_time*0.1);
    amod(q.xy, 2.0*PI / 4.0);
    q.x -= sphere_space + 2.0*syn_MidHighPresence;

    result.x = smin(sdSphereOrCage(q), sdSphereOrCage(q1), gooey);
    
    return result;

}

vec2 map(vec3 p) {

    vec3 q = p;

    float sphere_space = mix(2.0, 30.0, _sphere_space);
    
    q.x += sphere_space*sinBTime;
    q.y += sphere_space*cosBTime;    

    vec2 scene = vec2(2.0);

    vec2 oracle1 =  oracle(p);

    vec2 oracle2 =  oracle(q);

    if (oracle1.x < oracle2.x) {
        scene.y = 3.0;
    }

    scene.x = smin(oracle1.x, oracle2.x, 0.1);


    return scene;
    
}


vec2 trace(vec3 ro, vec3 rd){

    vec2 t = vec2(0.0);
    vec2 d = vec2(0.0);

    for (int i = 0; i < 30; i++){

        d = map(ro + rd*t.x);

        if(abs(d.x)<.0005 || t.x>FAR) break;        

        t.x += d.x*.75;

    }

    t.y = d.y;

    return t;

}


// Tetrahedral normal, to save a couple of "map" calls. Courtesy of IQ.

vec3 getNormal( in vec3 p ){

    vec2 e = vec2(.0025, -.0025); 

    return normalize(

        e.xyy * map(p + e.xyy).x + 

        e.yyx * map(p + e.yyx).x + 

        e.yxy * map(p + e.yxy).x + 

        e.xxx * map(p + e.xxx).x);

}

vec4 sobelIntensity(in vec4 color){

  return color;

}

vec4 sobelHelper(float stepx, float stepy, vec2 center, sampler2D tex){

    vec4 tleft = sobelIntensity(texture(tex,clamp(center + vec2(-stepx,stepy), 0.0, 1.0)));

    vec4 left = sobelIntensity(texture(tex,clamp(center + vec2(-stepx,0), 0.0, 1.0)));

    vec4 bleft = sobelIntensity(texture(tex,clamp(center + vec2(-stepx,-stepy), 0.0, 1.0)));

    vec4 top = sobelIntensity(texture(tex,clamp(center + vec2(0,stepy), 0.0, 1.0)));

    vec4 bottom = sobelIntensity(texture(tex,clamp(center + vec2(0,-stepy), 0.0, 1.0)));

    vec4 tright = sobelIntensity(texture(tex,clamp(center + vec2(stepx,stepy), 0.0, 1.0)));

    vec4 right = sobelIntensity(texture(tex,clamp(center + vec2(stepx,0), 0.0, 1.0)));

    vec4 bright = sobelIntensity(texture(tex,clamp(center + vec2(stepx,-stepy), 0.0, 1.0)));



    vec4 x = tleft + 2.0*left + bleft - tright - 2.0*right - bright;

    vec4 y = -tleft - 2.0*top - tright + bleft + 2.0 * bottom + bright;

    vec4 color = sqrt((x*x) + (y*y));

    return color;

}

vec4 edgeDetectSobel(sampler2D tex){

    float stepSize =1.0;// mix(0.15, 1.0, syn_BassPresence);

    vec2 uv = _uv;

    return sobelHelper(stepSize/RENDERSIZE.x, stepSize/RENDERSIZE.y, uv, tex);

}

vec4 diffLoop(vec4 sourceColor) {
    vec4 savecolor = sourceColor;
    sourceColor = abs(sourceColor*4.0 - vec4(1.0));
    for(float i = 0; i < 3.0; i++) {
        sourceColor = abs(sourceColor - vec4(1.0));
    }
    return _mix3(savecolor, (savecolor*sourceColor+sourceColor)*0.5, sourceColor, mix(psychedelic_vibrancy <= 0.51 ? clamp(psychedelic_vibrancy*2.0, 0.0, 1.0) : psychedelic_vibrancy , 0.0, mix(0.0, length(texture(firstPass, _uv).xyz)/3.0 ==  0.0 ? 0.0 : 1.0, media_uv)));
}


vec3 getObjectColor(vec3 p, float material){

    vec3 col = color_1;
    float colorSphere = length(p*0.015)-0.125*bass_time;
    col = mix(col, _hsv2rgb(vec3(colorSphere, 1.0, 1.0)), rainbow);
    if (material == 3.0 && one_color < 0.5) {
        col = vec3(1.0) - col;
    }
    
    
    return col;
}

vec3 doColor(in vec3 sp, in vec3 rd, in vec3 sn, in vec3 lp, vec2 t){

    vec3 ld = lp-sp;

    float lDist = max(length(ld), .001);

    ld /= lDist;

    float atten = 1. / (1. + lDist*.2 + lDist*lDist*.1);
    float diff = max(dot(sn, ld), 0.15);
    float spec = pow(max( dot( reflect(-ld, sn), rd ), 0.0), 20.0);
    vec3 objCol = getObjectColor(sp*1.5, t.y);
    vec3 texCol = syn_MediaType > 0.5 ? _loadMedia().xyz : objCol;
    texCol = pow(texCol, vec3(2.0));
    
    vec3 lightCol =  objCol;
    vec3 sceneCol = (objCol*(diff*(30.0)) + lightCol*spec*50.0) * atten;
    return mix(sceneCol, texCol, media_uv);
}


vec4 renderMainImage() {

	vec4 fragColor = vec4(0.0);

	vec2 fragCoord = _xy;

    int AA = 1;

    vec4 totalC = vec4(0.0);

    for( int m=0; m<AA; m++ )

    for( int nm=0; nm<AA; nm++ )

        {

            vec2 uv = (fragCoord.xy - RENDERSIZE.xy*.5) / RENDERSIZE.y;
            vec3 ro = vec3(0.0, 0.0, -5.0);
            vec3 lp = ro+vec3(0.0, 3.0, 0.0);
            vec3 lk = ro + vec3(0.0,0.0,15.0);

            float fFOV=3.14159/(mix(FOV, mix(0.02, 6.0, (syn_BassPresence)), auto_fov)*2.0);
            vec3 forward=normalize(lk-ro);
            vec3 right=normalize(vec3(forward.z,0.,-forward.x));
            vec3 up=cross(forward,right);

            vec3 rd=normalize(forward+fFOV*uv.x*right+fFOV*uv.y*up);
            // rd = normalize(vec3(rd.xy, sqrt(max(rd.z*rd.z - dot(rd.xy, rd.xy)*.085, 0.))));
            rd.xy = _rotate(rd.xy, TIME*0.1);

            vec2 t = trace(ro, rd);
            vec3 sp = ro + rd*t.x;
            ro += rd*t.x;
            vec3 saveRO = ro;
            vec3 sn = getNormal(ro);
            vec2 tSave = t;

            vec3 sceneColor = doColor(ro, rd, sn, lp, tSave);
            lp.y -= 6.0;
            sceneColor += doColor(ro, rd, sn, lp, tSave);

            float fogF = smoothstep(0., .5, t.x/(FAR*2.0));
            sceneColor = mix(sceneColor, vec3(0.0), fogF); 
            totalC += vec4(sqrt(clamp(sceneColor, 0., 1.)), 1);
    }

    return totalC;

 } 

float getVal(vec2 uv)
{
    return length(texture(rVertMirrPass,uv).xyz);
}
    
vec2 getGrad(vec2 uv,float delta)
{
    vec2 d=vec2(delta,0);
    return vec2(
        getVal(uv+d.xy)-getVal(uv-d.xy),
        getVal(uv+d.yx)-getVal(uv-d.yx)
    )/delta;
}

vec2 rotateCenter(vec2 uvIn){
    float tS = mix(0.000, 0.0025+syn_Presence*0.005, pow(spin_mix,2.0));
    float amount = tS*mix(2.0, -2.0, pow(length(_uvc), 3.0));// mix(0.0, mix(tS, -tS, tan(sin(mix(uvIn.x, uvIn.y, syn_RandomOnBeat)*cos(mix(uvIn.y, uvIn.x, syn_RandomOnBeat)*mix(-5.0,5.0, syn_BassPresence))*mix(5.0,-5.0, syn_BassPresence)*length(uvIn)))), mix(2.0, 4.0, syn_BassPresence*syn_BassLevel));
  uvIn.y += (RENDERSIZE.x-RENDERSIZE.y)/RENDERSIZE.x;
  uvIn*=vec2(1.0, RENDERSIZE.y/RENDERSIZE.x);
  _uv2uvc(uvIn);
  uvIn = _rotate(uvIn, amount);
  _uvc2uv(uvIn);
  uvIn/=vec2(1.0, RENDERSIZE.y/RENDERSIZE.x);
  uvIn.y -= (RENDERSIZE.x-RENDERSIZE.y)/RENDERSIZE.x;
  return uvIn;
}

vec4 renderMain(){
    if(PASSINDEX == 0){

		return renderMainImage();

	}
    else if (PASSINDEX == 1) {
        vec4 img = diffLoop(texture(firstPass, _uv))*vec4(vec3(1.0), 0.5);

        float zd = mix(-0.015, 0.015, zoom_direction)*mix(1.0, 1.0+syn_BassLevel*0.5, bass_boost);
        vec2 uwu = ( ( _uv - 0.5 ) / ( 1.0 + (mix(zd, _mix4(-0.1, -1.0, 0.25, 1.0, syn_BassPresence)*(zd), auto_zoom)) ) + 0.5 );
        

        vec2 uwu2 = uwu;
         vec2 uwu3 = uwu;
        
        float beatp = mix(0.1, 0.5, on_beat_only);
        float gpx = syn_BassLevel*syn_BassPresence*_power.x*beatp;
        float gpy = syn_BassLevel*syn_BassPresence*_power.y*beatp;

        float glitchSize = pow(2.0, pow(2.0,  mix(2.75,4.5,syn_RandomOnBeat)))*0.5;
        
        float shift = fract(uwu.y*glitchSize)*gpx;

        float h = mix(syn_BassHits, syn_OnBeat, on_beat_only);
        uwu2 += mod(fract(uwu.y*glitchSize), 2.0) > 0.5 ? vec2(h*shift, 0.0) : -vec2(h*shift, 0.0);        
        shift = fract(uwu.x*glitchSize)*gpy;
        uwu3 += mod(fract(uwu.x*glitchSize), 2.0) > 0.5 ? vec2(0.0, h*shift) : -vec2(0.0, h*shift);

        uwu = mix(uwu2, uwu3, floor(syn_RandomOnBeat+0.5));
        float step_size = mix(0.1, 1.0, mix(flow_speed, pow(syn_BassPresence,2.0), auto_flow))*0.005;
        vec4 fb = (texture(fbLoop, (uwu+vec2(0.0, step_size)))
                        + texture(fbLoop, (uwu+vec2(step_size, 0.0)))
                        + texture(fbLoop, (uwu+vec2(-step_size, 0.0)))
                        + texture(fbLoop, (uwu+vec2(0.0, -step_size)))
                        + texture(fbLoop, (uwu+vec2(step_size, step_size)))
                        + texture(fbLoop, (uwu+vec2(step_size, -step_size)))
                        + texture(fbLoop, (uwu+vec2(-step_size, step_size)))
                        + texture(fbLoop, (uwu+vec2(-step_size, -step_size)))
                        );//
                        vec3 fbHSV = _rgb2hsv(fb.xyz/mix(4.0, 4.0, syn_Presence));
                        fb /= mix(8.0, mix(8.0, 4.0, syn_BassLevel), 1.0 - fbHSV.z);

        // step_size *= 0.5;
        float flow = fb.a*step_size;
        uwu.x += fb.r*step_size*(1.0+fb_pan.x)+flow;
        uwu.y += fb.g*step_size*(1.0+fb_pan.y)+flow;
        uwu -= fb.b*step_size*(1.0+fb_pan)+flow;

        vec4 fragColor = vec4(0.0);
        float thresh = 0.0;    
        if(img.x <= thresh || img.y <= thresh || img.z <= thresh) {
            // fb = texture(fbLoop, uwu);
            vec2 uwuR = uwu;
            // step_size *= 4.0;
            // uwuR.x -= fb.r*step_size;
            // uwuR.y -= fb.b*step_size;
            // uwuR += fb.g*step_size;
            fb = texture(rVertMirrPass, rotateCenter(uwuR));
            fb.xyz = _rgb2hsv(fb.xyz);
            // fb.y += 0.001;
            // fb.z -= 0.0012;
            fb.xyz = _hsv2rgb(fb.xyz);
            img = mix(img, fb, traceMix);
        }

        return img;
    }
    if(PASSINDEX == 2.0){

        vec4 img = texture(postFXPass, _uv);// abs(texture(postFXPass, _uv) - edgeDetectSobel(postFXPass));
        vec4 imgV1 = texture(postFXPass, vec2(_uv.x >= 0.5 ? 1.0 - _uv.x : _uv.x, _uv.y) );
        vec4 imgV2 = texture(postFXPass, vec2(_uv.x <= 0.5 ? 1.0 - _uv.x : _uv.x, _uv.y) );
        return mix(_mix3(img, imgV1, imgV2, multi_mirror), mix(mix(imgV1, imgV2, syn_ToggleOnBeat), img, floor(syn_RandomOnBeat+0.5)), mix(0.0, clamp(pow(syn_Presence, 2.0)*1.1, 0.0, 1.0), auto_mirror));
    
	}
    if(PASSINDEX == 3.0){

        float ps = mix(3.0, 7.0, pow(syn_RandomOnBeat, 2.0));
        vec2 puv = fract(_pixelate((_uv)*ps,0.99)/ps + _rand(floor(syn_BassTime*10.0+0.5)*0.1));
        vec4 img = texture(secondPass, mix(_uv, mix(_uv, puv, floor(0.5+pow(syn_OnBeat, 5.0))*0.2), grid_glitch));
        return img;
	}
     if(PASSINDEX == 4.0){

        // return gaussianBlur2D(postFXPass, _uv, vec2((1.0/length(_uvc)+1.0/_uvc)*0.1), 1);
        return abs(edgeDetectSobel(rVertMirrPass));// - gaussianBlur2D(postFXPass, _uv,vec2(cos(TIME), sin(TIME))*0.0005, 2));
    }
    if(PASSINDEX == 5.0){

        // return gaussianBlur2D(postFXPass, _uv, vec2((1.0/length(_uvc)+1.0/_uvc)*0.1), 1);
        vec4 fb = mix(texture(rVertMirrPass,_uv), abs(boxBlur2D_fast9(fbEdge, _uv, vec2(length(_uvc)*0.01))), 1.0);// - gaussianBlur2D(postFXPass, _uv,vec2(cos(TIME), sin(TIME))*0.0005, 2));
        fb.xyz = _rgb2hsv(fb.xyz);
        // fb.y += 0.001;
        // fb.z -= 0.0012;
        fb.xyz = _hsv2rgb(fb.xyz);
        return fb;
    }
    if(PASSINDEX == 6.0){
        float detail = 1.0-psychedelic_vibrancy;// mix(_detail, 0.5*syn_Presence*syn_BassHits+syn_OnBeat*0.5, auto_detail);
        vec2 uv = _uv;
        vec3 n = vec3(getGrad(uv,1.0/RENDERSIZE.y),mix(100.0, 20.0, detail));
        n *= n;
        n=normalize(n);
        vec4 regColor=vec4(n,1);
        vec3 light = normalize(vec3(1.0,1.0,1.5));
        float diff=clamp(dot(n,light),0.0,1.0);
        float spec=clamp(dot(reflect(light,n),vec3(0,0,mix(-1.0, -20.0, 0.0))),0.0,1.0);
        spec=pow(spec,mix(3.0, 3.0, detail))*mix(0.5, 2.0, detail);
        vec4 lights = vec4(diff)+spec;
        // lights = length(texture(firstPass, _uv).xyz)/3.0 ==  0.0 ? lights : mix(lights,vec4(1.0), media_uv*metallic_media);
        regColor = texture(rVertMirrPass, _uv)*mix(lights, vec4(1.0), flat_fb);
        regColor = diffLoop(regColor);
        return clamp(regColor, 0.0, 1.0);
	}

}