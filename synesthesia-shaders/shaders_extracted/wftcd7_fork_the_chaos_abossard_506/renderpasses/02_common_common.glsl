// Common

// Constants
#define PI (3.141592)
#define FLT_MAX (1e12)
#define EPS (1e-12)

// Engine internals
#define GRAVITY (vec2(0,-1.)) 
#define ALLOWED_PENETRATION (.0005)
#define K_BIAS_FACTOR (.2)
#define MAX_VELOCITY (10.)
#define MAX_ANG_VELOCITY (100.)

// Factory example 
#define SPAWN_COOLDOWN (.05)
#define VIEW_ZOOM (1.4+.1*exp(-iTime))
#define VIEW_OFFSET (vec2(0,.05))
#define VIEW(P) (VIEW_ZOOM*(2.0*(P).xy-iResolution.xy)/iResolution.y+VIEW_OFFSET)
#define FACTORY_FIXED_BODIES (70)
#define FACTORY_MOVING_BODIES (60)
#define FACTORY_JOINTS (30)
#define BOX_SIZE 1.*(.03 + vec2(.03*rnd.xz))
#define BOX_MASS (.05)
#define BOX_FRICTION (10.)
#define INIT_SEED (int(3. + 1.*iDate.w*100.))

#define MOUSE_DOWN (iMouse.z > 0.)

vec3 hash31(uint q) // https://www.shadertoy.com/view/XdGfRR
{
	uvec3 n = q * uvec3(1597334673U, 3812015801U, 2798796415U);
	n = (n.x ^ n.y ^ n.z) * uvec3(1597334673U, 3812015801U, 2798796415U);
	return vec3(n) * 2.328306437080797e-10;
}

float rcp(float x) { return 1. / x; }
vec2 rcp(vec2 v) { return vec2(rcp(v.x), rcp(v.y)); }
float saturate(float x) { return clamp(x, 0., 1.); }
float dot2(vec2 v) { return dot(v, v); }
float cross2(vec2 a, vec2 b) { return a.x * b.y - a.y * b.x; }
vec2 cross2(vec2 a, float b) { return vec2(a.y * b, a.x * -b); }
vec2 cross2(float a, vec2 b) { return vec2(b.y * -a, b.x * a); }
float smoothsquare(float x, float eps) { float s = sin(2.*PI*x); return .5+.5*s*rcp(sqrt(s*s+eps*eps)); }
mat2 m_abs(mat2 m) { return mat2(abs(m[0]), abs(m[1])); }

mat2 rot(float a)
{
    float c = cos(a);
    float s = sin(a);
    return mat2(c, s, -s, c);
}

struct Globals
{
    ivec2 res;
    int n_body;
    int n_joint;
    float time;
    // factory example specific fields :
    float t_added; 
    int n_funnel;
    int funnel_b_id;
    int mode;
};

#define size_of_Globals (9)
#define pixel_count_of_Globals (3)

struct Body 
{
    vec2 pos;    
    vec2 vel;
    
    float ang;
    float ang_vel;
    
    vec2 size;
    float inv_mass;
    float inv_friction;
    float inv_i;
};

#define size_of_Body (11)
#define pixel_count_of_Body (3)

struct Joint
{
    int b0_id;
    int b1_id;
    vec2 loc_anc0;
    vec2 loc_anc1;
    float bias_factor;
    float softness;
    vec2 r0;
    vec2 r1;
    mat2 M;
    vec2 bias;
    vec2 P;
};

#define size_of_Joint (20)
#define pixel_count_of_Joint (5)

struct Contact
{
    vec2 pos;
    vec2 normal;
    float sep;
    
    float mass_n;
    float mass_t;
    float bias;
};

#define size_of_Contact (8)
#define pixel_count_of_Contact (2)

int address(int width, ivec2 addr2D)
{
    return addr2D.x + addr2D.y * width; 
}

int bufferAddress(sampler2D buff, ivec2 addr2D)
{
    return address(textureSize(buff, 0).x, addr2D);
}

ivec2 address2D(int width, int addr)
{
    return ivec2(addr % width, addr / width);
}

ivec2 address2D(ivec2 res, int addr)
{
    return address2D(res.x, addr);
}

ivec2 address2D(vec2 res, int addr)
{
    return address2D(int(res.x), addr);
}

ivec2 bufferAddress2D(sampler2D buff, int addr)
{
    return address2D(textureSize(buff, 0).x, addr);
}

int bodyStartAddress() 
{ 
    return pixel_count_of_Globals; 
}

int bodyAddress(int b_id)
{
    return bodyStartAddress() + pixel_count_of_Body * b_id;
}

int jointStartAddress(Globals g) 
{ 
    return bodyStartAddress() + g.n_body * pixel_count_of_Body; 
}

int jointAddress(Globals g, int j_id)
{
    return jointStartAddress(g) + pixel_count_of_Joint * j_id;
}

int contactStartAddress(Globals g)
{
    return jointStartAddress(g) + g.n_joint * pixel_count_of_Joint;
}

int contactAddress(Globals g, int c_id)
{
    return contactStartAddress(g) + pixel_count_of_Contact * c_id;
}

int nContact(Globals g)
{
    return g.n_body * (g.n_body - 1); // one contact foreach pair of body
}

int jointMax() // linear space in memory
{ 
    return 1000; 
}

int bodyMax(ivec2 res) //  quadratic space in memory because of contacts
{
    float c = float(pixel_count_of_Globals+pixel_count_of_Joint*jointMax()-res.x*res.y);
    float sb = float(pixel_count_of_Body);
    float sc = float(pixel_count_of_Contact);
    float sbc = sb - sc;
    return int((sqrt(sbc*sbc-4.*sc*c)-(sbc))/(2.*sc));
}

Globals loadGlobals(sampler2D buff)
{
    Globals g;
    vec4 data0 = texelFetch(buff, bufferAddress2D(buff, 0), 0);
    vec4 data1 = texelFetch(buff, bufferAddress2D(buff, 1), 0);
    vec4 data2 = texelFetch(buff, bufferAddress2D(buff, 2), 0);
    g.res = ivec2(data0.xy);
    g.n_body = int(data0.z);
    g.n_joint = int(data0.w);
    g.time = data1.x;
    g.t_added = data1.y;
    g.n_funnel = int(data1.z);
    g.funnel_b_id = int(data1.w);
    g.mode = int(data2.x);
    return g;
}

void storeGlobals(int buff_w, Globals g, ivec2 fragCoord, inout vec4 fragColor)
{
    int fragAddr = address(buff_w, fragCoord);

    if(fragAddr == 0) fragColor = vec4(g.res, g.n_body, g.n_joint);
    if(fragAddr == 1) fragColor = vec4(g.time, g.t_added, g.n_funnel, g.funnel_b_id);
    if(fragAddr == 2) fragColor = vec4(g.mode, -1, -1, -1);
}

Body loadBody(sampler2D buff, ivec2 res, int b_id)
{
    Body b;
    
    int addr = bodyAddress(b_id);
    
    vec4 data0 = texelFetch(buff, address2D(res, addr), 0);
    vec4 data1 = texelFetch(buff, address2D(res, addr+1), 0);
    vec4 data2 = texelFetch(buff, address2D(res, addr+2), 0);
    
    b.pos = data0.xy;
    b.vel = data0.zw;
    
    b.ang = data1.x;
    b.ang_vel = data1.y;
    
    b.size = data1.zw;
    b.inv_mass = data2.x;
    b.inv_friction = data2.y;
    b.inv_i = data2.z;
    
    return b;
}

Body loadBody(sampler2D buff, int b_id)
{
    return loadBody(buff, textureSize(buff, 0), b_id);
}

void storeBody(int res_x, int b_id, Body b, ivec2 fragCoord, inout vec4 fragColor)
{
    int addr = bodyAddress(b_id);
    int fragAddr = address(res_x, fragCoord);
    
    if(fragAddr == addr) fragColor = vec4(b.pos, b.vel);
    if(fragAddr == addr + 1) fragColor = vec4(b.ang, b.ang_vel, b.size);
    if(fragAddr == addr + 2) fragColor = vec4(b.inv_mass, b.inv_friction, b.inv_i, -1);
}

float computeInvI(Body b)
{
    return 12. * b.inv_mass / dot2(b.size);
}

Joint loadJoint(sampler2D buff, Globals g, int j_id)
{
    Joint j;
    
    int addr = jointAddress(g, j_id);
    
    vec4 data0 = texelFetch(buff, address2D(g.res, addr), 0);
    vec4 data1 = texelFetch(buff, address2D(g.res, addr+1), 0);
    vec4 data2 = texelFetch(buff, address2D(g.res, addr+2), 0);
    vec4 data3 = texelFetch(buff, address2D(g.res, addr+3), 0);
    vec4 data4 = texelFetch(buff, address2D(g.res, addr+4), 0);
    
    j.b0_id = int(data0.x);
    j.b1_id = int(data0.y);
    j.loc_anc0 = data0.zw;
    j.loc_anc1 = data1.xy;
    j.bias_factor = data1.z;
    j.softness = data1.w;
    j.r0 = data2.xy;
    j.r1 = data2.zw;
    j.M = mat2(data3);
    j.bias = data4.xy;
    j.P = data4.zw;
    
    return j;
}

void storeJoint(int res_x, Globals g, int j_id, Joint j, ivec2 fragCoord, inout vec4 fragColor)
{
    int addr = jointAddress(g, j_id);
    int fragAddr = address(res_x, fragCoord);
    
    if(fragAddr == addr) fragColor = vec4(float(j.b0_id), float(j.b1_id), j.loc_anc0);
    if(fragAddr == addr + 1) fragColor = vec4(j.loc_anc1, j.bias_factor, j.softness);
    if(fragAddr == addr + 2) fragColor = vec4(j.r0, j.r1);
    if(fragAddr == addr + 3) fragColor = vec4(j.M);
    if(fragAddr == addr + 4) fragColor = vec4(j.bias, j.P);
}

Contact loadContact(sampler2D buff, Globals g, int c_id)
{
    Contact c;
    
    int addr = contactAddress(g, c_id);
    
    vec4 data0 = texelFetch(buff, address2D(g.res, addr), 0);
    vec4 data1 = texelFetch(buff, address2D(g.res, addr+1), 0);
    
    c.pos = data0.xy;
    c.normal = data0.zw;
    c.sep = data1.x;

    c.mass_n = data1.y;
    c.mass_t = data1.z;
    c.bias = data1.w;
    
    return c;
}

void storeContact(int res_x, Globals g, int c_id, Contact c, ivec2 fragCoord, inout vec4 fragColor)
{
    int addr = contactAddress(g, c_id);
    int fragAddr = address(res_x, fragCoord);
    
    if(fragAddr == addr) fragColor = vec4(c.pos, c.normal);
    if(fragAddr == addr + 1) fragColor = vec4(c.sep, c.mass_n, c.mass_t, c.bias);
}

#define INVALID_VALUE -10000.
void setInvalidContact(inout Contact c)
{
    c.pos.x = INVALID_VALUE;
}

bool isContactValid(Contact c)
{
    return c.pos.x > INVALID_VALUE + 1.;
}

// overload so we don't have to sample the entire contact
bool isContactValid(sampler2D buff, Globals g, int c_id)
{
    int addr = contactAddress(g, c_id);
    float posx = texelFetch(buff, address2D(g.res, addr), 0).x;
    return posx > INVALID_VALUE + 1.;
}

void getContactBodyIds(int c_id, out int b0_id, out int b1_id)
{
    c_id = c_id / 2; // 2 contacts per pair
    
    int i = int((1.+sqrt(1.+8.*float(c_id)))/2.);
    int j = c_id - (i*(i-1))/2;
    
    b0_id = min(i, j);
    b1_id = max(i, j);
}

int getContactId(int b0_id, int b1_id)
{
    if(b0_id < b1_id) return b0_id +(b1_id*(b1_id-1))/2;
    return b1_id +(b0_id*(b0_id-1))/2;
}

void applyContactImpulse(inout Body b0, inout Body b1, inout Contact c)
{
    vec2 r0 = c.pos - b0.pos;
    vec2 r1 = c.pos - b1.pos;

    vec2 dv = b1.vel + cross2(b1.ang_vel, r1) - b0.vel - cross2(b0.ang_vel, r0);
    float v_n = dot(dv, c.normal);
    float dp_n = c.mass_n * (-v_n + c.bias); 
    dp_n = max(0., dp_n); 

    vec2 p_n = dp_n * c.normal;

    // Normal impulse
    b0.vel -= b0.inv_mass * p_n;
    b0.ang_vel -= b0.inv_i * cross2(r0, p_n); 

    b1.vel += b1.inv_mass * p_n;
    b1.ang_vel += b1.inv_i * cross2(r1, p_n); 

    dv = b1.vel + cross2(b1.ang_vel, r1) - b0.vel - cross2(b0.ang_vel, r0);
    vec2 tangent = cross2(c.normal, 1.);
    float v_t = dot(dv, tangent);
    float dp_t = c.mass_t * (-v_t);
    float friction = sqrt(b0.inv_friction * b1.inv_friction);
    float max_friction = abs(friction * dp_n);
    dp_t = clamp(dp_t, -max_friction, max_friction);

    vec2 p_t = dp_t * tangent;

    // Tangent impulse
    b0.vel -= b0.inv_mass * p_t;
    b0.ang_vel -= b0.inv_i * cross2(r0, p_t); 

    b1.vel += b1.inv_mass * p_t;
    b1.ang_vel += b1.inv_i * cross2(r1, p_t);
}

vec2 computeJointImpulse(Body b0, Body b1, Joint j)
{
    vec2 dv = b1.vel + cross2(b1.ang_vel, j.r1) - b0.vel - cross2(b0.ang_vel, j.r0);
    vec2 impulse = j.M * (j.bias - dv - j.softness * j.P);
    return impulse;
}

void applyJointImpulse(inout Body b0, inout Body b1, inout Joint j)
{
    vec2 impulse = computeJointImpulse(b0, b1, j);
    
    b0.vel -= b0.inv_mass * impulse;
    b0.ang_vel -= b0.inv_i * cross2(j.r0, impulse);

    b1.vel += b1.inv_mass * impulse;
    b1.ang_vel += b1.inv_i * cross2(j.r1, impulse);

    j.P += impulse;
}

bool isInvisibleBody(int b_id)
{
    return (b_id >= 67 && b_id <= 69);
}

void initGlobals(ivec2 res, inout Globals g)
{
    g.res = res;
    g.n_body = FACTORY_FIXED_BODIES + FACTORY_MOVING_BODIES;
    g.n_joint = FACTORY_JOINTS;
    g.time = 0.;
    g.t_added = -1.;
    g.n_funnel = 0;
    g.funnel_b_id = -1;
    g.mode = 2;
}

// Applying the impulses from contacts and joints
// Theoretically, the more iterations the better, here we have 3, each in buffer B/C/D
// Reference code uses 10 iterations and is single threaded, so each iteration uses updated bodies velocities
// Here we can only use the velocities from previous iteration, and that's why stacking is not possible (i think)
// Using accumulated impulses (as in reference) and multiple frames to reach ~12 iterations did not help
void physicsIteration(out vec4 fragColor, vec2 fragCoord, vec2 iResolution, sampler2D prev_buff)
{
    fragColor = vec4(-1);
    
    Globals g = loadGlobals(prev_buff);

    int res_x = int(iResolution.x);
    int id = address(res_x, ivec2(fragCoord));
    int g_id = id / pixel_count_of_Globals;
    int b_id = (id - bodyStartAddress()) / pixel_count_of_Body;
    int j_id = (id - jointStartAddress(g)) / pixel_count_of_Joint;
    int c_id = (id - contactStartAddress(g)) / pixel_count_of_Contact;
    if(g_id == 0) // Globals
    {
        // Copy
        fragColor = texelFetch(prev_buff, ivec2(fragCoord), 0);
    }
    else if(b_id >= 0 && b_id < g.n_body) // Body
    {
        // Load
        Body b = loadBody(prev_buff, b_id);

        // Apply contact impulses
        // Iterate contacts pointing to this body
        for(int i = 0; i < g.n_body; i++) //
        {
            if(i == b_id) continue;
            Body b_i = loadBody(prev_buff, i);

            int c_id = getContactId(b_id, i);
            for(int j = 0; j < 2; j++)
            {
                int c_ij_id = 2 * c_id + j;

                if(!isContactValid(prev_buff, g, c_ij_id)) continue;
                Contact c = loadContact(prev_buff, g, c_ij_id);

                if(b_id > i)
                {
                    applyContactImpulse(b_i, b, c);
                }
                else
                {
                    applyContactImpulse(b, b_i, c);
                }
            }        
        }
       
        // Apply joint impulses
        // Iterate every joint pointing to this body
        for(int joint_id = 0; joint_id < g.n_joint; joint_id++)
        {
            Joint j = loadJoint(prev_buff, g, joint_id);
            if(j.b0_id == b_id)
            {
                Body b1 = loadBody(prev_buff, j.b1_id);
                applyJointImpulse(b, b1, j);
            }
            else if(j.b1_id == b_id)
            {
                Body b0 = loadBody(prev_buff, j.b0_id);
                applyJointImpulse(b0, b, j);
            }
        }
       
        // Store
        storeBody(res_x, b_id, b, ivec2(fragCoord), fragColor);
    }
    else if(j_id >= 0 && j_id < g.n_joint) // Joint
    {
        // Load 
        Joint j = loadJoint(prev_buff, g, j_id);
        
        // Accumulate impulse
        Body b0 = loadBody(prev_buff, j.b0_id);
        Body b1 = loadBody(prev_buff, j.b1_id);
        applyJointImpulse(b0, b1, j);
        
        // Store
        storeJoint(res_x, g, j_id, j, ivec2(fragCoord), fragColor);
    }
    else if(c_id >= 0 && c_id < nContact(g)) // Contact
    {
        // Copy
        fragColor = texelFetch(prev_buff, ivec2(fragCoord), 0);
    }
}
