
#include "hg_sdf.glsl"

float lookatme_z = 0.0;
vec3 lookatme = vec3 (lookatme_x, lookatme_y,lookatme_z);

uniform float positiongymnastics1;
uniform float positiongymnastics2;
uniform float positiongymnastics3;

float iTime = script_reactive_time;
float glow = 0.;
float fog = 0.;
float mat = 0.;
float pi = 3.14159;
float cam_zoom = 0.0;



// Basic Functions //
// Rotation Function from evvvvil_ on Twitch, the guy who makes these shaders in 30 mins or less: https://twitch.tv/evvvvil_

mat2 r2(float r){return mat2(cos(r),sin(r),-sin(r),cos(r));}

// The rest of the functions are from Inigo Quilez, the king of raymarching: https://iquilezles.org/articles/distfunctions/



float sdPlane( vec3 p, vec3 n, float h )
{
  // n must be normalized
  return dot(p,n) + h;
}

float opSmoothSubtraction( float d1, float d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2+d1)/k, 0.0, 1.0 );
    return mix( d2, -d1, h ) + k*h*(1.0-h); }

float opUnion( float d1, float d2 ) { return min(d1,d2); }


            
float opRepLim( in vec3 p, in float c, in vec3 l)
            {
                vec3 np = p-c*clamp(round(p/c),-l,l);
                return fHexagonCircumcircle(np, vec2(1.5,2.));
            }
float opRepLim2( in vec3 p, in float c, in vec3 l)
            {
                vec3 np = p-c*clamp(round(p/c),-l,l);
                return fCapsule(np, 0.4, 5.);
            }

float opRepLim3( in vec3 p, in float c, in vec3 l)
            {
                vec3 np = p-c*clamp(round(p/c),-l,l);
                return fOctahedron(np, 3., 1.);
            }
            
float opTwist( in float boxframe, in vec3 p )                   
            {
                float k = twistamount; // Twist amount.
                float c = cos(k*p.z);
                float s = sin(k*p.z);
                mat2  m = mat2(c,-s,s,c);
                p = vec3(m*p.yz,p.x);
                p= mix(p,vec3(m*p.xy,p.z),twistdirection);
                return opRepLim3(p, 5., vec3(5.));
            }
                    


vec2 map(in vec3 p) {
        float glow;
                float spherecut = fSphere(p - vec3(cam_x,cam_y,cam_zoom),5.);
                        if (spherecut < 0.0001){mat = 3.;}
                        float d = 0.;
                d = min(d, spherecut);
        vec3 np = p;
        float syn_Time = iTime;
        for(int i=0;i<5;i++){
            p.z = pMirror (np.z, 1.);
            //np=abs(np);
            p.x = pModPolar(np.xz, 7.);
            
            np.xy*=r2(syn_Time*0.05+sin(p.y*0.2+syn_Time*5.)*0.02);
            //np.yz*=r2(syn_Time*0.05+sin(p.x*0.1+syn_Time*3.)*- 0.05);
            np.x += 0.002;
           // np.xz*=r2(syn_Time*0.02+sin(p.x*0.1+syn_Time*3.)*0.05);
            np.x += 2.;
        // Symmetry cloning of everything, based on a function of Evvvvil's
            }


        np*=mix(vec3(0.5,0.2,0.3),vec3(0.3),fractalmorph);  np.xz+=mix(0.5,2.,fractalmorph);//np.yz+=0.5;
      
        // p.x = pModPolar(p.xz, 2.);
        float capsule = fCapsule(np, vec3 (2., 0.,0.), vec3 (2.,0.,0.), 0.6);
    
        // float boxframe = opRepLim3(p, 5., vec3(1.)); 
        capsule = opTwist(capsule, np);//Limited Repetition and twist of the capsule.
        //float boxframe = sdBoxFrame(p,vec3 (2.,3.,3.), 0.75);        //Just one box frame.
       
               if (capsule < 0.0001){mat = 1.;}
       
            //p.y = pModPolar(p.xz, 3.);
            p.z*=(2.0);
        float boxframe = opRepLim(vec3(np), 4., vec3 (5.0,10.,3.));
        
        
                if (boxframe < 0.0001){mat = 2.;}
                
                d = min(d, boxframe);

        float scene = min(boxframe, capsule);

        float scene2 = fOpDifferenceChamfer (scene, (spherecut), 3.);
 
        // float scene2 = min(scene, plane);

        // glow +=0.1/(0.1*scene*scene*1000.0);
    
    return vec2 (scene2, mat);
}


// Normals for lighting, thanks to Synesthesia.

vec3 getNorm(vec3 np) {
	float d = map(np).x;
    vec2 e = vec2(.001, 0);
    vec3 n = d - vec3(
        map(np-e.xyy).x,
        map(np-e.yxy).x,
        map(np-e.yyx).x);
    return normalize(n);
}

const int max_steps = 120;


// Material Color function inspired by Psybernautics.


vec3 getObjectColor(vec3 p){
    float mat = map(p).y;
    vec3 col = vec3(0.0,0.0,0.0);
    vec3 norm = getNorm(p);
    float height = clamp(atan(norm.y, norm.x),-5.,5.);
	col = cos((height + vec3(0., .33, .67) * pi) * 2.) * .5 + .5;
    col *= smoothstep(.95, .25, abs(norm.z));
    
    vec4 media = _loadMedia(pow(norm.xz, vec2(2.))*media_displacement);
    if(_isMediaActive()) {
        col = normalize(media.rgb - col.rgb);
    }
    col = clamp(col, 0.0, 1.);
    return col;
}


vec4 raymarch(in vec3 ro, in vec3 rd) {
    float syn_Time = iTime;
    float TIME = iTime;
    vec3 col = vec3(0.);
    vec3 p = ro;
    float d = map(p).x;
    int steps = 1;
    bool hit = false;
    vec3 fog = vec3(0.2)*(1.0-(length(_uv)-0.2));    //  Background and fog values here.
    vec3 background = fog;  


 
    for (steps; steps<max_steps; steps++) {
        p = ro + rd * d;
     
        float dist_step = map(p).x;
        float scene = dist_step;
        d += dist_step;
         glow += d;
        // glow +=0.1/(0.1*scene*scene*1000.0);

        if (dist_step < 0.0008) {
            hit = true;
            break;
        } 
    }
    
    float dist_step = map(p).x;
    float scene = dist_step;
    // glow +=0.1/(0.1*scene*scene*1000.0);
    d += dist_step;
        
    float edgeGlow = glow * smoothstep(steps, 0.0, d) * (1/d) * EdgeGlow * EdgeGlow;
    if (hit) {
      
        float scene = 0.;
       
        vec3 norm = getNorm(p);
        vec3 objcol = getObjectColor(p);  
          
                    
          // basic phong lighting
          
            vec3 lightcol = vec3(0.8,0.85,0.8); // cool light
            vec3 lightpos = vec3(0.,0.,-5); // place light at top right of default view, slightly in front of object
            vec3 lightdir = normalize(lightpos - p); // calculate direction to the light
            vec3 diff = max(dot(norm,lightdir),0.) * lightcol;
            vec3 amb = lightcol * .6;// ambient light, multiplier determines strength
            float specularStrength = 0.5;
            vec3 viewDir = normalize(ro - p);
            vec3 reflectDir = reflect(-1.0 * lightdir, norm);  
            float spec = pow(max(dot(viewDir, reflectDir), 0.1), 8.0);
            vec3 specular = specularStrength * spec * lightcol; 
            float something = dot(norm,rd);
            float fresnel = pow((1.0+something),1.5);
            vec3 fog = vec3(0.2)*(1.0-(length(_uv)-0.2));
           
            col = (amb + diff + specular) * objcol * 1.;
            col += (edgeGlow*0.000004)*(fresnel*0.5);
           

            col = mix(col,fog, 0.5 * fresnel);
            col = mix(col,fog, 1.0-exp(-0.00003*pow(mat,1.0)));
 
        
    } else { 
        p = ro + rd * d;
        vec3 norm = getNorm(p);
        float dist_step = map(p).x;
        d += dist_step;
        glow += d;

        vec3 fog = vec3(0.05,0.05,0.05)*(1.0-(length(_uv)-0.2)*((length(_uv)-0.2))*((-length(_uv)-0.2)));
        float something = dot(vec3(1.0),vec3(0.0));
        float fresnel = pow((1.0+something),5.);
        glow +=0.1/(0.1*scene*scene*1000.0);

       float height = atan(norm.y, norm.x);
       
	    col = mix((mix(vec3 (0.0),fog, fogmix)), vec3(1.0), lightbackground);
        col += smoothstep(.95, .25, abs(norm.z));
    }
    
    fog = vec3(0.1)*(1.0-(length(_uv)-0.2)*((length(_uv)-0.2))*((-length(_uv)-0.2)));


    col += edgeGlow;
    return vec4(col, 1.);
}

// Camera defined here.

vec4 mainView(in vec2 uv) {

    float syn_Time = iTime;
    float TIME = iTime;
    vec3 ro = vec3(cam_x,cam_y,cam_zoom);
    vec3 rd = normalize(vec3(uv, 1.0));
    vec3 p = ro;
    vec3 cw = normalize(vec3 (lookatme.x,lookatme.y, lookatme.z));
    vec3 cu = normalize(cross(cw, vec3 (0.,1.,0.)));
    vec3 cv = normalize(cross(cu, cw));
    rd = mat3(cu,cv,cw)*normalize(vec3(uv, 0.5));
    
    return raymarch(ro, rd);
}


vec4 renderMain(void) {
    if (PASSINDEX == 0){

        vec3 p = vec3(cam_x,cam_y,cam_zoom);
    
        vec2 aspect = RENDERSIZE.xy/RENDERSIZE.x;
        vec2 uvc2 = _uvc * 2.;

        return mainView(_uvc);

    }
}