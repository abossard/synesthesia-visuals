class FloatingTerrainLevel extends Level {
  int cols = 48;
  int rows = 48;
  float noiseZ = 0;
  float camAngle = 0;
  float fogDensity = 0.0028f;
  int fogColor = color(12, 10, 18);
  
  public void reset() {
    noiseZ = random(1000);
    camAngle = 0;
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    noiseZ += dt * 0.25f;
    camAngle += dt * 0.15f;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 10, 18);
    pg.camera();  // Reset camera to default
    pg.lights();
    pg.ambientLight(50, 50, 60);
    pg.directionalLight(180, 200, 255, -0.4f, -0.5f, -1);
    pg.directionalLight(120, 130, 180, 0.6f, 0.4f, 0.5f);
    
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.5f + 40, -280);
    pg.rotateY(camAngle);
    pg.rotateX(PI / 3.0f);
    
    for (int z = 0; z < rows - 1; z++) {
      pg.beginShape(TRIANGLE_STRIP);
      for (int x = 0; x < cols; x++) {
        addTerrainVertex(pg, x, z);
        addTerrainVertex(pg, x, z + 1);
      }
      pg.endShape();
    }
    
    pg.popMatrix();
    
    // Fog overlay
    pg.noStroke();
    pg.fill(fogColor, 90);
    pg.rect(0, 0, pg.width, pg.height);
    pg.popStyle();
  }
  
  public void addTerrainVertex(PGraphics pg, int gx, int gz) {
    float nx = (float)gx / cols;
    float nz = (float)gz / rows;
    float h = noise(nx * 3.2f, nz * 3.2f, noiseZ) * 220 - 110;
    float x = (gx - cols / 2.0f) * 18;
    float z = (gz - rows / 2.0f) * 18;
    int c = terrainColor(pg, h);
    pg.fill(c);
    pg.stroke(30, 35, 60, 180);
    pg.vertex(x, h, z);
  }
  
  public int terrainColor(PGraphics pg, float h) {
    float t = constrain(map(h, -110, 140, 0, 1), 0, 1);
    pg.pushStyle();
    pg.colorMode(HSB, 1);
    int c = pg.color(0.58f - 0.05f * t, 0.55f + 0.2f * t, 0.5f + 0.4f * t, 1);
    pg.popStyle();
    return c;
  }
  
  public String getName() { return "Floating Terrain"; }
}
