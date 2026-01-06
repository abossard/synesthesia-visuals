
#define COPY_COLOR(N, colorsK)  for(int i = 0; i < N; i++) { colors[i] = colorsK[i]; }

vec3 rgb2hsl(vec3 color) {
    float r = color.r;
    float g = color.g;
    float b = color.b;
    float max = max(max(r, g), b);
    float min = min(min(r, g), b);
    float h, s, l;
    l = (max + min) / 2.0;

    if (max == min) {
        h = s = 0.0; // achromatic
    } else {
        float d = max - min;
        s = l > 0.5 ? d / (2.0 - max - min) : d / (max + min);
        if (max == r) {
            h = (g - b) / d + (g < b ? 6.0 : 0.0);
        } else if (max == g) {
            h = (b - r) / d + 2.0;
        } else if (max == b) {
            h = (r - g) / d + 4.0;
        }
        h /= 6.0;
    }
    return vec3(h, s, l);
}


const vec3 colors2[] = vec3[](
    vec3(27, 231, 255) / 255.0, // Electric blue
    vec3(110, 235, 131) / 255.0, // Light green
    vec3(228, 255, 26) / 255.0, // Lemon Lime
    vec3(255, 184, 0) / 255.0, // Selective yellow
    vec3(255, 87, 20) / 255.0 // Giants orange
);

const vec3 colors1[] = vec3[](
    vec3(84, 13, 110) / 255.0, // Indigo
    vec3(238, 66, 102) / 255.0, // Red (Crayola)
    vec3(255, 210, 63) / 255.0, // Sunglow
    vec3(59, 206, 172) / 255.0, // Turquoise
    vec3(14, 173, 105) / 255.0 // Jade
);
  

const vec3 colors3[] = vec3[](
    vec3(155, 93, 229) / 255.0, // Amethyst
    vec3(241, 91, 181) / 255.0, // Brilliant rose
    vec3(254, 228, 64) / 255.0, // Maize
    vec3(0, 187, 249) / 255.0, // Deep Sky Blue
    vec3(0, 245, 212) / 255.0 // Aquamarine
);


const vec3 colors4[] = vec3[](
    vec3(0.169, 0.761, 0.718),
    vec3(0.357, 0.518, 0.008),
    vec3(0.604, 0.851, 0.259),
    vec3(0.820, 0.235, 0.196),
    vec3(0.522, 0.075, 0.020)
);

const vec3 colors5[] = vec3[](
    vec3(237, 174, 73) / 255.0, // Hunyadi yellow
    vec3(209, 73, 91) / 255.0, // Amaranth
    vec3(0, 121, 140) / 255.0, // Caribbean Current
    vec3(48, 99, 142) / 255.0, // Lapis Lazuli
    vec3(0, 61, 91) / 255.0 // Indigo dye
);


const vec3 colors6[] = vec3[](
    vec3(0, 204, 255) / 255.0, // Vivid sky blue
    vec3(0, 255, 204) / 255.0, // Aquamarine
    vec3(255, 255, 0) / 255.0, // Yellow
    vec3(255, 0, 204) / 255.0, // Hot magenta
    vec3(204, 0, 255) / 255.0 // Electric purple
);

const vec3 colors77[] = vec3[](
    vec3(0.600,0.271,0.000), // Vivid sky blue
    vec3(0.949,0.600,0.314), // Aquamarine
    vec3(0.941,0.984,1.000), // Yellow
    vec3(0.071,0.537,0.769), // Hot magenta
    vec3(0.051,0.212,0.686) // Electric purple
);

const vec3 colors78[] = vec3[](
    vec3(249, 65, 68) / 255.0, // Imperial red
    vec3(243, 114, 44) / 255.0, // Orange (Crayola)
    vec3(248, 150, 30) / 255.0, // Carrot orange
    vec3(249, 132, 74) / 255.0, // Coral
    vec3(249, 199, 79) / 255.0, // Saffron
    vec3(144, 190, 109) / 255.0, // Pistachio
    vec3(67, 170, 139) / 255.0, // Zomp
    vec3(77, 144, 142) / 255.0, // Dark cyan
    vec3(87, 117, 144) / 255.0, // Payne's gray
    vec3(39, 125, 161) / 255.0 // Cerulean
);

const vec3 colors7[] = vec3[](
vec3(176.,29.,30.) / 255.,
vec3(241.,104.,38.) / 255.,
vec3(234.,211.,95.) / 255.,
vec3(0.,187.,173.) / 255.,
vec3(0.,107.,228.) / 255.,
vec3(126.,99.,180.) / 255.);


/*const vec3 colors1[] = vec3[](
    vec3(60, 22, 66) / 255.0, // Russian violet
    vec3(8, 99, 117) / 255.0, // Caribbean Current
    vec3(29, 211, 176) / 255.0, // Turquoise
    vec3(175, 252, 65) / 255.0, // Green Yellow
    vec3(178, 255, 158) / 255.0 // Light green
);*/
/*const vec3 colors2[] = vec3[](
    vec3(112, 214, 255) / 255.0, // Pale azure
    vec3(255, 112, 166) / 255.0, // Cyclamen
    vec3(255, 151, 112) / 255.0, // Atomic tangerine
    vec3(255, 214, 112) / 255.0, // Naples yellow
    vec3(233, 255, 112) / 255.0  // Mindaro
);*/



// Allow up to 10 colors per palette
vec3 getColorRamp_(vec3 cols[10], int N, float x ) {
    // Calculate adjusted length to ensure end color is reachable within [0, 1]
    float len = float(N);
    
    // Scale x according to the adjusted length and apply modulo for wrapping
    float scaledX = mod(x * (len-1.), len);
    
    // Calculate indices. Ensure index2 wraps around to the start if necessary
    int index1 = int(scaledX);
    int index2 = index1 + 1;
    if (index2 >= cols.length()) {
        index2 = 0; // Wrap to the start to close the loop
    }
    
    // Calculate the fraction between the two indices for smooth interpolation
    float frac = fract(scaledX);
    
    // Interpolate between the two selected colors
    return mix(cols[index1], cols[index2], smoothstep(0.0, .9, frac));
}

vec3 getColorRamp(int palette, float x) {

    vec3 colors[10];
    int len;
    
    
    if(palette == 0) {
        len = colors1.length();
        COPY_COLOR(len, colors1);       
    }
    
    if(palette == 1) {
        len = colors2.length();
        COPY_COLOR(len, colors2);
    }
    if(palette == 2) {
        len = colors3.length();
        COPY_COLOR(len, colors3);
        
    }
    if(palette == 3) {
        len = colors4.length();
        COPY_COLOR(len, colors4);    
    }
    
    if(palette == 4) {
        len = colors5.length();
        COPY_COLOR(len, colors5);    
    }
    if(palette == 5) {
        len = colors6.length();
        COPY_COLOR(len, colors6);    
    }
    if(palette == 6) {
        len = colors7.length();
        COPY_COLOR(len, colors7);    
    }
    return getColorRamp_(colors, len, x);

}


#define TAU (2.*PI)
#define SIN(x) (sin(x)*.5+.5)
#define BUMP_EPS 0.004
#define sabsk(x, k) sqrt(x * x + k * k)
#define sabs(x) (sabsk(x, .01))
#define S(a, b, x) smoothstep(a, b, x)

vec3 pal(float x) {return .5+.5*cos(x*2.*PI-vec3(0, 23, 21));}


const highp float NOISE_GRANULARITY = 0.5/255.0;


float tt, g_mat;
vec3 ro;


mat2 rot(float a) { return mat2(cos(a), -sin(a), sin(a), cos(a)); }


float saturate(float x) {
    return clamp(x, 0., 1.);
}

// zucconis spectral palette https://www.alanzucconi.com/2017/07/15/improving-the-rainbow-2/
vec3 bump3y (vec3 x, vec3 yoffset)
{
    vec3 y = 1. - x * x;
    y = clamp((y-yoffset), vec3(0), vec3(1));
    return y;
}


// ortho normal basis 
void pixarONB(vec3 n, out vec3 b1, out vec3 b2){
	float sign_ = sign(n.z);
	float a = -1.0 / (sign_ + n.z);
	float b = n.x * n.y * a;
	b1 = vec3(1.0 + sign_ * n.x * n.x * a, sign_ * b, -sign_ * n.x);
	b2 = vec3(b, sign_ + n.y * n.y * a, -n.y);
}

vec3 invGamma(vec3 col) {
    return pow(col, vec3(2.2));
}

vec3 gamma(vec3 col) {
    return pow(col, vec3(1./2.2));
}

// Zucconi's spectral palette
vec3 spectral_zucconi6(float x) {
    x = fract(x);
    const vec3 c1 = vec3(3.54585104, 2.93225262, 2.41593945);
    const vec3 x1 = vec3(0.69549072, 0.49228336, 0.27699880);
    const vec3 y1 = vec3(0.02312639, 0.15225084, 0.52607955);
    const vec3 c2 = vec3(3.90307140, 3.21182957, 3.96587128);
    const vec3 x2 = vec3(0.11748627, 0.86755042, 0.66077860);
    const vec3 y2 = vec3(0.84897130, 0.88445281, 0.73949448);
    return bump3y(c1 * (x - x1), y1) + bump3y(c2 * (x - x2), y2) ;
}


// spectral palette by wavelength
vec3 waveSpectrum(float w){

    if(w > 700.0 || w < 400.0){
        return vec3(0);
    }
    
	float x = fract((w - 400.0)/ 300.0);
    
	vec3 col = spectral_zucconi6(x);

    // Undo gamma
    col = invGamma(col);

    return col;
}


// physical based diffraction grating
vec3 diffraction(vec3 rd, vec3 n, vec3 td, vec3 l, float d) {

    vec3 col = vec3(0);

    float cos_ThetaL = dot(l, td);
    float cos_ThetaV = dot(rd, td);
   
    float u = abs(cos_ThetaL - cos_ThetaV);
    
    if(u == 0.) {
        return vec3(0);
    }
    
    for(float i=1.; i < 2.; i++) {
        float wavelength = u * d / i;
        col += waveSpectrum(wavelength);
    }
    col = clamp(col, vec3(0), vec3(1));
    return col;
}


// from https://mercury.sexy/hg_sdf/
float pModPolar(inout vec2 p, float repetitions) {
	float angle = 2.*PI/repetitions;
	float a = atan(p.y, p.x) + angle/2.;
	float r = length(p);
	float c = floor(a/angle);
	a = mod(a,angle) - angle/2.;
	p = vec2(cos(a), sin(a))*r;
	// For an odd number of repetitions, fix cell index of the cell in -x direction
	// (cell index would be e.g. -5 and 5 in the two halves of the cell):
	if (abs(c) >= (repetitions/2.)) c = abs(c);
	return c;
}



float box(vec3 p, vec3 r) {
  vec3 d = abs(p) - r;
  return length(max(d, 0.0)) + min(max(d.x, max(d.y, d.z)), 0.0);
}


float smin(float a, float b, float k) {
  float h = clamp((a-b)/k * .5 + .5, 0.0, 1.0);
  return mix(a, b, h) - h*(1.-h)*k;
}

vec3 pMod(inout vec3 p, vec3 size) {
	vec3 c = floor((p + size*0.5)/size);
	p = mod(p + size*0.5, size) - size*0.5;
	return c;
}

vec2 pMod(inout vec2 p, vec2 size) {
	vec2 c = floor((p + size*0.5)/size);
	p = mod(p + size*0.5,size) - size*0.5;
	return c;
}

float pMod(inout float p, float size) {
	float halfsize = size*0.5;
	float c = floor((p + halfsize)/size);
	p = mod(p + halfsize, size) - halfsize;
	return c;
}

#define PHI 1.618033988749895

float n21(vec2 p) {
      return fract(sin(dot(p, vec2(524.423,123.34)))*3228324.345);
}

// smooth noise
float noise(vec2 n) {
    const vec2 d = vec2(0., 1.0);
    vec2 b = floor(n);
    vec2 f = mix(vec2(0.0), vec2(1.0), fract(n));
    return mix(mix(n21(b), n21(b + d.yx), f.x), mix(n21(b + d.xy), n21(b + d.yy), f.x), f.y);
}

float g_glow = 0.;


float smax( float a, float b, float k )
{
    float h = max(k-abs(a-b),0.0);
    return max(a, b) + h*h*0.25/k;
}


// Repeat only a few times: from indices <start> to <stop> (similar to above, but more flexible)
float pModInterval1(inout float p, float size, float start, float stop) {
	float halfsize = size*0.5;
	float c = floor((p + halfsize)/size);
	p = mod(p+halfsize, size) - halfsize;
	if (c > stop) { //yes, this might not be the best thing numerically.
		p += size*(c - stop);
		c = stop;
	}
	if (c <start) {
		p += size*(c - start);
		c = start;
	}
	return c;
}

vec3 g_p;



vec2 toPolar(vec2 p)
{
  return vec2(length(p), atan(p.y, p.x));
}

vec2 fromPolar(vec2 p)
{
 return vec2(cos(p.y) * p.x , sin(p.y) * p.x);
}

float caps( vec3 p, float h, float r )
{
  p.y -= clamp( p.y, 0.0, h );
  return length( p ) - r;
}


vec3 fold(vec3 p) {

    float c = cos(PI/5.), s = sqrt(.75 - c*c);
    
    vec3 n = vec3(-.5, -c, s);
    
    p = abs(p);;
    p -= 2.*min(0., dot(p, n))*n;
    
    p.xy = abs(p.xy);
    p -= 2.*min(0., dot(p, n))*n;
    
    p.xy = abs(p.xy);
    p -= 2.*min(0., dot(p, n))*n;
    
    return p;
}


vec3 kalei(vec3 p, vec3 b, float N) {
    for(float i = 0.; i < N; i++) {
        p.xy *= rot(PI*i/N);
        p = abs(p) - b;
    }
    return p;
}


float tv(vec3 p) {
    float l = length(p);
    float d = box(p, vec3(vec2(.4, .3)*mix(1., .6, p.z), .3))-0.02;
    
    d = mix(d, l-.4, .14);
    
    p.z += .58 + -l*.3;
    
    p.xy *= mix(.9, 1., l*4.);
    float inset = box(p, vec3(vec2(.4, .3)*.9, .18))-.02;
     
    if(p.z < .24 && p.z > .196 && abs(p.x) < .4 && abs(p.y) < .3) g_mat = 1.;
    d = max(d, -inset);
    
    return d;

}

vec3 g_id = vec3(0);
#define MODE (int(floor(mode-.1)))

#define IS_MODE_1_2 ( MODE== 1 || MODE==2)
#define MAPPING_MODE (int(floor(mapping_mode)))
#define COLOR_MODE (int(floor(color_mode)))

// used in MODE 1
vec3 transform(vec3 p) {

    p.xy *= rot(p.z*sin(.25*tt)/8.*twist);
    
    p.xy *= rot(.5*tt);

    return p;
}

float map(vec3 p) {
    p.xy = mix(p.xy, abs(p.xy), mirror);
    vec3 bp = p;
    g_mat = 0.;
    float d = 1e4;
    
    float forward = tt + beat_forward*syn_BassTime;
    if(MODE == 0) {
        
        p.xy *= rot(p.z*sin(.5*tt+.5*syn_BassTime)*.1*twist);
        if(kaleidoscope > .5)  p = fold(p)*vec3(1, 1, -1);   
        p.x += .75+spacing/2.;
        p.x +=  .2*sin(p.z*.4+tt);
        p.y +=  .2*sin(p.z*.3+tt);
        p.z += forward;

      //  p.xy = p.yx;
        g_id = pMod(p, vec3(1.5+spacing, 1.3, 1.5));
        
        float move = beat_wave*sin(.25*tt+syn_BassTime + dot(g_id, vec3(1, 2, 3))*.5);
    //    p.xy *= rot(.1*move);
      //          p.xz *= rot(.1*move);
        p.z += .2*move;
    }
    
    if(IS_MODE_1_2) {
        
        p = transform(p);
        
        p.z += forward;  
        
        g_p = p;
        
        if(MODE == 2) {
            //p.x = mix(p.x, abs(p.x), 1.)-5.;     
               if(kaleidoscope > .5) {
                            // p = fold(p);   
                pMod(p.z, 11.);
                p = fold(p); 
            }
            p.x = abs(p.x) - mix(2.5, 7., spacing);  
            g_id.yz = pMod(p.yz, vec2(.7, 1.));
            
            p.x += .9*SIN(length(g_id.yz/ vec2(1., 1.5))*.8 - 2.*tt - syn_BassTime*beat_wave);
            p.xz *= rot(PI/2.);
        
        } else {
               
            float id = pModPolar(p.xy, 16);
            if(kaleidoscope > .5) {
                            // p = fold(p);   
                pMod(p.z, 11.);
                p = fold(p); 
            }
                     
   
            float id2 = pMod(p.z, .9);
                          
            g_id.y = id*3.;
            g_id.x = id2;
    
            p.x -= 2.05 + spacing;
                    p.x += (-.2+.2*sin(length(g_id.xy/ vec2(1., .5))*1. - 2.*tt - syn_BassTime))*beat_wave;
            p.xz *= rot(PI/2.);
            g_id.y = id*3.;
        }

        
        
    }
    
    if(MODE == 3) {

            
        p.xz *= rot(p.y*sin(.5*tt+.5*syn_BassTime)*.5*twist);
        
        if(kaleidoscope > .5) {
             p.xy *= rot(tt);
             p.xz *= rot(.75*SIN(.5*tt));
            p = fold(p);
        }
        p.xy *= rot(tt);
        p.xz *= rot(.75*SIN(.5*tt));
    
        p = abs(p)-vec3(1.8, 1.3, 1.5)*(.3*SIN(tt+PI+syn_BassTime*beat_wave));
    
        p = abs(p)-vec3(1.8, 1.3, 1.5)*(.3+.04*syn_BassHits*syn_Intensity*beat_wave);
        
        p.z *= -1;
        
        g_id = vec3(1);
    }
    
    if( MODE < 4) {
        if(MODE == -1) {
            vec2 size = vec2(4., 3.2)*0.23;
            p /= 1.4;
              
            p.yz *= rot(sin(tt)*.3);
            p.xz *= rot(cos(tt*.5)*.3);
  
    
           float id = pModInterval1(p.x, size.x+spacing, -2, 2); 
           float id2 = pModInterval1(p.y, size.y+spacing, -1, 1);
          
            p.z += .3*sin(length(g_id.xy/ vec2(1., 1.5))*1.5 - 2.*tt - syn_BassTime*beat_wave);
            
            g_id = vec3(id, id2, 55);
        }
        
        g_p = p;
        d = tv(p);
    }
    if(MODE >= 4) {
  
        bp.xz *= rot(.5*SIN(.25*tt));
                
         //   p.y += sin(.25*syn_BassTime)*.5*syn_Intensity;
        p.xy *= rot(tt + .5*syn_BassTime);
        p.xz *= rot(.75*tt);
                        p.y += sin(.25*syn_BassTime)*.5*syn_Intensity;
        if(kaleidoscope > .5) p = fold(p);
        g_id = vec3(0);
            
        float id = pModPolar(p.xz, 6);
                      
        g_id.y = id*3.;

        p.x -= 1.3+spacing;
        p.xz *= rot(-PI/2.);
        g_p = p;
        d =  tv(p);
        
        p = bp;
            
        p.xy *= rot(-.75*tt+.5*PI);
        p.xz *= rot(-.5*tt+PI);
        if(kaleidoscope > .5) p = fold(p);
        //               p.xy *= rot(-.75*tt+.5*PI);
       if(mode > 4.5) p.xz *= rot(-.25*tt+PI-.1*syn_BassTime);
        
               // p.y += sin(-1.5*tt)*.5*syn_Intensity;
               
        
        id = pModPolar(p.xz, 12);
        
      //  g_id += id;
      
        p.x -= 2.15+spacing;
        p.xz *= rot(-PI/2.);
   
              p.yz *= rot((mod(tt, 2.*PI)+id+.75*PI)*twist);
        
        p.z += .3*sin(tt+10.*_hash11(id*10.) +PI*syn_BassTime)*syn_Intensity*beat_wave;
      
     
        
        float e = tv(p);
        
        g_p = e < d ? p : g_p;
        g_id = vec3((e < d ? id : g_id.x) + .9);
        
        d= min(e, d);
     
   
    }
    
    
      if(glow > .5 && MODE > 2) {
            float gd = length(bp)-.01;
            d = min(d, gd);
            float pw = MODE  < 4. ? 4. : 2.;
            g_glow += 1.5/(.5+pow(abs((gd)*2.), pw));
    }
    //float gd = box(bp- vec3(0, 0, sin(tt)*15+5.), vec3(10, 10, .1) )-.01;
    if(plasma > .2 && MODE <= 2) {
        bp.yz += vec2(0.05, 0.1)*sin(bp.xx*2.+syn_BeatTime*.5);
        float gd = MODE < 0 ? box(bp- vec3(0, sin(tt)*3., 0), vec3(5, 0.01, 2) )-.01: bp.z + sin(tt)*15. -10.;
       
        
        g_glow += MODE < 0 ? 1.5/(1.+pow(abs((gd)*20.), 10.)) : 1.5/(.5+pow(abs((gd)*3.), 8.)) ;
    }
     //d = min(e, d);
    return d*.7;

}


vec3 getNormal(vec3 p) {

    vec2 eps = vec2(0.001, 0.0);
    return normalize(vec3(map(p + eps.xyy) - map(p - eps.xyy),
                          map(p + eps.yxy) - map(p - eps.yxy),
                          map(p + eps.yyx) - map(p - eps.yyx)
                         )
                     );
}

float gridSurf( in vec3 p){

    p.z += .3*tt;
    p = abs(mod(p*2., 1.*0.125)-0.0125);
    
    float x = min(p.x,min(p.z, p.y))/0.03125;

    return clamp(x, 0., 1.);
}

// Standard function-based bump mapping function (from Shane)
vec3 doBumpMap(in vec3 p, in vec3 nor, float bumpfactor) {
    
    const float eps = BUMP_EPS;
    float ref = gridSurf(p);                 
    vec3 grad = vec3( gridSurf(vec3(p.x-eps, p.y, p.z))-ref,
                      gridSurf(vec3(p.x, p.y-eps, p.z))-ref,
                      gridSurf(vec3(p.x, p.y, p.z-eps))-ref )/eps;                     
          
    grad -= nor*dot(nor, grad);          
                      
    return normalize( nor + bumpfactor*grad );
}

// iq's shadow function
float softshadow( in vec3 ro, in vec3 rd, float mint, float maxt, float k ) {

    float res = 1.0;
    float ph = 1e20;
    for( float t=mint; t<maxt; )
    {
        float h = map(ro + rd*t);
        if( h<0.001 )
            return 0.0;
        float y = h*h/(2.0*ph);
        float d = sqrt(h*h-y*y);
        res = min( res, k*d/max(0.0,t-y) );
        ph = h;
        t += h;
    }
    return res;
}


// why not put the raymarcher in a separate function (;
vec3 raymarch(vec3 ro, vec3 rd, float steps) {

    float mat = 0.,
          t   = 0.,
          d   = 0.;
    vec3 p = ro;
    for(float i=.0; i<steps; i++) {
    
        d = map(p);
        mat = g_mat;  // save global material
        
        if(abs(d) < 0.0001 || t > 120.) break;
        
        t += d;
        p += rd*d;
    }
    
   // g_p = p;
    
    return vec3(t, mat, d);
}


// from iq code
float softshadow( in vec3 ro, in vec3 rd, in float mint, in float tmax )
{
	float res = 1.0;
    float t = mint;
    for( int i=0; i<1; i++ )
    {
		float h = map( ro + rd*t );
        res = min( res, 8.0*h/t );
        t += h*.25;
        if( h<0.001 || t>tmax ) break;
    }
    return clamp( res, 0., 1. );
}

float calcAO(vec3 p, vec3 n)
{
	float sca = 1.0, occ = 0.0;
    for( int i=0; i<5; i++ ){
    
        float hr = 0.01 + float(i)*0.5/3.0;        
        float dd = map(n * hr + p);
        occ += (hr - dd)*sca;
        sca *= 0.7;
    }
    return clamp( 1.0 - occ, 0.0, 1.0 );    
}


vec3 getRayDir(vec2 uv, vec3 p, vec3 l, float z) {
    
    // camera system
    vec3 f = normalize(l - p),  // forward vector
         r = normalize(cross(vec3(0, 1, 0), f)), // right vector
         u = cross(f, r), // up vector
         c = p + f * z, // center of virtual screen
         i = c + uv.x * r + uv.y * u, // intersection with screen
         rd = normalize(i - p);  // ray direction
         
    return rd;
    
}

// Shane awesome work below
// Tri-Planar blending function. Based on an old Nvidia tutorial.
vec3 tex3D( sampler2D tex, in vec3 p, in vec3 n ){
    
    //return cellTileColor(p);
  
    n = max((abs(n) - 0.2)*7., 0.001); // n = max(abs(n), 0.001), etc.
    n /= (n.x + n.y + n.z ); 
	return (texture(tex, p.yz)*n.x + texture(tex, p.zx)*n.y + texture(tex, p.xy)*n.z).xyz;
}



// Texture bump mapping. Four tri-planar lookups, or 12 texture lookups in total. I tried to 
// make it as concise as possible. Whether that translates to speed, or not, I couldn't say.
vec3 texBump( sampler2D tx, in vec3 p, in vec3 n, float bf){
   
    const vec2 e = vec2(0.002, 0);
    
    // Three gradient vectors rolled into a matrix, constructed with offset greyscale texture values.    
    mat3 m = mat3( tex3D(tx, p - e.xyy, n), tex3D(tx, p - e.yxy, n), tex3D(tx, p - e.yyx, n));
    
    vec3 coeffs = vec3(0.299, 0.587, 0.114);
    vec3 g = coeffs*m; // Converting to greyscale.
    g = (g - dot(tex3D(tx,  p , n), coeffs) )/e.x; g -= n*dot(n, g);
                      
    return normalize( n + g*bf ); // Bumped normal. "bf" - bump factor.
	
}

void cam(inout vec3 p) {


    // p.yz *= rot(0.01);
   // p.yz *= rot(PI*.12);
    //p.xz *= rot(.25*PI);
    //p.xz *= rot(PI*.5*curve(tt, 1.));
}




vec2 getMediaUV(vec2 uvMedia) {
    

        float l = length(uvMedia);
           ivec2 mediaRes = textureSize(syn_Media, 0);

        uvMedia += .5;
      //  if(rot_media > .5) uvMedia = uvMedia.yx;
        //uvMedia *= mix(1., mix(.8, 1.2, SIN(length(_uvc)*4. + .5*syn_Time) ), .2);
        
        uvMedia -= .5;
  
     
        float mediaAspect = float(min(mediaRes.x, mediaRes.y))/float(max(mediaRes.x, mediaRes.y));
    
        float renderAspect = float(min(RENDERSIZE.x, RENDERSIZE.y))/float(max(RENDERSIZE.x, RENDERSIZE.y));
    
      
        if(mediaRes.x < mediaRes.y) {
            uvMedia = (uvMedia +.5)*vec2(1, mediaAspect)-.5;
        } else {
           uvMedia = (uvMedia +.5)*vec2(mediaAspect, 1)-.5;
        }


        if(mediaRes.y > mediaRes.x) {
            uvMedia.y +=.22;
           // uvMedia *= .8;
        }
    
        if(mediaRes.y < mediaRes.x && mediaAspect < .9) {           
                uvMedia.x += .22;
        }

        return uvMedia;
    
}

// Optimize for resize.
#define res (RENDERSIZE / 1.8)

// Hardness of scanline.
//  -8.0 = soft
// -16.0 = medium
float hardScan = -8.0;

// Hardness of pixels in scanline.
// -2.0 = soft
// -4.0 = hard
float hardPix = -3.0;

// Display warp.
// 0.0 = none
// 1.0/8.0 = extreme
vec2 warp = vec2(2.0 / 32.0, 2.0 / 24.0);

// Amount of shadow mask.
float maskDark  = 0.5;
float maskLight = 1.5;

// ------------------------------------------------------------
// sRGB <-> Linear (usually unnecessary if using sRGB textures)

float toLinear1(float c) { return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
vec3  toLinear(vec3 c)   { return vec3(toLinear1(c.r), toLinear1(c.g), toLinear1(c.b)); }

float toSrgb1(float c) { return (c < 0.0031308) ? c * 12.92 : 1.055 * pow(c, 0.41666) - 0.055; }
vec3  toSrgb(vec3 c)   { return vec3(toSrgb1(c.r), toSrgb1(c.g), toSrgb1(c.b)); }

// ------------------------------------------------------------
// Nearest emulated sample given floating point uv and texel offset.
// Zeros off-screen.

vec3 fetch(vec2 uv, vec2 off) {
  uv = floor(uv * res + off) / res;
  if (max(abs(uv.x - 0.5), abs(uv.y - 0.5)) > 0.5) return vec3(0.0);
  return toLinear(texture(syn_Media, uv).rgb);
}

// Distance in emulated pixels to nearest texel (signed).
vec2 dist(vec2 uv) {
  uv = uv * res;
  return -((uv - floor(uv)) - vec2(0.5));
}

// 1D Gaussian.
float gauss(float x, float scale) {
  return exp2(scale * x * x);
}

// 3-tap Gaussian filter along horizontal line.
vec3 horz3(vec2 uv, float off) {
  vec3 b = fetch(uv, vec2(-1.0, off));
  vec3 c = fetch(uv, vec2( 0.0, off));
  vec3 d = fetch(uv, vec2( 1.0, off));

  float dx = dist(uv).x;
  float s  = hardPix;

  float wb = gauss(dx - 1.0, s);
  float wc = gauss(dx + 0.0, s);
  float wd = gauss(dx + 1.0, s);

  return (b * wb + c * wc + d * wd) / (wb + wc + wd);
}

// 5-tap Gaussian filter along horizontal line.
vec3 horz5(vec2 uv, float off) {
  vec3 a = fetch(uv, vec2(-2.0, off));
  vec3 b = fetch(uv, vec2(-1.0, off));
  vec3 c = fetch(uv, vec2( 0.0, off));
  vec3 d = fetch(uv, vec2( 1.0, off));
  vec3 e = fetch(uv, vec2( 2.0, off));

  float dx = dist(uv).x;
  float s  = hardPix;

  float wa = gauss(dx - 2.0, s);
  float wb = gauss(dx - 1.0, s);
  float wc = gauss(dx + 0.0, s);
  float wd = gauss(dx + 1.0, s);
  float we = gauss(dx + 2.0, s);

  return (a * wa + b * wb + c * wc + d * wd + e * we) / (wa + wb + wc + wd + we);
}

// Return scanline weight.
float scanline(vec2 uv, float off) {
  float dy = dist(uv).y;
  return gauss(dy + off, hardScan);
}

// Allow nearest three lines to affect pixel.
vec3 triScan(vec2 uv) {
  vec3 a = horz3(uv, -1.0);
  vec3 b = horz5(uv,  0.0);
  vec3 c = horz3(uv,  1.0);

  float wa = scanline(uv, -1.0);
  float wb = scanline(uv,  0.0);
  float wc = scanline(uv,  1.0);

  return a * wa + b * wb + c * wc;
}

//Distortion of scanlines, and end-of-screen alpha.
vec2 warpScan(vec2 uv) {
  vec2 warp = vec2(1.0 / 32.0, 1.0 / 24.0);
  uv = uv * 2.0 - 1.0;
  uv *= vec2(1.0 + (uv.y * uv.y) * warp.x, 1.0 + (uv.x * uv.x) * warp.y);
  return uv * 0.5 + 0.5;
}

vec4 renderMainImage() {
	vec4 fragColor = vec4(0.0);
	vec2 fragCoord = _xy;

   	vec2 uv = (fragCoord - .5*RENDERSIZE.xy)/RENDERSIZE.y;
   // uv = uv.yx;
    tt = 2.*speed;
    float zoom = 9.;// mix(4., 9., SIN(.4*TIME));,w
    vec3  lp = vec3(2., 2.,  -10.),
          lp2 = vec3(-2.,4, -10.);


    //uv.xy *= rot(PI*.5);
    //uv = uv.yx;
    vec3 col = vec3(0);
        
    vec3 media = texture(syn_Media, getMediaUV(_uvc)+.5).rgb;
    vec3 glowColor = mix(glow_color, media, media_glow_blend);
    if(COLOR_MODE == 0)  glowColor = vec3(0.04, 1, .3)*.6;
    if(COLOR_MODE == 2)  glowColor = vec3(.9, .95, 1.);
    

    ro = vec3(0., 0, -5. + cam_z);
    
    float lookat_y = (MODE >=0 && MODE < 3)? cam_lookat: 0;
    if(MODE == 4 ) ro.z -= 3.;
    if(IS_MODE_1_2 && kaleidoscope < .5) ro.z -= 2.;
    vec3 lookat = vec3(0, lookat_y, 0), p;
    vec3 bg = vec3(0);
 
    
    
    if(MODE <= 2) {
       bg = mix(bg, glowColor*1.7, syn_BassHits*syn_BassPresence*glow*(1.-length(uv)));
        
    }
    
    //*S(0., 1., SIN(length(uv)*3.-tt-syn_BassTime)))
    
    if(MODE == 3) glowColor *= 1.4;
    cam(ro);
    cam(lp);
    cam(lp2);

    vec3 rd = getRayDir(uv, ro, lookat, 1.2);
       
    
    float mat = 0.,
          t   = 0.,
          d   = 0.;

    vec2 e = vec2(0.0035, -0.0035);
     
    // background color
    vec3 c1 = vec3(0.106,0.255,0.275);
    vec3 c2 = vec3(0.165,0.051,0.286);
    
    // light color
    vec3 lc1 = vec3(0.910,0.843,0.957);
    vec3 lc2 = vec3(0.757,0.941,0.941);
    
    float alpha = 1.;
    
    
    // currently only one pass
    for(float i = 0.; i < 1.; i++) {
        float steps = i > 0. ? 50. : 150.;
        vec3 rm = raymarch(ro, rd, steps);
        
        vec3 id = g_id;
        mat = rm.y;
         float t = rm.x;
        
        vec3 pp = g_p;

        vec3 p = ro + rm.x*rd;
        
        //p = g_p;
        vec3 n = normalize( e.xyy*map(p+e.xyy) + e.yyx*map(p+e.yyx) +
                            e.yxy*map(p+e.yxy) + e.xxx*map(p+e.xxx));
 
        vec3 al = color;
       
        int isScreen = 0;
        if(mat > .5) {
            isScreen = 1;
            al = vec3(0.05);
        }
        
        
        if(rm.z < 0.0001) {
        
            vec3 l = normalize(lp-p);
            vec3 l2 = normalize(lp2-p);
            float dif = max(dot(n, l), .0);
            float dif2 = max(dot(n, l2), .0);
            float spe = pow(max(dot(reflect(-rd, n), -l), .0), 50.);
            
            float shd=softshadow( p, l, 0.1, 10. );
       
            float sss = smoothstep(0., 1., map(p + l * .3)) / .4;
            float sss2 = smoothstep(0., 1., map(p + l2 * .3)) / .4;


            vec3 n2 = n;
            vec3 p2 = pp;
            n2.xy += noise(p2.xy*vec2(.5, .8) + 1.5*SIN(tt)) * .6 - .025;
            n2 = normalize(n2);
            float height = atan(n2.y, n2.x);

            vec3 iri = spectral_zucconi6(height*1.11)*smoothstep(.8, .2, abs(n2.z))-.02;
            
            float ao = calcAO(p, n);           

    
            rd = reflect(rd, n);
            rd.xz *= rot(.9);
             rd.xy *= rot(.2);
         
            vec3 refl = texture(cubemap26, rd).rrr;
            float h1 = _noise(abs(id));
            float h2 = _noise(abs(id) + 0.*tt+.5*syn_BassTime);
            float h3= _hash13(abs(id) + 32);
            float h = mix(h1, h2, .1+.6*syn_Intensity);
            int tvState = 1;
            
            if(h > 1.-(static_thres)) tvState = 2;
            if(h1 < .03) tvState = 0;
            
            if(isScreen > 0) {
                col = al*(dif*lc1 + dif2*lc2) + .1*iri + .5*spe; 
                col = mix(col, col+refl, .1);

                float refract_amount = mix(1., (1.-(h1)*.3*syn_BassHits), beat_refract);
                vec2 uvScreen = getMediaUV(_uvc*refract_amount)+.5;
                
          
                if(MODE ==1 && kaleidoscope < .5) {
                    p = transform(p);
                    uvScreen = fract((p.yz-vec2(0., 1.))*.1+.5);
                   // pp.xy *=2.;
                }
                // auto 
                
                vec2 uvMedia = getMediaUV(pp.xy*2.)+.5;
                                uvMedia = (uvMedia-.5)*refract_amount+.5;
                
                if(MAPPING_MODE  == 0) uvMedia = mix(uvMedia, uvScreen, S(0., 1., SIN(.5*TIME))); 
                
                // individual
                if(MAPPING_MODE > 0) {
                    uvMedia = mix(uvMedia, uvScreen, float(MAPPING_MODE -1)); 
                }
            
                uvMedia = warpScan(uvMedia);
        
                vec3 media = triScan(uvMedia);
 
                 //   vec3 media = texture(syn_Media, uvMedia).rgb;
                media = invGamma(media)*2.*media_level; // gammab

                // static
                if(tvState == 2) {
                    media = vec3(_noise(vec3(pp.xy*120. + vec2((10.*syn_BassHits*syn_BassPresence+5.)*_noise(pp.y*20), 4.*tt) +2.*syn_BassTime, 30.*tt)))*.9;
                    
                }
                //if(mod(id.x + id.y +id.z, 2) > .5) {
                if(h1 < .6) media *= mix(.8, 2.4, syn_BassHits);
                float lum = _luminance(media);
                if(COLOR_MODE == 0  ) {
                     media = lum*mix(vec3(1), vec3(0, 1, .5*S(.8, 1., pow(lum, 8.))), .9);  // green monochrome
                } else if(COLOR_MODE == 2) {
                     media = vec3(lum); 
                }
                
                media = _rgb2hsv(media);
                
                if(h1 >= 1.-hue_shift_thres) media.x += .5*h1;
                media = _hsv2rgb(media);
                  
            
                if(tvState == 0) {
                    media *= 0.;
                }
                
  
                col += media;


                // vignette
                col *= mix(1., .0, length(pp.xy)*2.);
            } else {
                al = color;
         
                if(h3 < .4) al = al.bgr*.4;
                col = al*vec3(.5*sss + dif*lc1 + dif2*lc2 + .5*sss2) + .04*iri;
                col *= mix(1., ao, .9);
               
            }
    

            // status led
            vec3 statusColor = vec3(0, .9, 0);
            if(tvState == 0) statusColor = vec3(.9, .0, 0);
            if(tvState == 2) statusColor = vec3(.9, .6, 0);
            p = pp;
            
            if(p.z < .1) {
               p.xy += -vec2(.355, -.313)*.94;
      
                col = mix(col, statusColor, S(.001, 0.0, length(p.xy)-.004));
            }
            
            float fog = exp(-t*t*0.002);
            
            col = mix(bg, col, fog);
          

        } else {        
            
   
            alpha = 0.;
            col = bg;
            
            col += glow*syn_BassHits*glowColor*3./(t*t);

        } 
        
        if(IS_MODE_1_2) g_glow *= .4;
        float glowTotal = (MODE > 2 ? .15*glow*syn_BassHits : 0.05*plasma*mix(.3, 1., syn_BassHits))*g_glow;
        alpha += .8*glow;
        col += glowTotal*glowColor;
        
     //  col += .15*g_glow2 *vec3(1.000,0.827,0.361) *SIN(10.*length(uv)+5.*tt);
    }


   // col += mix(-NOISE_GRANULARITY, NOISE_GRANULARITY, random(uv));
    col *= mix(.2, 1., (1.5-pow(dot(uv, uv), .3))); // vignette
    
    col = pow(col*1.3, vec3(2.2));

    col = gamma(col); // gammab
    col = tanh(col*1.); 

   //col = vec3(alpha);
    fragColor = vec4(col, tanh(alpha));
 
	return fragColor; 
 } 


vec4 renderMain(){
    return renderMainImage();


}
