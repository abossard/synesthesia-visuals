class BreathingPlanetLevel extends Level {
  float tOffset = random(1000);
  float baseRadius = 180;
  int detailLat = 28;
  int detailLon = 38;
  
  public void reset() {
    tOffset = random(1000);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    tOffset += dt * 0.35f;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 10, 18);
    pg.camera();  // Reset camera to default
    pg.lights();
    pg.ambientLight(40, 40, 60);
    pg.directionalLight(180, 160, 255, -0.4f, -0.6f, -1);
    pg.directionalLight(120, 200, 180, 0.6f, 0.4f, 0.5f);
    
    pg.pushMatrix();
    pg.translate(pg.width/2, pg.height/2, -80);
    pg.rotateY(time * 0.4f);
    pg.rotateX(time * 0.2f);
    
    float bass = audio.getBass();
    float mid = audio.getMid();
    float high = audio.getHigh();
    float dispAmt = 40 + bass * 80;
    float noiseScale = 0.8f + mid * 1.2f;
    float hueShift = high * 0.6f;
    
    pg.noStroke();
    for (int i = 0; i < detailLat; i++) {
      float theta1 = map(i, 0, detailLat, -HALF_PI, HALF_PI);
      float theta2 = map(i+1, 0, detailLat, -HALF_PI, HALF_PI);
      pg.beginShape(TRIANGLE_STRIP);
      for (int j = 0; j <= detailLon; j++) {
        float phi = map(j, 0, detailLon, -PI, PI);
        addPlanetVertex(pg, theta1, phi, dispAmt, noiseScale, hueShift);
        addPlanetVertex(pg, theta2, phi, dispAmt, noiseScale, hueShift);
      }
      pg.endShape();
    }
    
    pg.popMatrix();
    pg.popStyle();
  }
  
  void addPlanetVertex(PGraphics pg, float theta, float phi, float disp, float scale, float hueShift) {
    float nx = cos(theta) * cos(phi);
    float ny = sin(theta);
    float nz = cos(theta) * sin(phi);
    float n = noise(nx * scale + tOffset, ny * scale + 30 + tOffset, nz * scale + 60 + tOffset);
    float r = baseRadius + n * disp;
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color((0.6f + hueShift + n * 0.2f) % 1.0f, 0.7f, 0.9f, 1);
    pg.popStyle();
    pg.fill(c);
    pg.normal(nx, ny, nz);
    pg.vertex(nx * r, ny * r, nz * r);
  }
  
  public String getName() { return "Breathing Planet"; }
}

