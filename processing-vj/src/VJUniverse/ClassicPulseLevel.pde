class ClassicPulseLevel extends Level {
  public void reset() {}
  
  public void update(float dt, float t, AudioEnvelope audio) {}
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.camera();  // Reset camera to default
    pg.colorMode(RGB, 255);
    float t = millis() / 1000.0f;
    
    // Background gradient
    pg.noStroke();
    for (int y = 0; y < pg.height; y += 2) {
      float l = map(y, 0, pg.height, 0, 1);
      int c = lerpColor(color(8, 10, 20), color(20, 22, 40), l);
      pg.fill(c);
      pg.rect(0, y, pg.width, 2);
    }
    
    pg.pushMatrix();
    pg.translate(pg.width / 2, pg.height / 2);
    
    float pulse = 0.5f + 0.5f * sin(t * TWO_PI * 0.4f);
    float pulse2 = 0.5f + 0.5f * sin(t * TWO_PI * 0.62f + PI / 3);
    
    // Rings
    pg.noFill();
    pg.strokeWeight(3);
    pg.stroke(255, 120, 150, 200);
    pg.ellipse(0, 0, 220 + 90 * pulse, 220 + 90 * pulse);
    pg.stroke(120, 255, 180, 200);
    pg.ellipse(0, 0, 320 + 60 * pulse2, 320 + 60 * pulse2);
    pg.stroke(120, 160, 255, 170);
    pg.ellipse(0, 0, 420 + 50 * pulse, 420 + 50 * pulse);
    
    // Rotating square
    pg.pushMatrix();
    pg.rotate(t * 0.6f);
    pg.stroke(255, 160);
    pg.strokeWeight(2);
    pg.noFill();
    pg.rectMode(CENTER);
    pg.rect(0, 0, 280, 280);
    pg.popMatrix();
    
    pg.popMatrix();
    pg.popStyle();
  }
  
  public String getName() {
    return "Classic Pulse";
  }
}
