class LSystemTreesLevel extends Level {
  int iterations = 4;
  float branchAngle = PI/5;
  float branchLen = 70;
  
  public void reset() {
    // no persistent state
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    iterations = 3 + (int)map(audio.getMid(), 0, 1, 0, 2);
    branchAngle = PI/5 + audio.getHigh() * 0.6f;
    branchLen = 60 + audio.getBass() * 80;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 8, 14);
    pg.lights();
    pg.translate(pg.width/2, pg.height*0.9f, -120);
    pg.rotateY(sin(time*0.2f)*0.4f);
    drawTree(pg, iterations, branchLen);
    pg.popStyle();
  }
  
  void drawTree(PGraphics pg, int depth, float len) {
    if (depth == 0) return;
    pg.pushMatrix();
    pg.stroke(180, 200, 255, 200);
    pg.strokeWeight(map(depth, 0, iterations, 1, 6));
    pg.line(0, 0, 0, 0, -len, 0);
    pg.translate(0, -len, 0);
    // left
    pg.pushMatrix();
    pg.rotateZ(branchAngle + random(-0.1f, 0.1f));
    drawTree(pg, depth-1, len * 0.72f);
    pg.popMatrix();
    // right
    pg.pushMatrix();
    pg.rotateZ(-branchAngle + random(-0.1f, 0.1f));
    drawTree(pg, depth-1, len * 0.72f);
    pg.popMatrix();
    // forward
    pg.pushMatrix();
    pg.rotateY(branchAngle*0.8f);
    drawTree(pg, depth-1, len * 0.7f);
    pg.popMatrix();
    pg.popMatrix();
  }
  
  public String getName() { return "L-System Trees"; }
}

