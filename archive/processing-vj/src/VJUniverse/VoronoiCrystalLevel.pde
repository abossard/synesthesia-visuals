class VoronoiCrystalLevel extends Level {
  class Cell {
    PVector p = new PVector();
    float size;
    int col;
  }
  ArrayList<Cell> cells = new ArrayList<Cell>();
  
  public void reset() {
    cells.clear();
    for (int i=0;i<16;i++) {
      Cell c = new Cell();
      c.p.set(random(-180,180), random(-180,180), random(-180,180));
      c.size = random(60, 120);
      c.col = color(120 + i*8, 200, 255, 140);
      cells.add(c);
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    for (Cell c : cells) {
      c.p.add((noise(c.p.x*0.002f, t*0.2f)-0.5f)*2,
              (noise(c.p.y*0.002f, t*0.2f+20)-0.5f)*2,
              (noise(c.p.z*0.002f, t*0.2f+40)-0.5f)*2);
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 6, 12);
    pg.lights();
    pg.translate(pg.width/2, pg.height/2, -140);
    pg.rotateY(time*0.35f);
    pg.rotateX(0.4f);
    for (Cell c : cells) {
      pg.pushMatrix();
      pg.translate(c.p.x, c.p.y, c.p.z);
      pg.fill(c.col);
      pg.stroke(180, 220, 255, 140);
      pg.box(c.size * 0.6f, c.size, c.size * 0.6f);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Voronoi Crystal"; }
}

