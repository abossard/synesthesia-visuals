class KaleidoscopeGeometryLevel extends Level {
  int folds = 6;
  
  public void reset() {}
  
  public void update(float dt, float t, AudioEnvelope audio) {
    folds = 4 + (int)(audio.getBass()*6);
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 8, 14);
    pg.translate(pg.width/2, pg.height/2);
    pg.noStroke();
    for (int i=0;i<folds;i++) {
      pg.pushMatrix();
      pg.rotate(i * TWO_PI / folds + time*0.3f);
      drawBase(pg);
      pg.scale(-1,1);
      drawBase(pg);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  void drawBase(PGraphics pg) {
    pg.pushMatrix();
    pg.fill(120 + sin(time)*80, 200, 255, 180);
    pg.rotate(time*0.5f);
    pg.beginShape();
    pg.vertex(0, -120);
    pg.vertex(60, 60);
    pg.vertex(-60, 60);
    pg.endShape(CLOSE);
    pg.popMatrix();
  }
  
  public String getName() { return "Kaleidoscope Geometry"; }
}

