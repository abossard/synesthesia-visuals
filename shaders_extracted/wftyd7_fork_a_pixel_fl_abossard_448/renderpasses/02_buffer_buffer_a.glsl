// BUFFER A

#define KEY_SPACE 32

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    ivec2 v = ivec2(floor(fragCoord));
    ivec2 c = ivec2(floor(iResolution.xy / 2.0));

    ivec2 m = ivec2(floor(iMouse.xy));
    m = (m-c)/SCALE+c;

    // PRESS SPACE TO RESTART
    bool restart = texelFetch(iChannel3, ivec2(KEY_SPACE,0), 0).x > 0.0;
    if(iFrame <= 0 || restart || any(lessThan(iChannelResolution[0].xy,vec2(1)))) // Apparently iChannelResolution is more reliable than textureSize: https://shadertoyunofficial.wordpress.com/2019/01/26/classical-corner-cases/
    //if(iTime <= 0.5 || restart) // in case it takes some frames for texture to load
    //if(iFrame <= 60 || restart) // in case it takes some frames for texture to load
    {
        fragColor = vec4(0,0,0,0);
        //fragColor = vec4(v == c);
        //fragColor = vec4((texelFetch(iChannel1, v, 0).x >= 0.5));
        //float f = texture(iChannel1, fragCoord/iResolution.xy).x;
        //float f = fbm(fragCoord, 0.5, 8); // use noise to avoid troubble with texture load
        //float f = noise(33.5*fragCoord/iResolution.xy-vec2(2,0)); // use noise to avoid troubble with texture load
        float f = noise(33.5*mat2(1,1,-1,1)*(fragCoord/iResolution.xy)-vec2(4,0)); // use noise to avoid troubble with texture load
        //if(sin(3.1415926*f*10.0) >= 0.0)
        //if(f < 0.75)
        //if(f < -0.0)
        if(f < -0.03)
        {
            fragColor = vec4(0,0,0,1);
        }
        else
        {
            /*
            if((v.x-c.x)*(v.x-c.x)+(v.y-c.y)*(v.y-c.y)<5*5)
            {
                // start with a blob of water
                //if((uhash(uvec2(p), 0u)&15u) == 0u)
                if(true)
                {
                    fragColor = encode(255);
                }
                else
                {
                    fragColor = encode(0);
                }
            }
            else
            */
            {
                fragColor = encode(1);
                //fragColor = encode(2);
                //fragColor = encode(5);
            }
        }
    }
    else
    {
        fragColor = hstep(iChannel0, v);
        if(iMouse.z > 0.0 && m == v)
        {
            // keep adding pressure at center
            fragColor = encode(255);
        }
    }
    /*
    //if(v == c)
    if((v.x-c.x)*(v.x-c.x)+(v.y-c.y)*(v.y-c.y)<5*5)
    {
        // keep adding pressure at center
        fragColor = encode(255);
    }
    */
}

