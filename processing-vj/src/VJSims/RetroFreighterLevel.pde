class RetroFreighterLevel extends Level {
  PVector[] verts;
  int[][] edges;
  PVector[] stars;
  float spin = 0;
  
  RetroFreighterLevel() {
    buildGeometry();
    buildStars();
  }
  
  public void reset() {
    spin = random(TWO_PI);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    spin += dt * 0.18f;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(4, 5, 10);
    drawStars(pg);
    
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.55f, -40);
    pg.rotateY(spin * 0.5f + 0.6f);
    pg.rotateX(-0.25f + sin(time * 0.2f) * 0.1f);
    
    pg.noFill();
    pg.strokeWeight(2.6f);
    pg.stroke(120, 200, 255);
    drawWireframe(pg, verts, edges);
    
    // Accent glowing core
    pg.stroke(255, 140, 120, 180);
    pg.strokeWeight(3);
    pg.line(-20, 0, 0, 20, 0, 0);
    pg.line(0, -20, 0, 0, 20, 0);
    
    pg.popMatrix();
    pg.popStyle();
  }
  
  public void buildGeometry() {
    // Chunky freighter silhouette
    verts = new PVector[] {
      new PVector(-90, -25, 130), // nose left
      new PVector(90, -25, 130),  // nose right
      new PVector(-110, 25, 70),  // nose bottom left
      new PVector(110, 25, 70),   // nose bottom right
      new PVector(-140, -30, -20),// mid left upper
      new PVector(140, -30, -20), // mid right upper
      new PVector(-140, 30, -20), // mid left lower
      new PVector(140, 30, -20),  // mid right lower
      new PVector(-90, -35, -140),// tail upper left
      new PVector(90, -35, -140), // tail upper right
      new PVector(-90, 35, -140), // tail lower left
      new PVector(90, 35, -140),  // tail lower right
      new PVector(-180, 0, -60),  // wing left
      new PVector(180, 0, -60)    // wing right
    };
    
    edges = new int[][] {
      {0,1},{1,3},{2,3},{0,2},
      {0,4},{1,5},{2,6},{3,7},
      {4,5},{5,7},{4,6},{6,7},
      {4,8},{5,9},{6,10},{7,11},
      {8,9},{9,11},{8,10},{10,11},
      {4,12},{6,12},{5,13},{7,13},
      {12,8},{12,10},{13,9},{13,11}
    };
  }
  
  public void buildStars() {
    stars = new PVector[260];
    for (int i = 0; i < stars.length; i++) {
      float x = random(-1, 1) * 950;
      float y = random(-1, 1) * 650;
      float z = random(200, 1400);
      stars[i] = new PVector(x, y, -z);
    }
  }
  
  public void drawStars(PGraphics pg) {
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.5f, 0);
    pg.noStroke();
    for (int i = 0; i < stars.length; i++) {
      PVector s = stars[i];
      float tw = 0.7f + noise(i * 0.2f, time * 0.25f) * 1.3f;
      pg.fill(180 + 60 * sin(i * 0.23f), 180, 255, 150);
      pg.rect(s.x, s.y, tw, tw);
    }
    pg.popMatrix();
  }
  
  public void drawWireframe(PGraphics pg, PVector[] v, int[][] e) {
    pg.beginShape(LINES);
    for (int i = 0; i < e.length; i++) {
      PVector a = v[e[i][0]];
      PVector b = v[e[i][1]];
      pg.vertex(a.x, a.y, a.z);
      pg.vertex(b.x, b.y, b.z);
    }
    pg.endShape();
  }
  
  public String getName() { return "Retro Freighter"; }
}
