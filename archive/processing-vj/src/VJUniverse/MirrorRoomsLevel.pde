class MirrorRoomsLevel extends Level {
  public void reset() {}
  public void update(float dt, float t, AudioEnvelope audio) {}
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 8, 12);
    int tiles = 4;
    float w = pg.width / tiles;
    float h = pg.height / tiles;
    for (int i=0; i<tiles; i++) {
      for (int j=0; j<tiles; j++) {
        pg.pushMatrix();
        pg.translate(i*w + w/2, j*h + h/2);
        float sx = (i%2==0)?1:-1;
        float sy = (j%2==0)?1:-1;
        pg.scale(sx, sy);
        pg.rotate(time*0.4f + (i+j)*0.2f);
        pg.fill(120+ i*30, 180, 240, 160);
        pg.noStroke();
        pg.rectMode(CENTER);
        pg.rect(0,0,w*0.7f,h*0.4f);
        pg.popMatrix();
      }
    }
    pg.popStyle();
  }
  
  public String getName() { return "Mirror Rooms"; }
}
