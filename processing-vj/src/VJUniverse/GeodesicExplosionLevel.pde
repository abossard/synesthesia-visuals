class GeodesicExplosionLevel extends Level {
  class Face {
    PVector p;
    PVector v;
    int col;
    Face(PVector p, PVector v, int col){this.p=p;this.v=v;this.col=col;}
  }
  ArrayList<Face> faces = new ArrayList<Face>();
  float radius = 180;
  
  public void reset() {
    faces.clear();
    int steps = 12;
    for (int i=0;i<steps;i++){
      float theta = map(i,0,steps,-HALF_PI, HALF_PI);
      for (int j=0;j<steps*2;j++){
        float phi = map(j,0,steps*2,-PI, PI);
        PVector n = new PVector(cos(theta)*cos(phi), sin(theta), cos(theta)*sin(phi));
        PVector p = PVector.mult(n, radius);
        faces.add(new Face(p, new PVector(), color(120 + i*5, 200, 255, 200)));
      }
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    if (audio.getBass() > 0.8f) {
      // burst
      for (Face f : faces) {
        PVector dir = f.p.copy().normalize();
        dir.mult(160 + audio.getBass()*260);
        f.v.add(dir);
      }
    }
    for (Face f : faces) {
      f.v.mult(0.95f);
      f.p.add(PVector.mult(f.v, dt));
      // pull back to sphere
      PVector target = f.p.copy().normalize().mult(radius);
      f.p.lerp(target, 0.05f);
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 6, 12);
    pg.lights();
    pg.translate(pg.width/2, pg.height/2, -120);
    pg.rotateY(time*0.35f);
    pg.noStroke();
    for (Face f : faces) {
      pg.pushMatrix();
      pg.translate(f.p.x, f.p.y, f.p.z);
      pg.fill(f.col);
      pg.box(10, 14, 10);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Geodesic Explosion"; }
}

