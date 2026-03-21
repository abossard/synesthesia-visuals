/*
{
  "IMPORTED" : [

  ],
  "CATEGORIES" : [
    "raymarching",
    "cube",
    "4d",
    "rotating",
    "tesseract",
    "hypercube",
    "Automatically Converted"
  ],
  "DESCRIPTION" : "Automatically converted from https:\/\/www.shadertoy.com\/view\/MldXW7 by Vortex_.  A 4D Cube rendered as a  \"3D shadow\". \n\nUsing 4D matrices to rotate the Tesseract in the 4th dimension.\n\nPlease come with suggestions if I have done something utterly wrong. :)",
  "INPUTS" : [
    {
        "NAME": "rotX",
        "TYPE": "float",
        "DEFAULT": 0
    },
    {
        "NAME": "rotZ",
        "TYPE": "float",
        "DEFAULT": 0
    },
    {
        "NAME": "rotXX",
        "TYPE": "float",
        "DEFAULT": 0
    },
    {
        "NAME": "rotYY",
        "TYPE": "float",
        "DEFAULT": 0
    },
    {
        "NAME": "rotZZ",
        "TYPE": "float",
        "DEFAULT": 0
    }
  ]
}
*/


/*//////////////////////////
Creator: Andreas Sorman 
aka. "Vortex"



*///////////////////////////

float PI = 3.14159265359;
float eps = .0001;


//Models
float udBox( vec3 p, vec3 b )
{
  return length(max(abs(p)-b,0.0));
}

float udBox4D( vec4 p, vec4 b)
{
  return length(max(abs(p)-b,0.0));
}

float sdSphere( vec3 p, float s )
{
  return length(p)-s;
}

float sdBox( vec3 p, vec3 b )
{
  vec3 d = abs(p) - b;
  return min(max(d.x,max(d.y,d.z)),0.0) + length(max(d,0.0));
}

float sdBox4D( vec4 p, vec4 b )
{
  vec4 d = abs(p) - b;
  return min(max(d.x ,max(d.y,max(d.z,d.w))),0.0) + length(max(d,0.0));
}

mat4 rotateX(float _theta) {
    float theta = _theta * PI;
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(1, 0, 0, 0),
        vec4(0, 1, 0, 0),
        vec4(0, 0, c, -s),
        vec4(0, 0, s, c)
    );
}

mat4 rotateY(float _theta) {
    float theta = _theta * PI;
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(1, 0, 0, 0),
        vec4(0, c, 0, -s),
        vec4(0, 0, 1, 0),
        vec4(0, s, 0, c)
    );
}

mat4 rotateZ(float _theta) {
    float theta = _theta * PI;
    float c = cos(theta);
    float s = sin(theta);

    return mat4(
        vec4(c, 0, 0, s),
        vec4(0, 1, 0, 0),
        vec4(0, 0, 1, 0),
        vec4(-s, 0, 0, c)
    );
}


mat3 rotateX3D(float _theta) {
    float theta = _theta * PI;
    float c = cos(theta);
    float s = sin(theta);
    
    return mat3(
        vec3(1, 0, 0),
        vec3(0, c, -s),
        vec3(0, s, c)
    );
}

mat3 rotateY3D(float _theta) {
    float theta = _theta * PI;
    float c = cos(theta);
    float s = sin(theta);
    
    return mat3(
        vec3(c, 0, s),
        vec3(0, 1, 0),
        vec3(-s, 0, c)
    );
}

mat3 rotateZ3D(float _theta) {
    float theta = _theta * PI;
    float c = cos(theta);
    float s = sin(theta);
    
    return mat3(
        vec3(c, -s, 0),
        vec3(s, c, 0),
        vec3(0, 0, 1)
    );
}


float opS( float d1, float d2 )
{
    return max(-d1, d2);
}

//Scene Where You Can Place Objects
float scene(vec3 pos) { 
    
    float time = TIME;
    
    float d = sdBox4D(vec4(pos*rotateZ3D(rotZZ)*rotateY3D(rotYY)*rotateX3D(rotXX),0)*rotateZ(rotZ)*rotateY(rotZ)*rotateX(rotX), vec4(.6));
    
    d = opS(sdBox4D(vec4(pos*rotateZ3D(rotZZ)*rotateY3D(rotYY)*rotateX3D(rotXX),0)*rotateZ(rotZ)*rotateY(rotZ)*rotateX(rotX), vec4(1., .5, .5, .5)), d);
    d = opS(sdBox4D(vec4(pos*rotateZ3D(rotZZ)*rotateY3D(rotYY)*rotateX3D(rotXX),0)*rotateZ(rotZ)*rotateY(rotZ)*rotateX(rotX), vec4(.5, 1., .5, .5)), d);
    d = opS(sdBox4D(vec4(pos*rotateZ3D(rotZZ)*rotateY3D(rotYY)*rotateX3D(rotXX),0)*rotateZ(rotZ)*rotateY(rotZ)*rotateX(rotX), vec4(.5, .5, 1., .5)), d);
    d = opS(sdBox4D(vec4(pos*rotateZ3D(rotZZ)*rotateY3D(rotYY)*rotateX3D(rotXX),0)*rotateZ(rotZ)*rotateY(rotZ)*rotateX(rotX), vec4(.5, .5, .5, 1.)), d);         
    
    return d;
}

//Get Normal
vec3 normal(vec3 pos) {
    float eps = 0.001;
    
    return normalize(vec3(
    scene(pos + vec3(eps,0.,0.)) - scene(pos - vec3(eps,0.,0.)),
    scene(pos + vec3(0.,eps,0.)) - scene(pos - vec3(0.,eps,0.)),
    scene(pos + vec3(0.,0.,eps)) - scene(pos - vec3(0.,0.,eps))));
}

//Marching Until It Hits Something
vec3 march(vec3 pos, vec3 dir) {    
    vec3 rayPos = pos;    
    float dis = eps;
    
    vec3 c = vec3(rayPos);  
    
    for(int i = 0; i < 50; i++) {                         
       	c = rayPos;
      
        if(dis < eps) {
            c = normal(rayPos);
            
            break;
        }
                    
        dis = scene(rayPos); 
        rayPos += dir*dis;                                                         
    }
    
    if (dis > 10000.) { // Background condition
        c = vec3(0.0, 0.0, 0.0); // Black background
    }
        
    return c;
}

//Renders The Final Image
void main()
{

    //UV Setup
    vec2 uv = -1.0 + 2.0 * (gl_FragCoord.xy / RENDERSIZE.xy);
    uv.y *= -1.;
    uv.x *= 1.7777;
   
    vec3 pos = vec3(0., 1., -2.);
    vec3 target = vec3(0.);
    
    //Setting Up Camera Vector
    vec3 ww = normalize(target - pos);
    vec3 uu = normalize(cross(vec3(0, 1, 0), ww));
    vec3 vv = normalize(cross(ww, uu));
    vec3 dir = normalize(uv.x*uu + uv.y*vv + ww);         
    
    vec3 c = normalize(abs(march(pos, dir)));    
    
    gl_FragColor = vec4(c, 1.);
}