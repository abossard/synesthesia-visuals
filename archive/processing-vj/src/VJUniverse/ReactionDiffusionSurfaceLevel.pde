class ReactionDiffusionSurfaceLevel extends Level {
  int cols = 120;
  int rows = 80;
  float[][] A, B, nextA, nextB;
  float feed = 0.055f;
  float kill = 0.062f;
  
  public void reset() {
    A = new float[cols][rows];
    B = new float[cols][rows];
    nextA = new float[cols][rows];
    nextB = new float[cols][rows];
    for (int x=0;x<cols;x++) for (int y=0;y<rows;y++) {
      A[x][y] = 1;
      if (dist(x,y,cols/2, rows/2) < 6) B[x][y] = 1;
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    feed = 0.054f + audio.getBass()*0.01f;
    kill = 0.06f + audio.getMid()*0.006f;
    float dA = 1.0f;
    float dB = 0.5f;
    for (int x=1;x<cols-1;x++) {
      for (int y=1;y<rows-1;y++) {
        float a = A[x][y];
        float b = B[x][y];
        float lapA = laplace(A,x,y);
        float lapB = laplace(B,x,y);
        nextA[x][y] = a + (dA*lapA - a*b*b + feed*(1-a)) * dt * 60;
        nextB[x][y] = b + (dB*lapB + a*b*b - (kill+feed)*b) * dt * 60;
      }
    }
    float[][] ta=A; A=nextA; nextA=ta;
    float[][] tb=B; B=nextB; nextB=tb;
  }
  
  float laplace(float[][] g, int x, int y) {
    return g[x][y]*-1 +
      (g[x+1][y] + g[x-1][y] + g[x][y+1] + g[x][y-1]) * 0.2f +
      (g[x+1][y+1] + g[x-1][y+1] + g[x+1][y-1] + g[x-1][y-1]) * 0.05f;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 12);
    pg.lights();
    pg.translate(pg.width/2, pg.height*0.6f, -220);
    pg.rotateX(PI/3);
    float spacing = 10;
    for (int y=0;y<rows-1;y++) {
      pg.beginShape(TRIANGLE_STRIP);
      for (int x=0;x<cols;x++) {
        addVertex(pg,x,y,spacing);
        addVertex(pg,x,y+1,spacing);
      }
      pg.endShape();
    }
    pg.popStyle();
  }
  
  void addVertex(PGraphics pg, int x, int y, float spacing) {
    float val = constrain((A[x][y]-B[x][y])*2, -1, 1);
    float z = val * 40;
    float xx = (x - cols/2f) * spacing;
    float yy = (y - rows/2f) * spacing;
    int c = color(120 + val*60, 200, 255, 200);
    pg.fill(c);
    pg.vertex(xx, -z, yy);
  }
  
  public String getName() { return "RD 3D Surface"; }
}

