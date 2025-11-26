// Physics Integration (and scene initialization)

int clipSegmentToLine(vec2 p0, vec2 p1, vec2 normal, float offset,
 inout vec2 out_p0, inout vec2 out_p1)
{
    int out_n = 0;
    
    // Distance to plane
    float dist0 = dot(normal, p0) - offset;
    float dist1 = dot(normal, p1) - offset;
    
    // If points are behind the plane
    if(dist0 <= 0.) { out_n += 1; out_p0 = p0;  }
    if(dist1 <= 0.) { out_n += 1; if(out_n == 1) out_p0 = p1; else out_p1 = p1; }
    
    // If points are on different sides of the plane
    if(dist0 * dist1 < 0.)
    {
        out_n += 1;
        vec2 p = mix(p0, p1, dist0 / (dist0 - dist1)); 
        if(out_n == 1) out_p0 = p; else out_p1 = p;
    }
    
    return out_n;
}

void computeIncidentEdge(vec2 h, vec2 pos, mat2 rot, mat2 rot_t, vec2 normal, 
 inout vec2 clip_p0, inout vec2 clip_p1)
{
    vec2 n = -(rot_t * normal);
    vec2 nAbs = abs(n);
    if(nAbs.x > nAbs.y)
    {
        float s = 2.*step(0., n.x)-1.;
        clip_p0 = vec2(s, -s) * h;
        clip_p1 = s * h;
    }
    else
    {
        float s = 2.*step(0., n.y)-1.;
        clip_p0 = s * h;
        clip_p1 = vec2(-s, s) * h;
    }
    
    clip_p0 = pos + rot * clip_p0; 
    clip_p1 = pos + rot * clip_p1; 
}

void trySeparatingAxis(float face, float h, int axis, vec2 sc, float d,
 inout int sep_axis, inout float sep, inout vec2 normal) 
{
    const float tol_rel = .95;
    const float tol_abs = .1;
    
    if(face > tol_rel * sep + tol_abs * h)
    {
        sep_axis = axis;
        sep = face;
        normal = d > 0. ? sc : -sc;
    }
}

bool ignoreCollision(int b0_id, int b1_id) // This assumes b0_id < b1_id
{
    if(isInvisibleBody(b1_id)) return true; // only check b1_id since invisible bodies are highest hand-placed ids
    return false;
}

void collide(int c_id, int b0_id, Body b0, int b1_id, Body b1, inout Contact c)
{
    setInvalidContact(c);

    if(b0.inv_mass == 0. && b1.inv_mass == 0.) return;
    if(ignoreCollision(b0_id, b1_id)) return; 

    // Setup
    vec2 h0 = b0.size;
    vec2 h1 = b1.size;
    
    mat2 rot0 = rot(b0.ang);
    mat2 rot1 = rot(b1.ang);
    
    mat2 rot0_t = transpose(rot0); // rot(-b0.ang)
    mat2 rot1_t = transpose(rot1);

    vec2 dp = b1.pos - b0.pos;
    vec2 d0 = rot0_t * dp;
    vec2 d1 = rot1_t * dp;

    mat2 m = m_abs(rot0_t * rot1); 
    mat2 m_t = transpose(m);

    vec2 face0 = abs(d0) - m * h1 - h0;
    if(face0.x > 0. || face0.y > 0.) return;
    
    vec2 face1 = abs(d1) - m_t * h0 - h1;
    if(face1.x > 0. || face1.y > 0.) return;
    
    // Find separating axis
    int sep_axis = 0;
    float sep = face0.x;
    vec2 normal = d0.x > 0. ? rot0[0] : -rot0[0];
    
    trySeparatingAxis(face0.y, h0.y, 1, rot0[1], d0.y, sep_axis, sep, normal);
    trySeparatingAxis(face1.x, h1.x, 2, rot1[0], d1.x, sep_axis, sep, normal);
    trySeparatingAxis(face1.y, h1.y, 3, rot1[1], d1.y, sep_axis, sep, normal);
    
    vec2 ref_normal = vec2(-1);
    float ref_side = -1.;
    vec2 clip_normal = vec2(-1);
    vec2 clip_sides = vec2(-1);
    vec2 clip_p0 = vec2(-1);
    vec2 clip_p1 = vec2(-1);
    
    // Setup clipping plane
    if(sep_axis == 0)
    {
        ref_normal = normal;
        ref_side = dot(b0.pos, ref_normal) + h0.x;
        clip_normal = rot0[1];
        float clip_side = dot(b0.pos, clip_normal);
        clip_sides = vec2(-clip_side, clip_side) + h0.y;
        computeIncidentEdge(h1, b1.pos, rot1, rot1_t, ref_normal, clip_p0, clip_p1);
    }
    else if(sep_axis == 1)
    {
        ref_normal = normal;
        ref_side = dot(b0.pos, ref_normal) + h0.y;
        clip_normal = rot0[0];
        float clip_side = dot(b0.pos, clip_normal);
        clip_sides = vec2(-clip_side, clip_side) + h0.x;
        computeIncidentEdge(h1, b1.pos, rot1, rot1_t, ref_normal, clip_p0, clip_p1);
    }
    else if(sep_axis == 2)
    {
        ref_normal = -normal;
        ref_side = dot(b1.pos, ref_normal) + h1.x;
        clip_normal = rot1[1];
        float clip_side = dot(b1.pos, clip_normal);
        clip_sides = vec2(-clip_side, clip_side) + h1.y;
        computeIncidentEdge(h0, b0.pos, rot0, rot0_t, ref_normal, clip_p0, clip_p1);
    }
    else
    {
        ref_normal = -normal;
        ref_side = dot(b1.pos, ref_normal) + h1.y;
        clip_normal = rot1[0];
        float clip_side = dot(b1.pos, clip_normal);
        clip_sides = vec2(-clip_side, clip_side) + h1.x;
        computeIncidentEdge(h0, b0.pos, rot0, rot0_t, ref_normal, clip_p0, clip_p1);
    }
    
    // Clip
    vec2 clip1_p0 = vec2(-1);
    vec2 clip1_p1 = vec2(-1);
    vec2 clip2_p0 = vec2(-1);
    vec2 clip2_p1 = vec2(-1);
    
    int np = clipSegmentToLine(clip_p0, clip_p1, -clip_normal, clip_sides.x, clip1_p0, clip1_p1);
    if(np < 2) return;
    
    np = clipSegmentToLine(clip1_p0, clip1_p1, clip_normal, clip_sides.y, clip2_p0, clip2_p1);
    if(np < 2) return;

    // Fill contact
    vec2 c_p = (c_id % 2 == 0) ? clip2_p0 : clip2_p1;
    float c_sep = dot(ref_normal, c_p) - ref_side;
    if(c_sep <= 0.)
    {
        c.pos = c_p - c_sep * ref_normal;
        c.normal = normal;
        c.sep = c_sep;        
    }
}

// Compute some values for the contact, maybe it's not worth losing 3 floats in the buffer if you want more bodies
void preStepContact(float dt, Body b0, Body b1, inout Contact c)
{
    // because values are still from the previous frame we should integrated values (i don't see much difference)
    
    vec2 r0 = c.pos - (b0.pos + dt * b0.vel);
    vec2 r1 = c.pos - (b1.pos + dt * b1.vel);
    
    float rn0 = dot(r0, c.normal);
    float rn1 = dot(r1, c.normal);
    
    float k_normal = b0.inv_mass + b1.inv_mass + b0.inv_i * (dot2(r0) - rn0*rn0) + b1.inv_i * (dot2(r1) - rn1*rn1); 
    c.mass_n = 1. / k_normal;
    
    vec2 tangent = cross2(c.normal, 1.);
    float rt0 = dot(r0, tangent);
    float rt1 = dot(r1, tangent);
    float k_tangent = b0.inv_mass + b1.inv_mass + b0.inv_i * (dot2(r0) - rt0*rt0) + b1.inv_i * (dot2(r1) - rt1*rt1); 
    c.mass_t = 1. / k_tangent;
    
    c.bias = -K_BIAS_FACTOR * (1. / dt) * min(0., c.sep + ALLOWED_PENETRATION);
}

void preStepJoint(Body b0, Body b1, float dt, inout Joint j)
{
    mat2 rot0 = rot(b0.ang);
    mat2 rot1 = rot(b1.ang);
    j.r0 = rot0 * j.loc_anc0;
    j.r1 = rot1 * j.loc_anc1;

    mat2 k1 = (b0.inv_mass + b1.inv_mass) * mat2(1, 0, 0, 1);
    mat2 k2 = b0.inv_i * mat2(j.r0.y * j.r0.y, -j.r0.x * j.r0.y, - j.r0.x * j.r0.y, j.r0.x * j.r0.x);
    mat2 k3 = b1.inv_i * mat2(j.r1.y * j.r1.y, -j.r1.x * j.r1.y, - j.r1.x * j.r1.y, j.r1.x * j.r1.x);
    
    mat2 k = k1 + k2 + k3 + mat2(j.softness, 0, 0, j.softness);
    j.M = inverse(k);
    
    vec2 p0 = b0.pos + j.r0;
    vec2 p1 = b1.pos + j.r1;
    vec2 dp = p1 - p0;
    j.bias = -j.bias_factor * (1. / dt) * dp; 
    
    j.P = vec2(0);
}

void addBody(inout Body b)
{
    vec3 rnd = hash31(uint(iFrame+int(iMouse.x)));
    b.pos = VIEW(iMouse);
    b.ang = rnd.z;
    b.vel = 3.*vec2(rnd.x-.5, rnd.y);
    b.size = BOX_SIZE;
    b.inv_mass = rcp(BOX_MASS);
    b.inv_friction = rcp(BOX_FRICTION);
    b.inv_i = computeInvI(b);
}

vec2 getForce(Globals g, int b_id, Body b)
{
    vec2 m_force = vec2(0.0);
    if(iMouse.z > 0.5 && g.mode <= 1) 
    {
        vec2 m = VIEW(iMouse.xy);
        vec2 dir = ( b.pos - m);
        m_force = -sign(float(g.mode)-.5) * .05 * dir / (dot2(dir)); // repulsive or attractive force
    }

    if(b_id == 21) m_force = 15.*vec2(sin(2.*g.time), 0.); // spring
    if(b_id == 26) m_force = fract(g.time * .1) > .5 ? vec2(7,0) : vec2(0); // pinch
    if(b_id == 27) m_force = fract(g.time * .1) > .5 ? vec2(-7,0) : vec2(0); // pinch

    if(b.inv_mass > 0.)  return b.inv_mass * m_force + GRAVITY;
    return vec2(0);
   
}

float getTorque(Globals g, int b_id, Body b)
{
    float torque = 0.;
    if(b_id >= 8 && b_id <= 9 && b.ang_vel < 2.) torque = 2.;
    if(b_id >= 10 && b_id <= 16 && b.ang_vel < 7.) torque = 7.;
    if(b_id == 23 && b.ang_vel < 2.) torque = 2.;
    if(b_id == 25 && b.ang_vel > -3.) torque = -2.;
    if(b_id >= 30 && b_id <= 36 && b.ang_vel > -7.) torque = -7.;
    if(b_id >= 42 && b_id <= 43 && b.ang_vel < 2.) torque = 2.;
    if(b_id >= 57 && b_id <= 62 && b.ang_vel > -5.) torque = -5.;
    
    if(b.inv_i == 0.) return torque;
    return torque * b.inv_i;
}

void jointAnimation(Globals g, int j_id, inout Joint j)
{
    // Pinch
    if(j_id == 11 || j_id == 12) j.softness = mix(20., .5, smoothsquare(g.time * .1, .1)); // vertical
    if(j_id == 13 || j_id == 14) j.softness = mix(10., .5, smoothsquare(g.time * .1 + .1, .1)); // pinching

    // Bottom-right spring
    if(j_id >= 17 && j_id <= 20) j.softness = fract(g.time * .1 + .1) < .9 ? 50. : .2; 
}

// Add some fun setting up a scene to showcase the capabilities of the system (slowing compilation though)
void initBody(Globals g, int b_id, inout Body b)
{
    b = Body(vec2(0), vec2(0), 0., 0., vec2(0), 0., 0., 0.);

    // Factory
    vec2 p = vec2(0);
    b.inv_friction = 0.1;
    if(b_id <= 3) // Four walls 0 - 3
    { 
        if      (b_id == 0) { b.pos = vec2(0,-2.15); b.size = vec2(1.8,1); }
        else if (b_id == 1) { b.pos = vec2(0,2.1); b.size = vec2(3,1); }
        else if (b_id == 2) { b.pos = vec2(-3,0); b.size = vec2(1,2); }
        else                { b.pos = vec2(3,0); b.size = vec2(1,2); }
    }
    else if (b_id <= 7) // Funnel 4 - 7
    {
        p = vec2(-1.5, .5);
        if      (b_id == 4) { b.pos = p+vec2(.3,0); b.size = vec2(.4,.02); b.ang = PI*.3; }
        else if (b_id == 5) { b.pos = p+vec2(-.3,0); b.size = vec2(.4,.02); b.ang = -PI*.3; }
        else if (b_id == 6) { b.pos = p+vec2(-.075,-.37); b.size = vec2(.02,.06); }
        else                { b.pos = p+vec2(.075,-.37); b.size = vec2(.02,.06); }
    }
    else if (b_id <= 9) // Top Mill 8 - 9
    {
        b.pos = vec2(-1.5, .5);
        b.size = (b_id == 9) ? vec2(.2,.02) : vec2(.02,.2);
    }
    else if (b_id <= 16) // Up treadmill 10 - 16
    {
        b.pos = vec2(-.8, .8) + float(b_id-10) * vec2(.2, -.1);
        b.ang = (b_id % 2 == 0) ? 0. : PI*.25;
        b.size = vec2(.04,.1);
    }
    else if (b_id <= 21) // Spring 17 - 21
    {
        b.pos = vec2(-2.02, -.82) + vec2(float(b_id-17) *.15, 0);
        b.size = (b_id == 21) ? vec2(.06,.1) : vec2(.02,.1);
        b.inv_mass = (b_id == 17) ? 0. : rcp(10.);
    }
    else if (b_id <= 24) // Flipper 22 - 24
    {
        p = vec2(-2., -.82);
        if      (b_id == 22) { b.pos = p+vec2(1.75,-.16); b.ang = -.05; b.size = vec2(.45,.04); b.inv_mass = rcp(20.); }
        else if (b_id == 23) { b.pos = p+vec2(2.3,-.2); b.ang = 1.; b.size = vec2(.2, .02); }
        else                 { b.pos = p+vec2(.2,-.5); b.size = vec2(1.1,.4); }// Bottom Edge
    }
    else if (b_id <= 29) // Pinch 25 - 29
    {
        p = vec2(1.,.2);
        if      (b_id == 25) { b.pos = p+vec2(0,.5); b.size = vec2(.27, 0.03); }
        else if (b_id == 26) { b.pos = p+vec2(.175,.2); b.ang = PI*.25; b.size = vec2(.2, .03); }
        else if (b_id == 27) { b.pos = p+vec2(-.175,.2); b.ang = -PI*.25; b.size = vec2(.2, .03); }
        else if (b_id == 28) { b.pos = p+vec2(-.34,.5); b.size = vec2(.06, .03); }
        else                 { b.pos = p+vec2(.34,.5); b.size = vec2(.06, .03); }
        b.inv_mass = b_id <= 27 ? rcp(10.) : rcp(1.);
    }
    else if (b_id <= 36) // Top treadmill 30 - 36
    {
        b.pos = vec2(-.8, 1.1) + vec2(float(b_id-30)*.2, 0);
        b.ang = (b_id % 2 == 0) ? 0. : PI*.25;
        b.size = vec2(.04,.1);
    }
    else if (b_id <= 41) // Bottom basin 37 - 41
    {
        p = vec2(1.,-.8);
        if      (b_id == 37) { b.pos = p; b.size = vec2(.14,.04); }
        else if (b_id == 38) { b.pos = p+vec2(-.26, .16); b.ang = PI*.25; b.size = vec2(.04,.16); }
        else if (b_id == 39) { b.pos = p+vec2(.26, .16); b.ang = -PI*.25; b.size = vec2(.04,.16); }
        else if (b_id == 40) { b.pos = p+vec2(-.44, -.1); b.size = vec2(.04,.4); }
        else                 { b.pos = p+vec2(.545, .05); b.size = vec2(.16,.25); }
        b.inv_mass = (b_id <= 39) ? rcp(.5) : 0.;
    }
    else if (b_id <= 43) // Center Mill 42 - 43
    {
        b.pos = vec2(0., -.2);
        b.size = (b_id == 42) ? vec2(.4,.02) : vec2(.02,.4);
    }
    else if (b_id <= 46) // Right spring 44 - 46
    {
        p = vec2(1.9, -1.28);
        b.pos = p + vec2(0, float(b_id-44)*.3);
        b.size = vec2(.09,.03);
        b.inv_mass = (b_id == 44) ? 0. : rcp(40.);
    }
    else if (b_id <= 47) // Right trapdoor 47
    {
        b.pos = vec2(1.5,.92); b.size = vec2(.025,.09); b.inv_mass = rcp(.05);
    }
    else if (b_id <= 56) // Right pipe 48 - 56
    {
        if      (b_id == 48) { b.pos = vec2(1.65,-.15); b.size = vec2(.16,.85); }
        else if (b_id == 49) { b.pos = vec2(2.48,1.13); b.ang = .4; b.size = vec2(.6,.6); }
        else if (b_id == 50) { b.pos = vec2(3.29,1.37); b.ang = .8; b.size = vec2(.6,.4); }
        else if (b_id == 51) { b.pos = vec2(2.,1.54); b.ang = 1.2; b.size = vec2(.6,.8); }
        else if (b_id == 52) { b.pos = vec2(1.69,1.11); b.size = vec2(.2,.1); }
        else if (b_id == 53) { b.pos = vec2(1.7,.69); b.ang = .52; b.size = vec2(.1,.05); }
        else if (b_id == 54) { b.pos = vec2(1.68,.71); b.ang = 1.04; b.size = vec2(.1,.05); }
        else if (b_id == 55) { b.pos = vec2(1.59,.74); b.size = vec2(.1,.08); }
        else                 { b.pos = vec2(1.9,-1.45); b.size = vec2(.4,.2); }
        b.inv_friction = .001;
    }
    else if (b_id <= 62) // Down treadmill 57 - 62
    {
        b.pos = vec2(.7, -1.2) + vec2(float(b_id-57)*.2,0);
        b.ang = (b_id % 2 == 0) ? PI*.25 : 0.;
        b.size = vec2(.04,.1);
    }
    else if (b_id <= 66) // Down ramps 63 - 66
    {
        p = vec2(-1.5, -.15);
        if      (b_id == 63) { b.pos = p; b.ang = -PI*.05; b.size = vec2(.6,.02); }
        else if (b_id == 64) { b.pos = p+vec2(.6,-.3); b.ang = PI*.05; b.size = vec2(.4,.02); }
        else if (b_id == 65) { b.pos = p+vec2(1.,.15); b.size = vec2(.02,.4); }
        else                 { b.pos = p+vec2(-.2,-.5); b.ang = -PI*.05; b.size = vec2(.3,.02); }
        b.inv_friction = .001;
    }
    else if (b_id <= 69) // Invisible boxes 67 - 69 (to prevent boxes from being stuck)
    {
        if      (b_id == 67) { b.pos = vec2(-1.75,-.82); b.ang = -PI*.05; b.size = vec2(.32,.16); }
        else if (b_id == 68) { b.pos = vec2(-.36,-1.18); b.ang = -PI*.1; b.size = vec2(.42,.12); }
        else                 { b.pos = vec2(1.9,-1.25); b.size = vec2(.12,.1); }
        b.inv_friction = .1;
    }
    else // Dynamic Boxes 70+
    {
        vec3 rnd = hash31(uint(b_id+INIT_SEED));
        b.pos = vec2(3., 1.5)*(rnd.xy-vec2(.6,.4));
        b.ang = rnd.z;
        b.size = BOX_SIZE;
        b.inv_mass = rcp(BOX_MASS);
        b.inv_friction = rcp(BOX_FRICTION);
    }     

    b.inv_i = computeInvI(b); 
}

// Some helpers for initializing joint (the anchor position is most of the time dependant on bodies positions)
void initJoint(int b0_id, int b1_id, vec2 loc_anc0, vec2 loc_anc1, inout Joint j)
{
    if (b0_id <= b1_id)
    {
        j.b0_id = b0_id; j.loc_anc0 = loc_anc0;
        j.b1_id = b1_id; j.loc_anc1 = loc_anc1;
    }
    else 
    {
        j.b0_id = b1_id; j.loc_anc0 = loc_anc1;
        j.b1_id = b0_id; j.loc_anc1 = loc_anc0;
    }
}

void initJoint(Globals g, int b0_id, int b1_id, vec2 anchor, inout Joint j)
{
    Body b0; initBody(g, b0_id, b0);
    Body b1; initBody(g, b1_id, b1);
   
    vec2 loc_anc0 = transpose(rot(b0.ang)) * (anchor - b0.pos);
    vec2 loc_anc1 = transpose(rot(b1.ang)) * (anchor - b1.pos);    
    
    initJoint(b0_id, b1_id, loc_anc0, loc_anc1, j);
}

void initJoint_Mid(Globals g, int b0_id, int b1_id, vec2 offset, inout Joint j)
{
    Body b0; initBody(g, min(b0_id, b1_id), b0);
    Body b1; initBody(g, max(b0_id, b1_id), b1);
   
    vec2 anchor = (b0.pos + b1.pos) * .5 + offset;
    vec2 loc_anc0 = transpose(rot(b0.ang)) * (anchor - b0.pos);
    vec2 loc_anc1 = transpose(rot(b1.ang)) * (anchor - b1.pos);    
    
    initJoint(b0_id, b1_id, loc_anc0, loc_anc1, j);
}

void initJoint_Mid(Globals g, int b0_id, int b1_id, inout Joint j)
{
    initJoint_Mid(g, b0_id, b1_id, vec2(0), j);
}

void initJoint_Second(Globals g, int b0_id, int b1_id, vec2 offset, inout Joint j)
{
    Body b0; initBody(g, b0_id, b0);
    Body b1; initBody(g, b1_id, b1);
   
    vec2 anchor = b1.pos + offset;
    vec2 loc_anc0 = transpose(rot(b0.ang)) * (anchor - b0.pos);
    vec2 loc_anc1 = transpose(rot(b1.ang)) * (anchor - b1.pos);    
    
    initJoint(b0_id, b1_id, loc_anc0, loc_anc1, j);
}

void initJoint_Second(Globals g, int b0_id, int b1_id, inout Joint j)
{
    initJoint_Second(g, b0_id, b1_id, vec2(0), j);
}

void initJoint(Globals g, int j_id, inout Joint j)
{
    j = Joint(-1, -1, vec2(0), vec2(0), 0., 0., vec2(0), vec2(0), mat2(0), vec2(0), vec2(0));
    if(j_id <= 7) // Spring 0 - 7
    {
        if      (j_id == 0) initJoint_Mid(g, 17, 18, vec2(0,.1), j);
        else if (j_id == 1) initJoint_Mid(g, 17, 18, vec2(0,-.1), j);
        else if (j_id == 2) initJoint_Mid(g, 18, 19, vec2(0,.1), j);
        else if (j_id == 3) initJoint_Mid(g, 18, 19, vec2(0,-.1), j);
        else if (j_id == 4) initJoint_Mid(g, 19, 20, vec2(0,.1), j);
        else if (j_id == 5) initJoint_Mid(g, 19, 20, vec2(0,-.1), j);
        else if (j_id == 6) initJoint_Mid(g, 20, 21, vec2(0,.1), j);
        else                initJoint_Mid(g, 20, 21, vec2(0,-.1), j);
        j.softness = 10.; 
        j.bias_factor = .5;
    }
    else if (j_id <= 9) // Flipper 8 - 9
    {
        if (j_id == 8) { initJoint_Second(g, 24, 22, vec2(-.4,.04), j); j.softness = .01; }
        else           { initJoint_Second(g, 0, 22, vec2(0,-.2), j); j.softness = 3.; }
        j.bias_factor = .5;
    }
    else if (j_id <= 16) // Pinch 10 - 16
    {
        if      (j_id == 10) initJoint_Second(g, 1, 25, j);
        else if (j_id == 11) initJoint_Second(g, 26, 25, j);
        else if (j_id == 12) initJoint_Second(g, 27, 25, j);
        else if (j_id == 13) initJoint_Mid(g, 26, 27, vec2(0,.1), j);
        else if (j_id == 14) initJoint_Mid(g, 26, 27, vec2(0,-.1), j);
        else if (j_id == 15) initJoint_Second(g, 25, 28, vec2(.04,0), j);
        else                 initJoint_Second(g, 25, 29, vec2(-.04,0), j);
        j.bias_factor = .02;
        j.softness = 0.; // will be overriden by JointAnimation
    }
    else if (j_id <= 20) // Bottom-right Spring 17 - 20
    {
        if      (j_id == 17) initJoint_Mid(g, 44, 45, vec2(-.1, 0), j);
        else if (j_id == 18) initJoint_Mid(g, 44, 45, vec2(.1, 0), j);
        else if (j_id == 19) initJoint_Mid(g, 45, 46, vec2(-.1, 0), j);
        else                 initJoint_Mid(g, 45, 46, vec2(.1, 0), j);
        j.bias_factor = .2;
        j.softness = 10.; // will be overriden by JointAnimation
    }
    else if (j_id <= 21) // Top-right trapdoor 21
    {
        initJoint_Second(g, 52, 47, vec2(0,.1), j);
        j.softness = 0.; j.bias_factor = .075;
    }
    else if (j_id <= 29) // Bottom Bassin 22 - 29
    {
        if      (j_id == 22) initJoint_Second(g, 0, 37, vec2(.15, -.35), j);
        else if (j_id == 23) initJoint_Second(g, 0, 37, vec2(-.15, -.35), j);
        else if (j_id == 24) initJoint_Second(g, 0, 38, vec2(.15, -.5), j);
        else if (j_id == 25) initJoint_Second(g, 0, 38, vec2(-.15, -.5), j);
        else if (j_id == 26) initJoint_Second(g, 0, 39, vec2(.15, -.5), j);
        else if (j_id == 27) initJoint_Second(g, 0, 39, vec2(-.15, -.5), j);
        else if (j_id == 28) initJoint_Mid(g, 37, 38, j);
        else                 initJoint_Mid(g, 37, 39, j);
        j.softness = 20.; j.bias_factor = .1;
    }
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    fragColor = vec4(-1);
 
    Globals g_prev = loadGlobals(iChannel0);

    bool is_first_frame = (iFrame == 0);
    if(is_first_frame) initGlobals(ivec2(iResolution), g_prev);

    int res_x = int(iResolution.x);
    bool is_buffer_smaller = (g_prev.res.x > res_x) || (g_prev.res.y > int(iResolution.y)); 
    bool is_init = is_first_frame || is_buffer_smaller;
    bool is_body_added = !is_init 
     && (MOUSE_DOWN)
     && (g_prev.mode == 2)
     && (g_prev.n_body < bodyMax(ivec2(iResolution))) 
     && (g_prev.t_added + SPAWN_COOLDOWN < g_prev.time);

    Globals g_next = g_prev;
    if(is_init) initGlobals(ivec2(iResolution), g_next);
    g_next.res = ivec2(iResolution);
    if(is_body_added) 
    {
        g_next.n_body += 1;
        g_next.t_added = g_prev.time;
    }

    int id = address(res_x, ivec2(fragCoord));
    int g_id = id / pixel_count_of_Globals;
    int b_id = (id - bodyStartAddress()) / pixel_count_of_Body;
    int j_id = (id - jointStartAddress(g_next)) / pixel_count_of_Joint;
    int c_id = (id - contactStartAddress(g_next)) / pixel_count_of_Contact;
    float dt = rcp(60.); // factory calibrated with 60 fps, using iTimeDelta is more correct 

    if(g_id == 0) // Globals
    {
        g_next.time += dt;
        
        // Factory example specific : update funnel counter and b_id 
        vec2 funnel_p = vec2(-1.5, .07);
        Body funnel_b = loadBody(iChannel0, g_prev.funnel_b_id);
        if(g_prev.funnel_b_id >= 0 && funnel_b.pos.y < funnel_p.y) g_next.n_funnel = g_prev.n_funnel + 1;
        g_next.funnel_b_id = -1;
        float funnel_d = FLT_MAX;
        for(int i = 70; i < g_prev.n_body; i++) 
        {
            Body b_i = loadBody(iChannel0, i);
            if(b_i.pos.y < funnel_p.y) continue;
            float b_d = dot2(b_i.pos - funnel_p);
            if(b_d > .1) continue;
            if(g_next.funnel_b_id < 0 || b_d < funnel_d)
            {
                g_next.funnel_b_id = i;
                funnel_d = b_d;
            }
        }
        
        // Factory example specific : select mode
        if(MOUSE_DOWN)
        {
            vec2 m = VIEW(iMouse);
            if(length(m-vec2(-1.7, 1.3)) < .15) g_next.mode = 0; 
            if(length(m-vec2(-1.4, 1.3)) < .15) g_next.mode = 1; 
            if(length(m-vec2(-1.1, 1.3)) < .15) g_next.mode = 2; 
        }
        
        // Store
        storeGlobals(res_x, g_next, ivec2(fragCoord), fragColor);
    }
    else if(b_id >= 0 && b_id < g_next.n_body) // Body
    {
        // Load
        Body b = loadBody(iChannel0, g_prev.res, b_id);
        if(is_init) initBody(g_next, b_id, b);
        if(b_id >= g_prev.n_body) addBody(b);

        // Limit velocities
        if(length(b.vel) > MAX_VELOCITY) b.vel /= length(b.vel) * MAX_VELOCITY;
        if(abs(b.ang_vel) > MAX_ANG_VELOCITY) b.ang_vel = clamp(b.ang_vel, -MAX_ANG_VELOCITY, MAX_ANG_VELOCITY);   

        // Integrate velocities 
        b.pos += b.vel * dt;
        b.ang += b.ang_vel * dt;

        // Integrate forces
        b.vel += getForce(g_next, b_id, b) * dt;
        b.ang_vel += getTorque(g_next, b_id, b) * dt;

        // Store
        storeBody(res_x, b_id, b, ivec2(fragCoord), fragColor);
    }
    else if(j_id >= 0 && j_id < g_next.n_joint) // Joint
    {
        // Load
        Joint j = loadJoint(iChannel0, g_prev, j_id);
        if(is_init) initJoint(g_next, j_id, j);
        jointAnimation(g_next, j_id, j);

        // Load associated bodies
        Body b0 = loadBody(iChannel0, g_prev.res, j.b0_id);
        if(is_init) initBody(g_next, j.b0_id, b0);
        if(j.b0_id >= g_prev.n_body) addBody(b0);

        Body b1 = loadBody(iChannel0, g_prev.res, j.b1_id);
        if(is_init) initBody(g_next, j.b1_id, b1);
        if(j.b1_id >= g_prev.n_body) addBody(b1);

        // Pre Step
        preStepJoint(b0, b1, dt, j);

        // Store
        storeJoint(res_x, g_next, j_id, j, ivec2(fragCoord), fragColor);
    }
    else if(c_id >= 0 && c_id < nContact(g_next)) // Contact
    {
        // Load
        Contact c = loadContact(iChannel0, g_prev, c_id);

        // Load associated bodies
        int b0_id = -1, b1_id = -1;
        getContactBodyIds(c_id, b0_id, b1_id);

        Body b0 = loadBody(iChannel0, g_prev.res, b0_id);
        if(is_init) initBody(g_next, b0_id, b0);
        if(b0_id >= g_prev.n_body) addBody(b0);

        Body b1 = loadBody(iChannel0, g_prev.res, b1_id);
        if(is_init) initBody(g_next, b1_id, b1);
        if(b1_id >= g_prev.n_body) addBody(b1);

        // Collide
        collide(c_id, b0_id, b0, b1_id, b1, c);

        // Pre Step
        preStepContact(dt, b0, b1, c);

        // Store
        storeContact(res_x, g_next, c_id, c, ivec2(fragCoord), fragColor);
    }
}
