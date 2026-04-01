/*{
  "CREDIT": "by mojovideotech",
  "CATEGORIES": [
    "Shapes"
  ],
  "DESCRIPTION": "Automatically converted from https://www.shadertoy.com/view/lsfXWH by iq.  Four bands of Spherical Harmonics functions (or atomic orbitals if you want). For reference and fun.",
  "INPUTS": [
    {
      "MAX": [
        10,
        10
      ],
      "MIN": [
        -10,
        -10
      ],
      "DEFAULT": [
        3.5,
        1
      ],
      "NAME": "matrix",
      "TYPE": "point2D"
    },
    {
      "NAME": "rate",
      "TYPE": "float",
      "DEFAULT": 1.125,
      "MIN": 0.01,
      "MAX": 2.5
    },
    {
      "NAME": "rotation",
      "TYPE": "float",
      "DEFAULT": -0.5,
      "MIN": -2,
      "MAX": 2
    },
    {
      "NAME": "colorCycle",
      "TYPE": "float",
      "DEFAULT": 1.5,
      "MIN": 0.1,
      "MAX": 3
    },
    {
      "NAME": "warbble",
      "TYPE": "bool",
      "DEFAULT": "FALSE"
    }
  ]
}*/

// SphericalHarmonics by mojovideotech
// hack & mod of :
// https://www.shadertoy.com/view//lsfXWH  by IQ

// Created by inigo quilez - iq/2013
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.
// Four bands of Spherical Harmonics functions (or atomic orbitals if you want). For
// reference and fun.


#define AA 1

#define k02 0.4886025119 // sqrt(  3/PI)/2
#define k03 1.0925484306 // sqrt( 15/PI)/2
#define k04 0.3153915652 // sqrt(  5/PI)/4
#define k10 1.4453057110 // sqrt(105/PI)/4

float SH_0_0( in vec3 s ) { vec3 n = s.zxy; return  k10*n.z*(n.x*n.x-n.y*n.y); }
float SH_1_0( in vec3 s ) { vec3 n = s.zxy; return -k02*n.y; }
float SH_1_1( in vec3 s ) { vec3 n = s.zxy; return  k02*n.z; }
float SH_1_2( in vec3 s ) { vec3 n = s.zxy; return -k02*n.x; }
float SH_2_0( in vec3 s ) { vec3 n = s.zxy; return  k03*n.x*n.y; }
float SH_2_2( in vec3 s ) { vec3 n = s.zxy; return  k04*(3.0*n.z*n.z-1.0); }
float SH_3_6( in vec3 s ) { vec3 n = s.zxy; return  k03*n.x*(n.z*n.y-1.0*n.y); } 

vec3 map( in vec3 p )
{
	float trv = clamp(sin(TIME),0.1,0.9);
	float trh = clamp(cos(TIME),0.0,0.9);
    vec3 p00 = p - vec3( 0.0,trh,0.0);
	vec3 p01 = p - vec3(0.0,trv,0.0);
	vec3 p02 = p - vec3( 0.0,-trv,0.0);	
	vec3 p03 = p - vec3(0.0,-trh,0.0);
	vec3 p04 = p - vec3(0.0,abs(trh),0.0);
	vec3 p06 = p - vec3( 0.0,abs(trv),0.0);
	vec3 p15 = p - vec3( 0.0,trv+trh,0.0);
	float r, d; vec3 n, s, res;
	
	#define SHAPE (vec3(d-abs(r), sign(r),d))
	d=length(p00); n=p00/d; r = SH_0_0( n ); s = SHAPE; res = s;
	d=length(p01); n=p01/d; r = SH_1_0( n ); s = SHAPE; if( s.x<res.x ) res=s;
	d=length(p02); n=p02/d; r = SH_1_1( n ); s = SHAPE; if( s.x<res.x ) res=s;
	d=length(p03); n=p03/d; r = SH_1_2( n ); s = SHAPE; if( s.x<res.x ) res=s;
	d=length(p04); n=p04/d; r = SH_2_0( n ); s = SHAPE; if( s.x<res.x ) res=s;
	d=length(p06); n=p06/d; r = SH_2_2( n ); s = SHAPE; if( s.x<res.x ) res=s;
	d=length(p15); n=p15/d; r = SH_3_6( n ); s = SHAPE; if( s.x<res.x ) res=s; 
	return vec3( res.x, 0.25+0.25*res.y, res.z );
}

vec3 intersect( in vec3 ro, in vec3 rd )
{
	vec3 res = vec3(1e8,-1.0, 1.0);
	float maxd = 4.0;
    float h = 1.0;
    float t = 0.0;
    vec2  m = vec2(1.0);
    for( int i=0; i<150; i++ )
    {
        if( h<0.001||t>maxd ) break;
	    vec3 res = map( ro+rd*t );
        h = res.x;
		m = res.yz;
        t += h*0.3;
    }
	if( t<maxd && t<res.x ) res=vec3(t,m);
	return res;
}

vec3 calcNormal( in vec3 pos )
{
    vec3 eps = vec3(0.001,0.0,0.0);
	return normalize( vec3(
           map(pos+eps.xyy).x - map(pos-eps.xyy).x,
           map(pos+eps.yxy).x - map(pos-eps.yxy).x,
           map(pos+eps.yyx).x - map(pos-eps.yyx).x ) );
}

void main()
{
    vec3 tot = vec3(0.0);
    for( int m=0; m<AA; m++ )
    for( int n=0; n<AA; n++ )
    {        
        vec2 p = (-RENDERSIZE.xy + 2.0*(gl_FragCoord.xy+vec2(float(m),float(n))/float(AA))) / RENDERSIZE.y;
        float T = TIME * rate;
        float an = rotation*T - 8.0*RENDERSIZE.x;
        vec3 ro = vec3(3.0*sin(an),0.0,3.0*cos(an)); 
        vec3  ta = vec3(0.0,0.0,0.0);
		vec3 mnx = vec3 (0.0,1.0,0.0);
		if (warbble) mnx = vec3(1.0,1.0,1.0);
        vec3 ww = normalize( ta - ro );
        vec3 uu = normalize( cross(ww,mnx ) );
        vec3 vv = normalize( cross(uu,ww));
        vec3 rd = normalize( p.x*uu + p.y*vv + 2.0*ww );
        vec3 col = vec3(0.2) * clamp(1.0-length(p)*0.125,0.0,1.0);
        vec3 tmat = intersect(ro,rd);
        if( tmat.y>-0.25 )
        {
            vec3 pos = ro + tmat.x*rd;
            vec3 nor = calcNormal(pos);		
            vec3 ref = reflect( rd, nor );
            vec3 mate = mix(vec3(0.8,0.0,0.0),vec3(mix( vec3(0.0,0.8,0.0), vec3(0.1,0.2,0.8), clamp(sin(T * tmat.y)*colorCycle,0.3,0.9))), clamp(cos(T * colorCycle + tmat.y),0.3,0.9));
            float occ = clamp( 3.0*tmat.z, 0.0, 1.0 );
            float sss = pow( clamp( 1.0 + dot(nor,rd), 0.0, 1.0 ), 1.0 );
            vec3 lin  = 2.5*occ*vec3(matrix.x,1.0,matrix.y)*(0.5+0.3*nor.x);
                 lin += 1.0*sss*vec3(0.5,0.5,0.5)*occ;		
            col = mate.xyz * lin;
        }
        col = pow( clamp(col,0.1,0.9), vec3(0.845) );
        tot += col;
    }
    gl_FragColor = vec4( tot, 1.0 );
}