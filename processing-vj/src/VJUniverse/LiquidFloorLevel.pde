class LiquidFloorLevel extends Level {
  public void reset() {}
  public void update(float dt, float t, AudioEnvelope audio) {}
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 8, 14);
    pg.lights();
    pg.translate(pg.width/2, pg.height*0.6f, -200);
    pg.rotateX(PI/3);
    pg.stroke(120, 180, 255, 180);
    pg.noFill();
    int grid = 28;
    float spacing = 24;
    for (int z = -grid; z < grid; z++) {
      pg.beginShape();
      for (int x = -grid; x <= grid; x++) {
        float y = sin((x+time*2)*0.4f) * 14 + cos((z+time*2)*0.4f) * 14;
        pg.vertex(x*spacing, y, z*spacing);
      }
      pg.endShape();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Liquid Floor"; }
}
