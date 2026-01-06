class MeshMorphLevel extends Level {
  ArrayList<PVector[]> shapes = new ArrayList<PVector[]>();
  int current = 0;
  int next = 1;
  float morph = 0;
  
  public MeshMorphLevel() {
    shapes.add(makeSpherePoints());
    shapes.add(makeCubePoints());
    shapes.add(makeTorusPoints());
    equalizeShapeLengths();
  }
  
  public void reset() {
    current = 0;
    next = 1;
    morph = 0;
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    morph += dt * (0.3f + audio.getLevel() * 1.5f);
    if (morph >= 1) {
      morph = 0;
      current = next;
      next = (next + 1) % shapes.size();
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(8, 8, 14);
    pg.lights();
    pg.translate(pg.width/2, pg.height/2, -100);
    pg.rotateY(time * 0.5f);
    pg.rotateX(time * 0.2f);
    
    PVector[] a = shapes.get(current);
    PVector[] b = shapes.get(next);
    pg.noStroke();
    for (int i=0; i<a.length; i++) {
      PVector p = PVector.lerp(a[i], b[i], morph);
      pg.pushMatrix();
      pg.translate(p.x, p.y, p.z);
      pg.fill(140 + i%120, 200, 255, 200);
      pg.sphere(4);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  PVector[] makeSpherePoints() {
    ArrayList<PVector> pts = new ArrayList<PVector>();
    int lat = 14, lon = 18;
    float r = 160;
    for (int i=0; i<lat; i++) {
      float th = map(i, 0, lat-1, -HALF_PI, HALF_PI);
      for (int j=0; j<lon; j++) {
        float ph = map(j, 0, lon, 0, TWO_PI);
        pts.add(new PVector(cos(th)*cos(ph)*r, sin(th)*r, cos(th)*sin(ph)*r));
      }
    }
    return pts.toArray(new PVector[0]);
  }
  
  PVector[] makeCubePoints() {
    ArrayList<PVector> pts = new ArrayList<PVector>();
    float r = 150;
    for (int x=-1; x<=1; x++) for (int y=-1; y<=1; y++) for (int z=-1; z<=1; z++) {
      pts.add(new PVector(x*r, y*r, z*r));
    }
    return pts.toArray(new PVector[0]);
  }
  
  PVector[] makeTorusPoints() {
    ArrayList<PVector> pts = new ArrayList<PVector>();
    float R=160,r=60;
    for (int i=0;i<16;i++){
      float u=map(i,0,16,0,TWO_PI);
      for (int j=0;j<14;j++){
        float v=map(j,0,14,0,TWO_PI);
        float x=(R+r*cos(v))*cos(u);
        float y=(R+r*cos(v))*sin(u);
        float z=r*sin(v);
        pts.add(new PVector(x,y,z));
      }
    }
    return pts.toArray(new PVector[0]);
  }
  
  void equalizeShapeLengths() {
    int maxLen = 0;
    for (PVector[] s : shapes) {
      if (s.length > maxLen) maxLen = s.length;
    }
    for (int idx=0; idx<shapes.size(); idx++) {
      PVector[] src = shapes.get(idx);
      if (src.length == maxLen) continue;
      PVector[] expanded = new PVector[maxLen];
      for (int i=0; i<maxLen; i++) {
        expanded[i] = src[i % src.length].copy();
      }
      shapes.set(idx, expanded);
    }
  }
  
  public String getName() { return "Mesh Morph"; }
}
