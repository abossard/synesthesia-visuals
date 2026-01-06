class TimeSmearLevel extends Level {
  PGraphics buffer;
  
  public void reset() {
    buffer = createGraphics(width, height, P3D);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    if (buffer == null) return;
    buffer.beginDraw();
    buffer.resetMatrix();
    buffer.noStroke();
    buffer.fill(0, 0, 0, 30);
    buffer.rect(0, 0, buffer.width, buffer.height);
    buffer.fill(200, 180, 255, 180);
    float r = 80 + sin(t)*40;
    buffer.translate(buffer.width/2, buffer.height/2);
    buffer.rotate(t*0.3f);
    buffer.ellipse(0, 0, r*2, r*1.2f);
    buffer.endDraw();
  }
  
  public void render(PGraphics pg) {
    if (buffer != null) {
      pg.image(buffer, 0, 0);
    }
  }
  
  public String getName() { return "Time Smear"; }
}
