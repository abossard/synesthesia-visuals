class JellyBlobsLevel extends Level {
  class Blob {
    PVector p = new PVector();
    PVector v = new PVector();
    float r;
    float seed;
  }
  ArrayList<Blob> blobs = new ArrayList<Blob>();
  
  public void reset() {
    blobs.clear();
    for (int i = 0; i < 6; i++) {
      Blob b = new Blob();
      b.p.set(random(-200, 200), random(-150, 150), random(-80, 80));
      b.r = random(40, 90);
      b.seed = random(1000);
      blobs.add(b);
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    for (Blob b : blobs) {
      PVector attract = PVector.mult(b.p, -0.35f);
      b.v.add(PVector.mult(attract, dt));
      b.v.add(new PVector(noise(b.seed + t)*2-1, noise(b.seed+50+t)*2-1, noise(b.seed+100+t)*2-1));
      b.v.mult(0.9f);
      b.p.add(PVector.mult(b.v, dt*40));
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(10, 8, 18);
    pg.translate(pg.width/2, pg.height/2);
    pg.blendMode(ADD);
    pg.noStroke();
    for (int i = 0; i < blobs.size(); i++) {
      Blob b = blobs.get(i);
      pg.pushMatrix();
      pg.translate(b.p.x, b.p.y, b.p.z);
      int c = color(120 + i*30, 180 + i*12, 255, 90);
      pg.fill(c);
      pg.ellipse(0, 0, b.r*2, b.r*2);
      pg.popMatrix();
    }
    pg.blendMode(BLEND);
    pg.popStyle();
  }
  
  public String getName() { return "Jelly Blobs"; }
}
