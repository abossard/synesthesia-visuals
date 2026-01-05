class RecursiveCityLevel extends Level {
  public void reset() {}
  
  public void update(float dt, float t, AudioEnvelope audio) {}
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(10, 10, 18);
    pg.lights();
    pg.translate(pg.width/2, pg.height*0.65f, -300);
    pg.rotateY(sin(time * 0.2f) * 0.7f);
    pg.rotateX(-0.9f);
    int layers = 14;
    for (int i = 0; i < layers; i++) {
      float z = -i * 80;
      float scale = 1.0f + i * 0.1f;
      pg.pushMatrix();
      pg.translate(0, 0, z);
      pg.scale(scale);
      drawCityBlock(pg, i);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public void drawCityBlock(PGraphics pg, int idx) {
    pg.pushMatrix();
    float size = 140;
    pg.stroke(40, 60, 90, 180);
    pg.fill(50 + idx*10, 80 + idx*8, 120 + idx*6, 120);
    int towers = 12;
    for (int i = 0; i < towers; i++) {
      pg.pushMatrix();
      float angle = TWO_PI * i / towers;
      float r = size + sin(idx*0.3f + i)*20;
      pg.translate(cos(angle)*r, -60, sin(angle)*r);
      float h = 80 + (sin(i + idx*0.4f)+1)*50;
      pg.box(30, h, 30);
      pg.popMatrix();
    }
    pg.popMatrix();
  }
  
  public String getName() { return "Recursive City"; }
}
