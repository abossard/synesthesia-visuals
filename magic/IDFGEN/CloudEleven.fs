/*{
	"CREDIT": "by mojovideotech",
	"DESCRIPTION": "",
	"CATEGORIES": [
		"generator",
		"clouds"
	],
  "INPUTS" : [
  	{
		"NAME" : 		"center",
		"TYPE" : 		"point2D",
		"DEFAULT" :		[ 0.0, 0.0 ],
		"MAX" : 		[ 1.0, 1.0 ],
     	"MIN" : 		[ -1.0, -1.0 ]
	},
    {
     	"NAME" :		"seed",
      	"TYPE" :		"float",
     	"DEFAULT" :		514229,
     	"MIN" :			75025,
     	"MAX" :			3524578
    },
	{
		"NAME" : 		"zoom",
		"TYPE" : 		"float",
		"DEFAULT" : 	0.5,
		"MIN" : 		0.125,
		"MAX" : 		1.5
	},
	{
		"NAME" : 		"rate",
		"TYPE" : 		"float",
		"DEFAULT" : 	0.25,
		"MIN" : 		-1.0,
		"MAX" : 		1.0
	},
	{
      	"NAME" : 		"rot",
      	"TYPE" : 		"float",
      	"DEFAULT" :		0.2,
      	"MIN" : 		-0.5,
      	"MAX" : 		0.5
	},	
    {
      	"NAME" : 		"hue",
      	"TYPE" : 		"float",
      	"DEFAULT" :		0.0,
      	"MIN" : 		0.0,
      	"MAX" : 		1.0
  	}	
  ],
    "ISFVSN" : 2.0
}
*/

////////////////////////////////////////////////////////////
// CloudEleven   by mojovideotech
//
// based on 
// Cloud Ten  by nimitz
// shadertoy.com\/XtS3DD
//
// Creative Commons Attribution-NonCommercial-ShareAlike 3.0
////////////////////////////////////////////////////////////



#define 	pi   	3.14159265 	// pi

float T = TIME * rate, moy = 0.0;
vec3 lgt = vec3(1.0);

mat2 mm2(in float a) {float c = cos(a), s = sin(a);return mat2(c,s,-s,c);}

float noise3D(vec3 p) {
	const vec3 s = vec3(17, 377, 1113);
	vec3 ip = floor(p); 
    vec4 h = vec4(0.0, s.yz, s.y + s.z) + dot(ip, s);
	p -= ip; 
	p = p*p*p*(p*(p * 6.0 - 15.0) + 10.0);
    h = mix(fract(sin(h)*seed), fract(sin(h + s.x)*seed), p.x);
    h.xy = mix(h.xz, h.yw, p.y);
    return mix(h.x, h.y, p.z); 
}

float fbm(in vec3 x) {
    float rz = 0.0, a = 0.35;
    for (int i = 0; i<2; i++) {
        rz += noise3D(x)*a;
        a*=0.35;
        x*= 4.0;
    }
    return rz;
}

float path(in float x) { return sin(x*0.01-pi)*28.0+6.5; }

float map(vec3 p) {
    return p.y*0.07 + (fbm(p*0.3)-0.1) + sin(p.x*0.24 + sin(p.z*.01)*7.)*0.22+0.15 + sin(p.z*0.08)*0.05;
}

float march(in vec3 ro, in vec3 rd) {
    float precis = 0.3, h= 1.0, d = 0.0;
    for( int i=0; i<17; i++ ) {
        if( abs(h)<precis || d>50.0 ) break;
        d += h;
        vec3 pos = ro+rd*d;
        pos.y += 0.5;
	    float res = map(pos)*7.0;
        h = res;
    }
	return d;
}

float mapV( vec3 p ){ return clamp(-map(p), 0.0, 1.0); }

vec4 marchV(in vec3 ro, in vec3 rd, in float t, in vec3 bgc) {
	vec4 rz = vec4( 0.0 );
	for( int i=0; i<100; i++ ) {
		if(rz.a > 0.99 || t > 200.0) break;
		vec3 pos = ro + t*rd;
        float den = mapV(pos);
        vec4 col = vec4(mix( vec3(0.8,0.75,0.85), vec3(0.0), den ),den);
        col.xyz *= mix(bgc*bgc*2.5,  mix(vec3(0.1,0.2,0.55),vec3(0.8,0.85,0.9),moy*0.4), clamp( -(den*40.0+0.0)*pos.y*0.03-moy*0.5, 0.0, 1.0));
        col.rgb += clamp((1.0-den*6.0) + pos.y*0.13 +0.55, 0.0, 1.0)*0.35*mix(bgc,vec3(1.0),0.7); //Fringes
        col += clamp(den*pos.y*0.15, -0.02, 0.0); //Depth occlusion
        col *= smoothstep(0.2+moy*0.05,0.0,mapV(pos+1.0*lgt))*.85+0.15; //Shadows
		col.a *= 0.95;
		col.rgb *= col.a;
		rz = rz + col*(1.0 - rz.a);
        t += max(0.3,(2.0-den*30.0)*t*0.011);
	}
	return clamp(rz, 0.0, 1.0);
}

mat3 rot_x(float a){float sa = sin(a); float ca = cos(a); return mat3(1.,.0,.0,    .0,ca,sa,   .0,-sa,ca);}
mat3 rot_y(float a){float sa = sin(a); float ca = cos(a); return mat3(ca,.0,sa,    .0,1.,.0,   -sa,.0,ca);}
mat3 rot_z(float a){float sa = sin(a); float ca = cos(a); return mat3(ca,sa,.0,    -sa,ca,.0,  .0,.0,1.);}

void main() 
{
	vec2 q = gl_FragCoord.xy / RENDERSIZE.xy;
    vec2 p = q - 0.5;
	float asp =RENDERSIZE.x/RENDERSIZE.y;
    p.x *= asp;
	vec2 mo = center.xy;
	moy = mo.y;
    float st = sin(T*0.3-1.3)*rot;
    vec3 ro = vec3(0.0,-2.0+sin(T*0.3-1.0)*2.0,T*30.0);
    ro.x = path(ro.z);
    vec3 ta = ro + vec3(0,0,1);
    vec3 fw = normalize(ta - ro);
    vec3 uu = normalize(cross( vec3(0.0,1.0,0.0), fw));
    vec3 vv = normalize(cross(fw,uu));
    vec3 rd = normalize(p.x*uu + p.y*vv + -zoom*fw);
    float rox = sin(T*0.2)*0.6+2.9;
    rox += smoothstep(0.6,1.2,sin(T*0.25))*3.5;
   	float roy = sin(T*0.5)*rot;
    mat3 rotation = rot_x(-roy)*rot_y(-rox+st*1.5)*rot_z(st);
	mat3 inv_rotation = rot_z(-st)*rot_y(rox-st*1.5)*rot_x(roy);
    rd *= rotation;
    rd.y -= dot(p,p)*0.06;
    rd = normalize(rd);
    vec3 col = vec3(0.0);
    lgt = normalize(vec3(-mo.x,mo.y+0.1,1.0));  
    float rdl = clamp(dot(rd, lgt),0.0,1.0);
    vec3 hor = mix(vec3(0.9,0.6,0.7)*0.35, vec3(0.5,0.05,0.05), rdl);
    hor = mix(hor, vec3(0.5,0.8,1.0),mo.y);
    col += mix( vec3(0.2,0.2,0.6), hor, exp2(-(1.0+ 3.0*(1.0-rdl))*max(abs(rd.y),0.0)))*0.6;
    col += 0.8*vec3(1.0,0.9,0.9)*exp2(rdl*650.0-650.0);
    col += 0.3*vec3(1.0,1.0,0.1)*exp2(rdl*100.0-100.0);
    col += 0.5*vec3(1.0,0.7,0.0)*exp2(rdl*50.0-50.0);
    col += 0.4*vec3(1.0,0.0,0.05)*exp2(rdl*10.0-10.0);  
    vec3 bgc = col;
    float rz = march(ro,rd);
    if (rz < 70.) {   
        vec4 res = marchV(ro, rd, rz-5.0, bgc);
    	col = col*(1.0-res.w) + res.xyz;
    }
    float g = smoothstep(0.01,0.9,hue);
   	col = mix(mix(col,col.brg*vec3(1.0,0.75,1.0),clamp(g*2.0,0.0,1.0)), col.bgr, clamp((g-0.5)*2.,0.0,1.0));
	col = clamp(col, 0.0, 1.0);
    col = col*0.5 + 0.5*col*col*(3.0-2.0*col); //saturation
    col = pow(col, vec3(0.416667))*1.055 - 0.055; //sRGB
	gl_FragColor = vec4( col, 1.0 );
}
