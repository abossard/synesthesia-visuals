//Puddle Party - Alx Tman - Psybernautics 2025
#include "hg_sdf.glsl"
#include "lygia/generative/pnoise.glsl"

#define FAR 80
#define SURF_DIST 0.01
#define MAX_STEPS 64


vec3 re(vec3 p, float d) 
{return mod(p - d * .5, d) - d * .5;}

vec4 sobelIntensity(in vec4 color){
  return color*0.5;
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

vec4 edgeDetectSobel(sampler2D tex, float stepS){
    float stepSize = stepS;
    vec2 uv = _uv;
    if (uv.x < 0.01 || uv.y < 0.01 || uv.y > 0.99 || uv.x > 0.99) {
        stepSize = 0.0;
    } 
    return sobelHelper(stepSize/RENDERSIZE.x, stepSize/RENDERSIZE.y, uv, tex);
}

float sBox2D(vec2 p, vec2 b, float rf){
    vec2 d = abs(p) - b + rf;
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0)) - rf;
}


float opExtrusionZ(float sdf2D, float pz, float h, float sf){
    vec2 w = vec2(sdf2D, abs(pz) - h) + sf;
    return min(max(w.x, w.y), 0.0) + length(max(w, 0.0)) - sf;
}

float waveField(vec2 posXY) {
    float bc         = dynamic_time;
    float wave_scale = mix(0.5, 1.0, 0.0);
    float slope_fix  = clamp(1.0 / wave_scale, 0.0, 0.9);

    float base_wave = mix(
        sin(-bc + length(posXY) * wave_scale) * slope_fix,
        sin(fBox2Cheap(posXY * wave_scale + 0.125, vec2(1.5)) - bc) * slope_fix,
        mix(square_wave, floor(rand_beat_num_b + 0.5), beat_square)
    );

    float nullMask = smoothstep(
        0.15, mix(0.9, 0.2, mix(patch_size, syn_MidPresence, auto_size)),
        abs(pnoise(vec3((posXY * 0.0625 - 2.0), bc * 0.125), vec3(100.0)))
    );

    base_wave = mix(base_wave, mix(base_wave, 1.0, nullMask), mix(patches, syn_BassPresence, auto_patches));
    return clamp(base_wave, -5.0, 5.0);
}

vec2 rings(vec3 p, float condition) {

    // p.y += mix(0.0, 5.0, mix(geo_switch, floor(syn_ToggleOnBeat + 0.5), beat_shape));

    // 1) Decide your cell size (reuse your original logic so it "breathes" the same)
    float cellSize  = 1.0;

    // We'll tile on the XY plane and extrude along Z (to match your original 'p.z -= wave;' vibe)
    vec2 qWorld = p.xy;

    // 2) Cell ID (integer) and local coordinates centered in the cell
    vec2 cellId  = floor(qWorld / cellSize) + 0.5;
    vec2 qLocal  = qWorld - cellId * cellSize;  // now in [-cellSize/2, +cellSize/2]

    // 3) Sample the wave ONCE per cell (use the cell center in world coords)
    float w      = -waveField(cellId * cellSize);
    // float ws     = -waveField_stripes(cellId * cellSize);
    // w = mix(w, ws, mix(geo_switch, floor(syn_ToggleOnBeat + 0.5), beat_shape));
    // float w01    = w * smoothstep(-0.15, 0.05, w);//max(w, 0.0);//clamp(0.5 + 0.5*w, 0.0, 1.0);      // map [-1,1] -> [0,1]
    float w01    = clamp(mix(0.5+w*0.5, w, mix(flat_trough, syn_Presence, auto_flat)), 0.0, 1.0);
    // float w01    = w * smoothstep(-0.15, 0.05, w);
    float wAbs   = abs(w);                            // optional debug/lighting

    // vec4 aspec = texture(syn_Spectrum,clamp(length(qWorld), 0., 1.0));

    // aspec = texelFetch(syn_Spectrum, int(x*1024), 0);
    vec4 aspec = texelFetch(syn_Spectrum, int(w01*512), 0);

    // 4) Convert wave to a height (per cell)
    float minH   = 0.05;                 // base height (tweak)
    float maxH   = mix(5.0, mix(0.05, 5.0, pow(aspec.b, 1.0)), use_audio_spectrum);//*clamp(syn_Level*1.05, 0.0, 1.0));               // max height (tweak or tie to audio)
    // maxH   = mix(mix(0.5, 1.0, max_height)*maxH, 0.125+aspec.b*maxH, use_audio_spectrum*clamp(syn_Level*1.05, 0.0, 1.0));
    maxH = mix(0.125, 1.0, max_height)*maxH;
    float H      = mix(minH, maxH, w01); // total height
    float halfH  = 0.5 * H;

    // p.z -= mix(w*0.5, w, max_height)*(1.0 - use_audio_spectrum);
    

    // 5) Build a 2D box in the cell and extrude along Z
    float margin = cellSize * mix(0.25, 0.1, w01*(0.5+length(_uvc*0.5)));//mix(0.05, 0.05, w01) * cellSize;                  // gutter width
    vec2  halfXY = vec2(0.5*cellSize) - vec2(margin);
    float round  = clamp(_mix3(0.125, mix(mix(0.3, 0.25, syn_MidHits), 0.05, w01), 0.35, mix(all_dots, 1.0-w01, wave_dots)), 0.0, 0.4);                             // rounding fillet

    // 2D box SDF in XY (local cell space):
    // qLocal = _rotate(qLocal, w*0.5);
    float d2     = sBox2D(qLocal, halfXY-vec2(0.0*syn_HighLevel, 0.0)*halfXY, round);

    // Extrude along Z from 0..H (shift p.z by -halfH so the base sits at z=0)
    float d      = opExtrusionZ(d2, p.z - (halfH), halfH, round);

    // Return SDF and an aux value (wAbs here) like your original rings() did
    return vec2(d, w);
}

vec2 map(vec3 p) {    

    vec3 r = p;
    r.yz = _rotate(r.yz, PI);
    r.yz =  _rotate(r.yz, 0.425*PI*mix(tilt_angle.y, mix(syn_Presence*0.6, rand_beat_num_b, beat_tilt), auto_tilt));

    if (layer_travel > 0.125 ) {
        r.z -= layer_time;
        
        r.z = re(r, 50.0).z;
    }
    
    vec2 scene = vec2(0.0);
    vec2 ring = rings(r, 0.0);
    scene = ring;

    ring.x = min(ring.x, -(length(p) - 40.0));
    return scene;
    
}

vec2 trace(vec3 ro, vec3 rd){

    vec2 t = vec2(0.0);
    vec2 d = vec2(0.0);

    for (int i = 0; i < MAX_STEPS; i++){

        d = map(ro + rd*t.x);

        if(abs(d.x)<SURF_DIST || t.x>FAR) break;        

        t.x += d.x*.75;

    }

    t.y = d.y;

    return t;

}


vec3 getNormal( in vec3 p ){

    vec2 e = vec2(.0025, -.0025); 

    return normalize(

        e.xyy * map(p + e.xyy).x + 

        e.yyx * map(p + e.yyx).x + 

        e.yxy * map(p + e.yxy).x + 

        e.xxx * map(p + e.xxx).x);

}

float softshadow( in vec3 ro, in vec3 rd, in float mint, in float tmax )
{
	float res = 1.0;
    float t = mint;
    for( int i=0; i<16; i++ )
    {
		float h = map( ro + rd*t ).x;
        res = min( res, 8.0*h/t );
        t += clamp( h, 0.02, 0.10 );
        if( h<0.001 || t>tmax ) break;
    }
    return clamp( res, 0.0, 1.0 );
}


vec4 diffLoop(vec4 ta, vec4 tb) {
    ta = abs(ta*4.0 - tb);
    for(float i = 0; i < 3.0; i++) {
        ta = abs(ta - tb);
    }

    return ta;
}

vec3 diffLoop(vec3 ta, vec3 tb) {
    ta = abs(ta*3.0 - tb);
    for(float i = 0; i < 3.0; i++) {
        ta = abs(ta - tb);
    }

    return ta;
}


vec3 getObjectColor(vec3 p, float material, vec3 n, float wave){

    vec3 colH = _rgb2hsv(color);
    colH.x += 0.5;
    colH = _hsv2rgb(colH);

    vec3 col = _mix3((vec3(1.0) - color), color, color, pow(wave, 4.0));
    

    // col = mix(col, colH, 1.0);
    return mix(col, color, monochrome);
}


float calcAO( in vec3 pos, in vec3 nor )
{
	float occ = 0.0;
    float sca = 1.0;
    for( int i=0; i<5; i++ )
    {
        float hr = 0.01 + 0.12*float(i)/4.0;
        vec3 aopos =  nor * hr + pos;
        float dd = map( aopos ).x;
        occ += -(dd-hr)*sca;
        sca *= 0.95;
    }
    return clamp( 1.0 - 3.0*occ, 0.0, 1.0 );
}

vec3 doColor(in vec3 sp, in vec3 rd, in vec3 sn, in vec3 lp, vec2 t, float li){

    vec3 ld = lp-sp;
    float lDist = max(length(ld), .001);
    ld /= lDist;
    t.y = abs(t.y);
    float atten = 1. / (1. + lDist*.2 + lDist*lDist*.1);
    float diff = max(dot(sn, ld), 0.00);
    float spec = pow(max( dot( reflect(-ld, sn), rd ), 0.0), 100.0);
    vec3 objCol = getObjectColor(sp, li, sn, t.y);
    float media_mix = _isMediaActive() ? mix(show_media, clamp(syn_BassPresence *1.5, 0.0, 1.0), media_bass) : 0.0;
    float sh = softshadow( sp + sn*0.1, rd, 0.08,  lDist*4.0 );
    diff *= mix(1.0, sh, mix(0.9, 0.5, media_mix*(t.y)));
    vec2 uwu = _uv;
    float offset = mix(0.0, 0.125, mix(media_displace, syn_Presence*0.95+0.05, auto_displace));
    vec3 texCol = _textureMedia(uwu - vec2(-offset, offset)*t.y - length(sn)*0.01*t.y).xyz;
    // vec3 texCol = texelFetch(mediaPass, ivec2((uwu - vec2(-offset, offset)*t.y) * RENDERSIZE), 0).xyz;
    texCol = pow(texCol, vec3(2.0));
    vec3 lightCol = objCol;
    objCol = _isMediaActive() ? mix(objCol, texCol,  media_mix) : objCol;
    vec3 sceneCol = (objCol*(diff*15.0) + objCol*spec*10.0)  * atten ;
    return sceneCol*2.0;
}

vec4 renderMainImage() {

	vec4 fragColor = vec4(0.0);
	vec2 fragCoord = _xy;
    int AA = 1;
    vec4 totalC = vec4(0.0);
    float deerugs = rave_mode*(1.0 - (_isMediaActive() ? mix(show_media, clamp(syn_BassPresence *1.5, 0.0, 1.0), media_bass) : 0.0));
    vec2 uv = (fragCoord.xy - RENDERSIZE.xy*.5) / RENDERSIZE.y;
    vec3 ro = vec3(0.0,0.0,-30.0);
    vec3 lk = vec3(0.0,0.0,0.0);
    vec3 lp = ro + vec3(5.0, -30.0,0.0);
    vec3 rd=normalize(vec3(uv,mix(0.5, 2.5, mix(zoom, mix(1.0, rand_beat_num_b, beat_zoom)*(0.1+mix(0.9, 0.5, syn_BassPresence)*syn_MidPresence), auto_zoom))));
    rd = normalize(vec3(rd.xy, sqrt(max(rd.z*rd.z - dot(rd.xy, rd.xy)*.15, 0.))));
    rd.xy = _rotate(rd.xy , PI*mix(tilt_angle.x, 0.5*mix(sin(cam_time), mix(1., -1.0, rand_beat_num_a), beat_tilt), auto_tilt));
    vec2 v = (_xy.xy / RENDERSIZE.xy) + RENDERSIZE.y;
    v.y += 0.5;
    float pi = PI;
    float twpi = 2.0*PI;
    float th =  v.y * pi, ph = v.x * twpi;
    vec3 ssp = vec3( sin(ph) * cos(th), sin(th), cos(ph) * cos(th) );
    ssp.xy = _rotate(ssp.xy, morph_time*0.05);
    ssp.xz = _rotate(ssp.xz, morph_time*0.005);
    ssp.yz = _rotate(ssp.yz, morph_time*-0.05);
    rd = mix(rd, normalize(ssp), mix(morph, pow(syn_BassPresence, 4.0), auto_morph));
    vec2 t = trace(ro, rd);
    vec3 sceneColor = vec3(0.0);
    if(t.x < FAR) {      
        vec2 tSave = t;
        vec3 sp = ro + rd*t.x;
        ro += rd*t.x;
        vec3 sn = getNormal(ro);
        vec3 reflCol = doColor(ro, rd, sn, lp, t, 0.0);
        lp.z -= 35.0;;
        sceneColor = reflCol + doColor(ro, rd, sn, lp, t, 1.0);
        float fogF = smoothstep(0., .99, t.x/(FAR*mix(5.5, 2.0, deerugs)));
        sceneColor = mix(sceneColor, (abs(vec3(1.0) - glow_color)*deerugs*(0.5+rd.y*0.5)), fogF); 
        
    }

    totalC += vec4(sqrt(clamp(sceneColor, 0., 1.))*mix(2.0, 4.0, (1.0 - deerugs)), t.y);
    return clamp(totalC, 0.0, 1.0);
 } 

 vec2 mirrorCoords(vec2 uvIn){

    if (mod(uvIn.x, 2.0) > 1.0){
        uvIn.x = 1.0-uvIn.x;
    }
    if (mod(uvIn.y, 2.0) > 1.0){
        uvIn.y = 1.0-uvIn.y;
    }
    return mod(uvIn, 1.0);
}



vec4 renderMain(){

    if(PASSINDEX == 0){
		return _loadUserImage();
	}

	if(PASSINDEX == 1){
		return renderMainImage();
	}
    else if (PASSINDEX == 2) {
        vec2 uv = _uv;
        float mw = invert_mask;
        float wave = abs(mix(1.0, 0.0, mw) - clamp(texture(postFXPass, _uv).w, 0.0, 1.0));
        wave = sqrt(wave);
        wave = mix(sqrt(wave), wave, mw);
        vec4 new_edge = edgeDetectSobel(postFXPass, (wave+1.0)*mask_edge);
        vec4 col = texture(postFXPass, _uv);
        vec4 vibrant = diffLoop(col, vec4(1.0));
        // vibrant = mix(vibrant, vibrant*new_edge, mask_edge);
        return mix(col, _mix3(new_edge*vibrant+new_edge.b, vibrant+new_edge.b, vibrant, wave), rave_mode*(1.0-(_isMediaActive() ? mix(show_media, clamp(syn_BassPresence *1.5, 0.0, 1.0), media_bass) : 0.0)));         
    }
    if(PASSINDEX == 3.0){
        vec4 img = texture(secondPass, _uv);
        vec2 uv = _uv;
        vec2 uvL = _uv;
        uvL.x = 1.0 - uvL.x;
		vec4 mirImg = texture(secondPass, uv);
        vec4 mirImgL = texture(secondPass, uvL);
        vec4 mir_mix_1 = length(mirImg.xyz) == 0.0 ? mirImgL : mirImg;
        return _mix3( img, mir_mix_1,  mirImgL, mix(mir, pow(syn_Presence, 2.0), auto_mir));//mix(mirImg, mirImgL, syn_ToggleOnBeat), mir);
	}
    if(PASSINDEX == 4.0) {
        vec4 img = texture(mirrorPass, _uv);
        img = mix(img, length(img.xyz) < 0.1 ? texture(mediaPass, _uv) : img, media_under*(_isMediaActive() ? 1.0 : 0.0));
        return clamp(img, 0.0, 1.0);
    
    }
    if(PASSINDEX == 5.0) {
        vec2 offset = vec2(mix(0.0, mix(0.01325, 0.0625, syn_BassLevel)*_noise((_uv)*10.0), mix(0.0, syn_BassPresence*syn_MidHits , party_boi)), 0.0);
        return vec4(mix(texture(syn_FinalPass, _uv+offset).xyz, texture(syn_FinalPass, _uv-offset).xyz, syn_ToggleOnBeat), 1.0);

    }
    if (PASSINDEX == 6.0) {
        vec4 ofp = (texture(offsetPass, _uv));
        vec4 r = mix(texture(kalPass, _uv), ofp, mix(0.0,  pow(syn_BassLevel, 5.0)*syn_MidHits, party_boi));
        return r;
    }
    if (PASSINDEX == 7.0) {
        return mix(texture(tunnelPass, _uv), texture(syn_FinalPass, _uv)*1.005,composition_feedback);
    }
}