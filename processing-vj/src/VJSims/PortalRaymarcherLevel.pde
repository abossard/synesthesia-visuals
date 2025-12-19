class PortalRaymarcherLevel extends Level {
  public void reset() {}
  public void update(float dt, float t, AudioEnvelope audio) {}
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.noStroke();
    pg.background(4, 6, 12);
    pg.translate(pg.width/2, pg.height/2);
    int rings = 28;
    for (int i=0; i<rings; i++) {
      float tNorm = (float)i / rings;
      float r = 40 + i*18 + sin(time*0.8f + i*0.2f)*10;
      float alpha = 180 - tNorm*180;
      int c = pg.color(120 + tNorm*100, 180 + tNorm*50, 255, alpha);
      pg.fill(c);
      float wobble = sin(time*1.2f + i)*8;
      pg.ellipse(wobble, wobble*0.6f, r*2, r*2*0.8f);
    }
    pg.popStyle();
  }
  
  public String getName() { return "Portal Raymarcher"; }
}
