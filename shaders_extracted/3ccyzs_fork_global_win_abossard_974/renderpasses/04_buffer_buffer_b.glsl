// 2018 David A Roberts <https://davidar.io>

// atmospheric pressure and circulation model

#define buf(uv) texture(iChannel1, uv)

#define SIGMA vec4(6,4,0,0)
vec4 normpdf(float x) {
	return 0.39894 * exp(-0.5 * x*x / (SIGMA*SIGMA)) / SIGMA;
}

// mean sea level pressure
vec4 mslp(vec2 uv) {
    float lat = 180. * (uv.y * iResolution.y / MAPRES.y) - 90.;
    float land = texture(iChannel0, uv).x;
    vec4 r;
    if (land > 0.) { // land
        r.x = 1012.5 - 6. * cos(lat*PI/45.); // annual mean
        r.y = 15. * sin(lat*PI/90.); // January/July delta
    } else { // ocean
        r.x = 1014.5 - 20. * cos(lat*PI/30.);
        r.y = 20. * sin(lat*PI/35.) * abs(lat)/90.;
    }
    return r;
}

// horizontally blurred MSLP
vec4 pass1(vec2 uv) {
    //if (iFrame > 10) return buf(uv + PASS1);
    vec4 r = vec4(0);
    for (float i = -20.; i <= 20.; i++)
        r += mslp(uv + i*E/iResolution.xy) * normpdf(i);
    return r;
}

// fully blurred MSLP
vec4 pass2(vec2 uv) {
    //if (iFrame > 10) return buf(uv + PASS2);
    vec4 r = vec4(0);
    for (float i = -20.; i <= 20.; i++)
        r += buf(uv + i*N/iResolution.xy + PASS1) * normpdf(i);
    return r;
}

// time-dependent MSLP
vec4 pass3(vec2 uv) {
    vec4 c = buf(uv + PASS2);
    float t = mod(iTime, 12.); // simulated month of the year
    float delta = c.y * (1. - 2. * smoothstep(1.5, 4.5, t) + 2. * smoothstep(7.5, 10.5, t));
    return vec4(c.x + delta,0,0,0);
}

// wind vector field
vec4 pass4(vec2 uv) {
    vec2 p = uv * iResolution.xy;
    float n = buf(mod(p + N, MAPRES)/iResolution.xy + PASS3).x;
    float e = buf(mod(p + E, MAPRES)/iResolution.xy + PASS3).x;
    float s = buf(mod(p + S, MAPRES)/iResolution.xy + PASS3).x;
    float w = buf(mod(p + W, MAPRES)/iResolution.xy + PASS3).x;
    vec2 grad = vec2(e - w, n - s) / 2.;
    float lat = 180. * fract(uv.y * iResolution.y / MAPRES.y) - 90.;
    vec2 coriolis = 15. * sin(lat*PI/180.) * vec2(-grad.y, grad.x);
    vec2 v = coriolis - grad;
    return vec4(v,0,0);
}

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
    vec2 uv = fragCoord / iResolution.xy;
    if (uv.x < 0.5) {
        if (uv.y < 0.5) {
    		fragColor = pass1(uv - PASS1);
        } else {
    		fragColor = pass2(uv - PASS2);
        }
    } else {
        if (uv.y < 0.5) {
    		fragColor = pass3(uv - PASS3);
        } else {
    		fragColor = pass4(uv - PASS4);
        }
    }
}
