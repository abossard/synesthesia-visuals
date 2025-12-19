class SpectrumBars3DLevel extends Level {
  int bands = 48;
  float[] values = new float[bands];
  
  public void reset() {
    for (int i = 0; i < bands; i++) values[i] = 0;
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    float lvl = audio.getLevel();
    for (int i=0;i<bands;i++) {
      float target = lvl * (0.5f + noise(i*0.1f, t*0.5f));
      values[i] = lerp(values[i], target, 0.4f);
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 8, 14);
    pg.lights();
    pg.translate(pg.width/2, pg.height/2, -200);
    pg.rotateY(time*0.4f);
    
    float radius = 280;
    for (int i=0;i<bands;i++) {
      float a = TWO_PI * i / bands;
      float h = 40 + values[i]*260;
      float x = cos(a)*radius;
      float z = sin(a)*radius;
      pg.pushMatrix();
      pg.translate(x, h*-0.5f, z);
      pg.rotateY(-a + HALF_PI);
      pg.fill(120 + i*3, 200, 255, 220);
      pg.box(12, h, 30);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Spectrum Bars 3D"; }
}

