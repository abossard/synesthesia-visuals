class TextEngineLevel extends Level {
  String[] words = {"SYNESTHESIA", "VJ", "FLOW", "LIGHT", "AUDIO", "OSC"};
  float z = 0;
  
  public void reset() {
    z = 0;
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    z -= dt * 200;
    if (z < -800) z = 400;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 8, 16);
    pg.textAlign(CENTER, CENTER);
    pg.translate(pg.width/2, pg.height/2, 0);
    for (int i=0; i<words.length; i++) {
      float depth = z + i*140;
      pg.pushMatrix();
      pg.translate(0, 0, depth);
      float s = map(depth, -800, 400, 16, 96);
      pg.fill(255, 200);
      pg.textSize(s);
      pg.text(words[i], 0, 0);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Text Engine"; }
}
