class ToroidalFlowLevel extends Level {
  class FlowParticle {
    PVector p = new PVector();
    PVector v = new PVector();
  }
  ArrayList<FlowParticle> pts = new ArrayList<FlowParticle>();
  float majorR = 220;
  float minorR = 70;
  
  public void reset() {
    pts.clear();
    for (int i = 0; i < 350; i++) {
      FlowParticle fp = new FlowParticle();
      float u = random(TWO_PI);
      float v = random(TWO_PI);
      fp.p = torusToCartesian(u, v);
      fp.v = PVector.random3D();
      pts.add(fp);
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    float flowSpeed = 90 + audio.getMid() * 160;
    for (FlowParticle fp : pts) {
      // convert to torus params
      float u = atan2(fp.p.y, fp.p.x);
      float v = atan2(fp.p.z, sqrt(fp.p.x*fp.p.x + fp.p.y*fp.p.y) - majorR);
      // flow tangent along torus
      PVector tangentU = new PVector(-sin(u), cos(u), 0);
      PVector tangentV = new PVector(cos(u)*-sin(v), sin(u)*-sin(v), cos(v));
      PVector flow = PVector.add(tangentU, tangentV);
      flow.normalize();
      flow.mult(flowSpeed * dt);
      fp.p.add(flow);
      // slight noise drift
      fp.p.add((noise(fp.p.x*0.005f, fp.p.y*0.005f, t*0.2f)-0.5f)*8,
               (noise(fp.p.y*0.005f, fp.p.z*0.005f, t*0.2f+10)-0.5f)*8,
               (noise(fp.p.z*0.005f, fp.p.x*0.005f, t*0.2f+20)-0.5f)*8);
      // clamp radius toward torus surface
      float magXY = sqrt(fp.p.x*fp.p.x + fp.p.y*fp.p.y);
      float distMinor = sqrt(pow(magXY - majorR,2) + fp.p.z*fp.p.z);
      float corr = (distMinor - minorR) * 0.05f;
      PVector corrVec = new PVector(fp.p.x, fp.p.y, fp.p.z);
      corrVec.normalize();
      corrVec.mult(corr);
      fp.p.sub(corrVec);
    }
  }
  
  PVector torusToCartesian(float u, float v) {
    float x = (majorR + minorR * cos(v)) * cos(u);
    float y = (majorR + minorR * cos(v)) * sin(u);
    float z = minorR * sin(v);
    return new PVector(x, y, z);
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 14);
    pg.translate(pg.width/2, pg.height/2, -120);
    pg.rotateY(time * 0.3f);
    pg.rotateX(sin(time * 0.2f) * 0.2f);
    pg.blendMode(ADD);
    pg.stroke(120, 220, 255, 180);
    pg.strokeWeight(2);
    pg.beginShape(POINTS);
    for (FlowParticle fp : pts) {
      pg.vertex(fp.p.x, fp.p.y, fp.p.z);
    }
    pg.endShape();
    pg.blendMode(BLEND);
    pg.popStyle();
  }
  
  public String getName() { return "Toroidal Flow"; }
}

