class VolumetricFireLevel extends Level {
  class Ember {
    PVector p = new PVector();
    PVector v = new PVector();
    float life;
    float maxLife;
  }
  ArrayList<Ember> embers = new ArrayList<Ember>();
  
  public void reset() {
    embers.clear();
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    int emit = 20 + (int)(audio.getBass()*30);
    for (int i=0;i<emit;i++) {
      Ember e = new Ember();
      e.p.set(random(-20,20), 120, random(-20,20));
      e.v.set(random(-20,20), random(-180,-80), random(-20,20));
      e.maxLife = random(1.0f, 1.8f);
      e.life = e.maxLife;
      embers.add(e);
    }
    for (int i=embers.size()-1;i>=0;i--) {
      Ember e = embers.get(i);
      e.p.add(PVector.mult(e.v, dt));
      e.v.y -= 120*dt;
      e.v.x += (noise(e.p.x*0.05f, t*0.6f)-0.5f)*30*dt;
      e.v.z += (noise(e.p.z*0.05f, t*0.6f+20)-0.5f)*30*dt;
      e.life -= dt;
      if (e.life <= 0) embers.remove(i);
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 6, 10);
    pg.blendMode(ADD);
    pg.translate(pg.width/2, pg.height*0.9f, -120);
    for (Ember e : embers) {
      float a = map(e.life, 0, e.maxLife, 0, 255);
      pg.noStroke();
      pg.fill(255, 160, 80, a);
      pg.pushMatrix();
      pg.translate(e.p.x, -e.p.y, e.p.z);
      float s = 8 + (1 - e.life/e.maxLife)*16;
      pg.ellipse(0, 0, s, s);
      pg.popMatrix();
    }
    pg.blendMode(BLEND);
    pg.popStyle();
  }
  
  public String getName() { return "Volumetric Fire"; }
}

