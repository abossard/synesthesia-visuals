class TentacleRibbonLevel extends Level {
  class Tentacle {
    ArrayList<PVector> points = new ArrayList<PVector>();
    float seed;
  }
  ArrayList<Tentacle> tentacles = new ArrayList<Tentacle>();
  int segs = 22;
  
  public void reset() {
    tentacles.clear();
    for (int i=0;i<6;i++) {
      Tentacle t = new Tentacle();
      t.seed = random(1000);
      for (int s=0;s<segs;s++) t.points.add(new PVector(0,0,0));
      tentacles.add(t);
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    for (Tentacle tc : tentacles) {
      PVector target = new PVector(
        sin(time*0.8f + tc.seed)*180,
        cos(time*0.6f + tc.seed*0.4f)*140,
        sin(time*0.5f + tc.seed*0.2f)*120
      );
      for (int i=0;i<tc.points.size();i++) {
        PVector p = tc.points.get(i);
        float f = 1 - (float)i / (tc.points.size()-1);
        PVector desired = PVector.lerp(target, new PVector(), f*0.8f);
        PVector noiseOffset = new PVector(
          (noise(tc.seed + time*0.4f + i*0.05f)-0.5f)*50,
          (noise(tc.seed + 20 + time*0.5f + i*0.04f)-0.5f)*50,
          (noise(tc.seed + 40 + time*0.3f + i*0.03f)-0.5f)*50
        );
        desired.add(noiseOffset);
        p.lerp(desired, 0.2f);
      }
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 14);
    pg.translate(pg.width/2, pg.height/2, -120);
    pg.rotateY(time*0.3f);
    pg.blendMode(ADD);
    pg.noFill();
    pg.strokeWeight(3);
    for (Tentacle tc : tentacles) {
      pg.stroke(120 + tc.seed%80, 200, 255, 160);
      pg.beginShape();
      for (PVector p : tc.points) {
        pg.curveVertex(p.x, p.y, p.z);
      }
      pg.endShape();
    }
    pg.blendMode(BLEND);
    pg.popStyle();
  }
  
  public String getName() { return "Tentacle Ribbons"; }
}

