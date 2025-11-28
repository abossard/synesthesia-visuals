// 2018 David A Roberts <https://davidar.io>

// wind flow map

vec2 getVelocity(vec2 uv) {
    vec2 p = uv * MAPRES;
    if (p.x < 1.) p.x = 1.;
    vec2 v = texture(iChannel1, p/iResolution.xy + vec2(0.5,0.5)).xy;
    if (length(v) > 1.) v = normalize(v);
    return v;
}

vec2 getPosition(vec2 fragCoord) {
    for(int i = -1; i <= 1; i++) {
        for(int j = -1; j <= 1; j++) {
            vec2 uv = (fragCoord + vec2(i,j)) / iResolution.xy;
            vec2 p = texture(iChannel0, fract(uv)).xy;
            if(p == vec2(0)) {
                if (hash13(vec3(fragCoord + vec2(i,j), iFrame)) > 1e-4) continue;
                p = fragCoord + vec2(i,j) + hash21(float(iFrame)) - 0.5; // add particle
            } else if (hash13(vec3(fragCoord + vec2(i,j), iFrame)) < 8e-3) {
                continue; // remove particle
            }
            vec2 v = getVelocity(uv);
            p = p + v;
            p.x = mod(p.x, iResolution.x);
            if(abs(p.x - fragCoord.x) < 0.5 && abs(p.y - fragCoord.y) < 0.5)
                return p;
        }
    }
    return vec2(0);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
    fragColor.xy = getPosition(fragCoord);
    fragColor.z = 0.9 * texture(iChannel0, fragCoord/iResolution.xy).z;
    if (fragColor.x > 0.) fragColor.z = 1.;
}
