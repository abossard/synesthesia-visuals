class ReactionDiffusionLevel extends Level {
  int cols = 160;
  int rows = 90;
  float[][] A, B, nextA, nextB;
  
  public void reset() {
    A = new float[cols][rows];
    B = new float[cols][rows];
    nextA = new float[cols][rows];
    nextB = new float[cols][rows];
    for (int x = 0; x < cols; x++) {
      for (int y = 0; y < rows; y++) {
        A[x][y] = 1;
        B[x][y] = 0;
        if (dist(x, y, cols/2, rows/2) < 6) {
          B[x][y] = 1;
        }
      }
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    float dA = 1.0f;
    float dB = 0.5f;
    float feed = 0.055f + 0.01f * sin(t * 0.2f);
    float kill = 0.062f + 0.005f * cos(t * 0.17f);
    for (int x = 1; x < cols-1; x++) {
      for (int y = 1; y < rows-1; y++) {
        float a = A[x][y];
        float b = B[x][y];
        float lapA = laplace(A, x, y);
        float lapB = laplace(B, x, y);
        nextA[x][y] = a + (dA * lapA - a*b*b + feed*(1-a)) * dt * 60;
        nextB[x][y] = b + (dB * lapB + a*b*b - (kill+feed)*b) * dt * 60;
      }
    }
    float[][] tmpA = A; A = nextA; nextA = tmpA;
    float[][] tmpB = B; B = nextB; nextB = tmpB;
  }
  
  public float laplace(float[][] g, int x, int y) {
    return g[x][y]*-1 +
      (g[x+1][y] + g[x-1][y] + g[x][y+1] + g[x][y-1]) * 0.2f +
      (g[x+1][y+1] + g[x-1][y+1] + g[x+1][y-1] + g[x-1][y-1]) * 0.05f;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.loadPixels();
    for (int x = 0; x < cols; x++) {
      for (int y = 0; y < rows; y++) {
        float c = constrain((A[x][y] - B[x][y]) * 255, 0, 255);
        int col = pg.color(c, 120 + c*0.4f, 255 - c*0.3f);
        int px = (int)map(x, 0, cols, 0, pg.width);
        int py = (int)map(y, 0, rows, 0, pg.height);
        int idx = py * pg.width + px;
        if (idx >= 0 && idx < pg.pixels.length) {
          pg.pixels[idx] = col;
        }
      }
    }
    pg.updatePixels();
    pg.popStyle();
  }
  
  public String getName() { return "Reaction Diffusion"; }
}
