class LogoWindTunnelLevel extends Level {
  public void reset() {}
  public void update(float dt, float t, AudioEnvelope audio) {}
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 14);
    pg.translate(pg.width/2, pg.height/2);
    
    pg.stroke(120, 200, 255, 180);
    pg.noFill();
    int rings = 16;
    for (int i=0; i<rings; i++) {
      float r = 80 + i*18 + sin(time*1.2f + i)*6;
      pg.ellipse(0, 0, r*2, r*2*0.75f);
    }
    
    pg.textAlign(CENTER, CENTER);
    pg.textSize(96);
    pg.fill(255, 180);
    pg.pushMatrix();
    pg.shearX(sin(time*0.5f)*0.2f);
    pg.shearY(cos(time*0.4f)*0.2f);
    pg.text("SYN", -120, -20);
    pg.text("VJ", 120, 60);
    pg.popMatrix();
    
    pg.popStyle();
  }
  
  public String getName() { return "Logo Wind Tunnel"; }
}
