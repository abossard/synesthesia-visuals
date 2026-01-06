vec3 permute(vec3 x){return mod((34.0*x+1.0)*x,289.0);}
vec3 dist(vec3 x,vec3 y,bool manhattanDistance){return manhattanDistance?abs(x)+abs(y):(x*x+y*y);}
vec2 worley(vec2 P,float jitter,bool manhattanDistance){float K=0.142857142857;float Ko=0.428571428571;vec2 Pi=mod(floor(P),289.0);vec2 Pf=fract(P);vec3 oi=vec3(-1.0,0.0,1.0);vec3 of=vec3(-0.5,0.5,1.5);vec3 px=permute(Pi.x+oi);vec3 p=permute(px.x+Pi.y+oi);vec3 ox=fract(p*K)-Ko;vec3 oy=mod(floor(p*K),7.0)*K-Ko;vec3 dx=Pf.x+0.5+jitter*ox;vec3 dy=Pf.y-of+jitter*oy;vec3 d1=dist(dx,dy,manhattanDistance);p=permute(px.y+Pi.y+oi);ox=fract(p*K)-Ko;oy=mod(floor(p*K),7.0)*K-Ko;dx=Pf.x-0.5+jitter*ox;dy=Pf.y-of+jitter*oy;vec3 d2=dist(dx,dy,manhattanDistance);p=permute(px.z+Pi.y+oi);ox=fract(p*K)-Ko;oy=mod(floor(p*K),7.0)*K-Ko;dx=Pf.x-1.5+jitter*ox;dy=Pf.y-of+jitter*oy;vec3 d3=dist(dx,dy,manhattanDistance);vec3 d1a=min(d1,d2);d2=max(d1,d2);d2=min(d2,d3);d1=min(d1a,d2);d2=max(d1a,d2);d1.xy=(d1.x<d1.y)?d1.xy:d1.yx;d1.xz=(d1.x<d1.z)?d1.xz:d1.zx;d1.yz=min(d1.yz,d2.yz);d1.y=min(d1.y,d1.z);d1.y=min(d1.y,d2.x);return sqrt(d1.xy);}
vec3 dist(vec3 x,vec3 y,vec3 z,bool manhattanDistance){return manhattanDistance?abs(x)+abs(y)+abs(z):(x*x+y*y+z*z);}
vec2 worley(vec3 P,float jitter,bool manhattanDistance){float K=0.142857142857;float Ko=0.428571428571;float K2=0.020408163265306;float Kz=0.166666666667;float Kzo=0.416666666667;vec3 Pi=mod(floor(P),289.0);vec3 Pf=fract(P)-0.5;vec3 Pfx=Pf.x+vec3(1.0,0.0,-1.0);vec3 Pfy=Pf.y+vec3(1.0,0.0,-1.0);vec3 Pfz=Pf.z+vec3(1.0,0.0,-1.0);vec3 p=permute(Pi.x+vec3(-1.0,0.0,1.0));vec3 p1=permute(p+Pi.y-1.0);vec3 p2=permute(p+Pi.y);vec3 p3=permute(p+Pi.y+1.0);vec3 p11=permute(p1+Pi.z-1.0);vec3 p12=permute(p1+Pi.z);vec3 p13=permute(p1+Pi.z+1.0);vec3 p21=permute(p2+Pi.z-1.0);vec3 p22=permute(p2+Pi.z);vec3 p23=permute(p2+Pi.z+1.0);vec3 p31=permute(p3+Pi.z-1.0);vec3 p32=permute(p3+Pi.z);vec3 p33=permute(p3+Pi.z+1.0);vec3 ox11=fract(p11*K)-Ko;vec3 oy11=mod(floor(p11*K),7.0)*K-Ko;vec3 oz11=floor(p11*K2)*Kz-Kzo;vec3 ox12=fract(p12*K)-Ko;vec3 oy12=mod(floor(p12*K),7.0)*K-Ko;vec3 oz12=floor(p12*K2)*Kz-Kzo;vec3 ox13=fract(p13*K)-Ko;vec3 oy13=mod(floor(p13*K),7.0)*K-Ko;vec3 oz13=floor(p13*K2)*Kz-Kzo;vec3 ox21=fract(p21*K)-Ko;vec3 oy21=mod(floor(p21*K),7.0)*K-Ko;vec3 oz21=floor(p21*K2)*Kz-Kzo;vec3 ox22=fract(p22*K)-Ko;vec3 oy22=mod(floor(p22*K),7.0)*K-Ko;vec3 oz22=floor(p22*K2)*Kz-Kzo;vec3 ox23=fract(p23*K)-Ko;vec3 oy23=mod(floor(p23*K),7.0)*K-Ko;vec3 oz23=floor(p23*K2)*Kz-Kzo;vec3 ox31=fract(p31*K)-Ko;vec3 oy31=mod(floor(p31*K),7.0)*K-Ko;vec3 oz31=floor(p31*K2)*Kz-Kzo;vec3 ox32=fract(p32*K)-Ko;vec3 oy32=mod(floor(p32*K),7.0)*K-Ko;vec3 oz32=floor(p32*K2)*Kz-Kzo;vec3 ox33=fract(p33*K)-Ko;vec3 oy33=mod(floor(p33*K),7.0)*K-Ko;vec3 oz33=floor(p33*K2)*Kz-Kzo;vec3 dx11=Pfx+jitter*ox11;vec3 dy11=Pfy.x+jitter*oy11;vec3 dz11=Pfz.x+jitter*oz11;vec3 dx12=Pfx+jitter*ox12;vec3 dy12=Pfy.x+jitter*oy12;vec3 dz12=Pfz.y+jitter*oz12;vec3 dx13=Pfx+jitter*ox13;vec3 dy13=Pfy.x+jitter*oy13;vec3 dz13=Pfz.z+jitter*oz13;vec3 dx21=Pfx+jitter*ox21;vec3 dy21=Pfy.y+jitter*oy21;vec3 dz21=Pfz.x+jitter*oz21;vec3 dx22=Pfx+jitter*ox22;vec3 dy22=Pfy.y+jitter*oy22;vec3 dz22=Pfz.y+jitter*oz22;vec3 dx23=Pfx+jitter*ox23;vec3 dy23=Pfy.y+jitter*oy23;vec3 dz23=Pfz.z+jitter*oz23;vec3 dx31=Pfx+jitter*ox31;vec3 dy31=Pfy.z+jitter*oy31;vec3 dz31=Pfz.x+jitter*oz31;vec3 dx32=Pfx+jitter*ox32;vec3 dy32=Pfy.z+jitter*oy32;vec3 dz32=Pfz.y+jitter*oz32;vec3 dx33=Pfx+jitter*ox33;vec3 dy33=Pfy.z+jitter*oy33;vec3 dz33=Pfz.z+jitter*oz33;vec3 d11=dist(dx11,dy11,dz11,manhattanDistance);vec3 d12=dist(dx12,dy12,dz12,manhattanDistance);vec3 d13=dist(dx13,dy13,dz13,manhattanDistance);vec3 d21=dist(dx21,dy21,dz21,manhattanDistance);vec3 d22=dist(dx22,dy22,dz22,manhattanDistance);vec3 d23=dist(dx23,dy23,dz23,manhattanDistance);vec3 d31=dist(dx31,dy31,dz31,manhattanDistance);vec3 d32=dist(dx32,dy32,dz32,manhattanDistance);vec3 d33=dist(dx33,dy33,dz33,manhattanDistance);vec3 d1a=min(d11,d12);d12=max(d11,d12);d11=min(d1a,d13);d13=max(d1a,d13);d12=min(d12,d13);vec3 d2a=min(d21,d22);d22=max(d21,d22);d21=min(d2a,d23);d23=max(d2a,d23);d22=min(d22,d23);vec3 d3a=min(d31,d32);d32=max(d31,d32);d31=min(d3a,d33);d33=max(d3a,d33);d32=min(d32,d33);vec3 da=min(d11,d21);d21=max(d11,d21);d11=min(da,d31);d31=max(da,d31);d11.xy=(d11.x<d11.y)?d11.xy:d11.yx;d11.xz=(d11.x<d11.z)?d11.xz:d11.zx;d12=min(d12,d21);d12=min(d12,d22);d12=min(d12,d31);d12=min(d12,d32);d11.yz=min(d11.yz,d12.xy);d11.y=min(d11.y,d12.z);d11.y=min(d11.y,d11.z);return sqrt(d11.xy);}
vec3 invertMix(in vec3 a, in vec3 b) {
    return abs(a-b);
}
float shapes() {
    float shape = 0.;
    float scale = 1.5;
    vec2 suvc = _uvc * scale;
    float circle = length(suvc);
    float diamond = abs(suvc.x) + abs(suvc.y);
    float square = max(abs(suvc.x),abs(suvc.y));
    float lines_h = sin(suvc.y * 14. - TIME) + .5;
    float line_h = sin(suvc.y*4.+1.5);
    float lines_v = sin(abs(suvc.x) * 10. - TIME) + .5;
    // float line_v = sin(suvc.x*2.+1.575);
    float line_v = worley(suvc*4., syn_Presence, true).x;
    const int shape_count = 8;
    float media = _luminance(_loadMedia().rgb)*2. - .5;
    float s[8] = float[](circle,diamond,square,lines_h,line_h,lines_v,line_v,media);
    int shape_a = int(shaper.x+0.5);
    int shape_b = int(shaper.y+0.5);
    shape = mix(s[shape_a], s[shape_b], shaper.z);
    float shape_fade = 0.5*shape_blur;
    float shape_size = shape_sizer*(1.+syn_BassHits*syn_BassLevel*shape_grow_on_beat);
    vec2 scatter_uv = _uvc*4.*(1.+(1.-scatter_size)*10.);
    float scatter_noise = worley(vec3(scatter_uv,TIME*0.25),2.-scatter_sort,false).x;
    shape *= mix(1.,scatter_noise,scatter);
    shape = smoothstep(shape_size-shape_fade,shape_size+shape_fade,shape);
    return shape;
}
void addStars(inout vec3 col) {
    if (reactive_stars < 0.5) return;
    vec2 star_uv = _uvc * 4.;
    star_uv *= 1. + syn_MidHits * 0.2;
    // syn_Mid stars
    float stars_grad = worley(vec3(star_uv,TIME*0.25),1.,true).x;
    float star_size = 0.5 * syn_MidPresence;
    float stars = smoothstep(star_size - 0.01,star_size + 0.01,stars_grad);
    star_size *= 0.8;
    float stars_inner = smoothstep(star_size - 0.01,star_size + 0.01,stars_grad);
    col = invertMix(col, vec3(stars));
    col = invertMix(col, vec3(stars_inner));
    // syn_MidHigh stars
    float stars2_grad = worley(vec3(star_uv*1.2+90.,TIME*0.25),1.,true).x;
    star_size = 0.4 * syn_MidHighPresence;
    float stars2 = smoothstep(star_size - 0.01,star_size + 0.01,stars2_grad);
    star_size *= 0.8;
    float stars2_inner = smoothstep(star_size - 0.01,star_size + 0.01,stars2_grad);
    col = invertMix(col, vec3(stars2));
    col = invertMix(col, vec3(stars2_inner));
}
void addBursts(inout vec3 col) {
    if (reactive_bursts < 0.5) return;
    // syn_High bursts
    vec2 polar = _toPolar(_uvc);
    float high_bursts = _sqPulse(polar.x - syn_BPMTri2, 0.3,0.1);
    high_bursts *= smoothstep(0.5,0.6,sin(polar.y * 30 + syn_HighTime * 10.));
    // trigger when high present & bpm confident
    #ifndef SHOW_BURSTS
    high_bursts *= step(0.5,syn_HighPresence) * step(0.3,syn_BPMConfidence);
    #endif
    col = invertMix(col, vec3(high_bursts));
    // syn_High bursts
    float high_bursts2 = _sqPulse(polar.x - syn_BPMSin4, 0.1,0.1);
    high_bursts2 *= smoothstep(0.1,0.2,sin(polar.y * 30 + syn_BPMTwitcher));
    // trigger when high presenter & bpm confidenter
    #ifndef SHOW_BURSTS2
    high_bursts2 *= step(0.5,syn_HighPresence) * step(0.3,syn_BPMConfidence);
    high_bursts2 *= step(0.7,syn_HighPresence) * step(0.5,syn_BPMConfidence);
    #endif
    col = invertMix(col, vec3(high_bursts2));
}
vec4 renderMain(void) {
    vec3 col = vec3(0.);
    col = vec3(shapes());
    addStars(col);
    addBursts(col);
    // invert on beat
    float flip = smoothstep(0.4, 0.6, syn_ToggleOnBeat);
    if (invert_on_beat>0.5) col = mix(col, 1. - col, vec3(flip));
    // return
    vec3 palcol = _palette(col.r, vec3(0.), 0.6 + 0.4*vec3(syn_BassPresence, syn_MidPresence, syn_HighPresence), palette_picker.xyx*vec3(2.,2.,_uv.y), vec3(syn_BassTime*.01, syn_MidTime*.01, syn_HighTime*.01));
    col = mix(col, palcol, apply_palette);
	return vec4(col, 1.0);
}
