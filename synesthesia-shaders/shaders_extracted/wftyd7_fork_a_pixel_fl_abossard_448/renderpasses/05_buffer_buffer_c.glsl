// BUFFER C

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    ivec2 v = ivec2(floor(fragCoord));
    fragColor = sim(iChannel0, v, false); // even
}

