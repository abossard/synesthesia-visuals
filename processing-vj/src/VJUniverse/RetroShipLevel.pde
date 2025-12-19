class RetroShipLevel extends Level {
  PVector[] verts;
  int[][] edges;
  PVector[] stars;
  float spin = 0;
  
  RetroShipLevel() {
    buildGeometry();
    buildStars();
  }
  
  public void reset() {
    spin = random(TWO_PI);
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    spin += dt * 0.25f;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 6, 14);
    drawStars(pg);
    
    pg.pushMatrix();
    pg.translate(pg.width * 0.5f, pg.height * 0.55f, 0);
    pg.rotateY(spin * 0.8f);
    pg.rotateX(-0.3f + sin(time * 0.3f) * 0.15f);
    
    pg.noFill();
    pg.strokeWeight(3);
    pg.stroke(255, 120, 80);
    drawWireframe(pg, verts, edges);
    
    pg.stroke(80, 220, 255, 180);
    pg.strokeWeight(2);
    pg.pushMatrix();
    pg.translate(0, 0, -70);
    pg.sphereDetail(14);
    pg.sphere(24);
    pg.popMatrix();
    
    pg.popMatrix();
    pg.popStyle();
  }
  
  public void buildGeometry() {
    // Simple fighter silhouette
    verts = new PVector[] {
      new PVector(0, 0, 120),   // nose 0
      new PVector(-40, -12, 40), // left front 1
      new PVector(40, -12, 40),  // right front 2
      new PVector(-70, -8, -40), // left mid 3
      new PVector(70, -8, -40),  // right mid 4
      new PVector(-50, 12, -90), // left rear 5
      new PVector(50, 12, -90),  // right rear 6
      new PVector(0, -2, -120),  // rear 7
      new PVector(-120, -4, 0),  // left wing tip 8
      new PVector(120, -4, 0),   // right wing tip 9
      new PVector(0, -40, -10)   // belly 10
    };
    
    edges = new int[][] {
      {0,1},{0,2},{1,2},
      {1,3},{2,4},
      {3,5},{4,6},{5,7},{6,7},
      {3,8},{2,9},{1,8},{4,9},
      {8,5},{9,6},
      {1,10},{2,10},{10,3},{10,4}
    };
  }
  
  public void buildStars() {
    stars = new PVector[300];
    for (int i = 0; i < stars.length; i++) {
      float x = random(-1, 1) * 900;
      float y = random(-1, 1) * 600;
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
      float tw = 0.5f + noise(i * 0.1f, time * 0.3f) * 1.5f;
      pg.fill(200 + 55 * sin(i), 200, 255, 160);
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
  
  public String getName() { return "Retro Ship"; }
}
