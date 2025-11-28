const float gamma = 2.2;
const vec3 gamma_vec = gamma * vec3(1.,1.,1.);
const vec3 col_x = pow(vec3(209., 48., 107.)/255., gamma_vec);
const vec3 col_y = pow(vec3(52., 235., 186.)/255., gamma_vec);
const vec3 col_z = pow(vec3(125., 57., 219.)/255., gamma_vec);
const vec3 col_sky = pow(vec3(0.2,0.2,0.2),gamma_vec);
const vec3 col_core = pow(vec3(0.8,.8,.8), gamma_vec);

vec2 rot2d(vec2 v, float angle){
    float s = sin(angle);
    float c = cos(angle);
    
    return vec2(
        c*v.x - s*v.y, s*v.x + c*v.y
    );
}

vec3 rot(vec3 v, float azimuth, float altitude){
    vec3 u = v;
    u.yz = rot2d(u.yz, altitude);
    u.xz = rot2d(u.xz,azimuth);
    return u;
}


// https://iquilezles.org/articles/smin/
vec2 smin( float a, float b, float k )
{
    float h = 1.0 - min( abs(a-b)/(4.0*k), 1.0 );
    float w = h*h;
    float m = w*0.5;
    float s = w*k;
    return (a<b) ? vec2(a-s,m) : vec2(b-s,1.0-m);
}


float sdf_box( vec3 p, vec3 b, float r )
{
  vec3 q = abs(p) - b + r;
  return length(max(q,0.0)) + min(max(q.x,max(q.y,q.z)),0.0) - r;
}

//multiply two vector quats
vec4 imuli(vec3 v, vec3 w){
    return vec4(cross(v,w),-dot(v,w));
}

//quat times vector quat
vec4 qmuli(vec4 q, vec3 v){
    return q.w * vec4(v,0.) + imuli(q.xyz, v);
}


//quat times quat
vec4 qmulq(vec4 q, vec4 p){
    return q * p.w + qmuli(q,p.xyz);
}

vec4 qconj(vec4 q){
    return vec4(-q.xyz,q.w);
}

vec3 adjoint(vec4 q, vec3 x){
    return qmulq(qmuli(q, x), qconj(q) ).xyz;
}


struct Surface{
    float sdf;
    vec3 color;
};

Surface sunion(Surface a, Surface b){
    if (a.sdf < b.sdf){
        return a;
    }
    return b;
}

Surface smooth_union(Surface a, Surface b, float k){
    vec2 smoothing = smin(a.sdf,b.sdf,k);
    
    return Surface(
        smoothing.x,
        mix(a.color, b.color, smoothing.y)
    );
}


Surface sdf_axes(vec3 p){

    
    const float size = 0.5;
    const vec3 b = vec3(40.,size, size);
    const float r = 0.1;
    return sunion(
        Surface(sdf_box(p, b.xyz, r), col_x),
        sunion(
            Surface(sdf_box(p, b.yzx, r), col_y),
            Surface(sdf_box(p, b.zxy, r), col_z)
            )
        );
}

const float marker_distance = sqrt(2./0.03);

//unused 
Surface markers(vec3 p){
    vec3 q = abs(p);
    
    const vec3 marker_center = normalize(vec3(1.,1.,1.)) * marker_distance;
    
    return Surface(
        length(q-marker_center) - 0.5,
        
        col_core
    );
}

float rotation_angle_at_r2(float r2){
    return 6.28318530718 * smoothstep(0.,1.,1. /(1.+0.01*r2));
}

vec4 quaternion_at_r2(float r2, float lambda){
    float rangle =  rotation_angle_at_r2(r2);
    float c = cos(rangle*0.5);
    float s = sin(rangle*0.5);
    
    float cl = cos(lambda);
    float sl = sin(lambda);

    vec4 base_q = vec4(cl*s,sl,0.,cl*c);
    vec4 q = base_q;
    q.wy = rot2d(q.wy, -lambda);
    return q;
}


Surface scene(vec3 pos){

    float st = 2.*smoothstep(0.,1.,fract(0.65+0.1*iTime))-1.;
    float lambda = 1.57079632679 * (st*st*st);
    
    
    vec4 q = quaternion_at_r2(dot(pos,pos), lambda);
    
    vec3 x = adjoint(q,pos);
    
    
    Surface box = Surface(sdf_box(x, vec3(1.,1.,1.), 0.2), col_core);
    Surface axes = sdf_axes(x);
    
    Surface surf = smooth_union(box,axes,0.02);
    
    Surface sky = Surface( - (length(pos)-26.0), col_sky);
    
    surf = smooth_union(surf, sky,3.0);
    
    return surf;
    
}

const vec3 light = normalize(vec3(1.,-2.,0.3));

vec3 march(vec3 cam, vec3 ray){
    float t = 2.0;
    int it=0;
    float min_dist = 5000.0;
    
    for (it=0; it<1000; it++){
        if (t > 100.){
            break;
        }
        vec3 pos = cam + ray*t;
        Surface surf = scene(pos);
        float dist = surf.sdf;
        
        min_dist = min(dist, min_dist);
        
        if (dist < 0.01){
            const float delta = 0.002;
            float ndotl = (scene(pos-delta*light).sdf-dist)/delta;
            float ao = pow(clamp(50./float(it),0.,1.),0.5);
            vec3 shading = 0.7*vec3(1.1,1.1,1.)*smoothstep(-0.3,1.0,ndotl)+ ao*vec3(0.4,0.4,0.7);
            
            return surf.color * shading;
        }
        //unfortunately the sdf is highly imperfect,
        //so we need to march very carefully and with a lot of iterations.
        t += 0.2*dist;
    }
    
    return vec3(1.,0.,1.);
}


void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 viewport = (fragCoord - 0.5*iResolution.xy)/iResolution.y;
    vec3 cam = vec3(0.,0.,-25.);
    vec3 ray = normalize(vec3(viewport, 1.5));
    
    float azimuth = 0.7 + iTime * 0.0425;
    float altitude = 0.4;
    
    cam = rot(cam, azimuth, altitude);
    ray = rot(ray, azimuth, altitude);
    
    
    vec3 col = march(cam,ray);
    fragColor = vec4(pow(col,1./gamma * vec3(1.,1.,1.)),1.0);
}
