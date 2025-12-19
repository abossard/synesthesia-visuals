class FFTMountainsLevel extends Level {
  int cols = 70;
  int rows = 40;
  float[][] heights = new float[cols][rows];
  
  public void reset() {
    for (int x=0;x<cols;x++) Arrays.fill(heights[x], 0);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    float bass = audio.getBass();
    float mid = audio.getMid();
    float high = audio.getHigh();
    for (int x=0; x<cols; x++) {
      float v = sin(t*0.6f + x*0.2f) * 0.2f + noise(x*0.05f, t*0.2f) * 0.8f;
      heights[x][0] = lerp(heights[x][0], (bass*0.8f + mid*0.6f + high*0.4f + v)*160, 0.5f);
    }
    // propagate backwards
    for (int z=rows-1; z>0; z--) {
      for (int x=0; x<cols; x++) {
        heights[x][z] = lerp(heights[x][z], heights[x][z-1]*0.92f, 0.4f);
      }
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 14);
    pg.lights();
    pg.translate(pg.width/2, pg.height*0.65f, -300);
    pg.rotateX(PI/3);
    
    float spacing = 18;
    for (int z=0; z<rows-1; z++) {
      pg.beginShape(TRIANGLE_STRIP);
      for (int x=0; x<cols; x++) {
        float h1 = heights[x][z];
        float h2 = heights[x][z+1];
        float xPos = (x - cols/2f) * spacing;
        float zPos = (z - rows/2f) * spacing;
        int c = color(80 + z*3, 160 + z*2, 255, 200);
        pg.fill(c);
        pg.vertex(xPos, -h1, zPos);
        pg.vertex(xPos, -h2, zPos + spacing);
      }
      pg.endShape();
    }
    
    pg.popStyle();
  }
  
  public String getName() { return "FFT Mountains"; }
}

