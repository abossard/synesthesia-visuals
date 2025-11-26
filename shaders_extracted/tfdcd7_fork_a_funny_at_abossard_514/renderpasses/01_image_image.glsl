float sdfCircle(vec2 pos,vec2 uv, float size){
    return length(pos - uv) - size;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    
    vec2 uv = fragCoord/iResolution.xy;
    uv.x *= iResolution.x/iResolution.y;

    vec3 col = vec3(0);
    
    float r1 = 0.06;
    float r2 = 0.1;
    float r3 = 0.04;
    float r4 = 0.03;
    
    vec2 pos1 = vec2(1.2,0.6);
    vec2 pos2 = vec2(0.3,0.6);
    vec2 pos3 = vec2(0.8,0.3);
    vec2 pos4 = vec2(0.9,0.5);
    
    pos1 += vec2(sin(iTime)*0.1,cos(iTime)*0.1);
    pos2 += vec2(sin(iTime)*-0.3,cos(iTime)*0.3);
    pos3 += vec2(sin(iTime)*0.2,cos(iTime)*0.1);
    pos3 += 0.0;
    
    
    if(sdfCircle(pos1,uv,r1)>0.0 && sdfCircle(pos2,uv,r2)>0.0 && sdfCircle(pos3,uv,r3)>0.0&& sdfCircle(pos4,uv,r4)>0.0)
    {
        
        
        vec2 p = uv;
        vec2 v = vec2(0);
        float dt = 0.01;
        for(int i=0;i<10000;i++){
            vec2 dir1 = normalize(pos1-p) ;
            vec2 dir2 = normalize(pos2-p);
            vec2 dir3 = normalize(pos3-p);
            vec2 dir4 = normalize(pos4-p);
            
            float dist1 =max(length(p-pos1),0.001) ;
            float dist2 = max(length(p-pos2),0.001);
            float dist3 = max(length(p-pos3),0.001);
            float dist4 = max(length(p-pos4),0.001);
            
            float force1 = r1/(dist1*dist1);
            float force2 = r2/(dist2*dist2);
            float force3 = r3/(dist3*dist3);
            float force4 = r4/(dist4*dist4);
            
            
            vec2 acc = dir1 * force1 + dir2 * force2 + dir3 * force3+ dir4 * force4;
            v += acc * dt;
            p += v * dt;
        
            if(sdfCircle(pos1,p,r1)<0.0){
                col = vec3(pos1,1);
                break;
            }
        
            if(sdfCircle(pos2,p,r2)<0.0){
                col = vec3(1,pos2);
                break;
            }
        
            if(sdfCircle(pos3,p,r3)<0.0){
                col = vec3(pos3,1);
                break;
            }
            if(sdfCircle(pos4,p,r4)<0.0){
                col = vec3(1,pos4);
                break;
            }
            
        }
    }
    
    

    
    fragColor = vec4(col,1.0);
}
