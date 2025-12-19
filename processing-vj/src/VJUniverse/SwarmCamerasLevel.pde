class SwarmCamerasLevel extends Level {
  public void reset() {}
  public void update(float dt, float t, AudioEnvelope audio) {}
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 10, 16);
    int cams = 4;
    float w = pg.width/2;
    float h = pg.height/2;
    for (int i=0; i<cams; i++) {
      float cx = (i%2)*w;
      float cy = (i/2)*h;
      pg.pushMatrix();
      pg.translate(cx + w/2, cy + h/2);
      pg.fill(20, 24, 40);
      pg.rectMode(CENTER);
      pg.rect(0, 0, w, h);
      drawSwarm(pg, i);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public void drawSwarm(PGraphics pg, int idx) {
    pg.pushMatrix();
    pg.rotate(sin(time*0.3f + idx)*0.4f);
    pg.stroke(140 + idx*30, 220, 255, 180);
    pg.noFill();
    pg.ellipse(0, 0, 180, 120);
    int agents = 30;
    for (int i=0; i<agents; i++) {
      float a = time*0.6f + i*0.2f + idx;
      float r = 20 + (i%5)*12;
      pg.fill(200, 255, 255, 120);
      pg.noStroke();
      pg.ellipse(cos(a)*r, sin(a*1.2f)*r, 6, 6);
    }
    pg.popMatrix();
  }
  
  public String getName() { return "Swarm Cameras"; }
}
