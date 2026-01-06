class VortexTunnelLevel extends Level {
  int rings = 32;
  float spacing = 40;
  float offset = 0;
  
  public void reset() { offset = 0; }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    offset += dt * (180 + audio.getLevel()*240);
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(4, 6, 12);
    pg.noFill();
    pg.translate(pg.width/2, pg.height/2, 0);
    pg.rotateZ(time*0.4f);
    pg.strokeWeight(3);
    for (int i=0;i<rings;i++) {
      float z = -i*spacing + (offset % spacing);
      float r = 120 + i*6 + sin(time*0.7f + i*0.3f)*12;
      int c = color(120 + i*4, 200, 255, 220 - i*4);
      pg.stroke(c);
      pg.pushMatrix();
      pg.translate(0,0,z);
      pg.rotateZ(i*0.1f + time*0.5f);
      pg.ellipse(0,0,r*2,r*1.2f);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Vortex Tunnel"; }
}

