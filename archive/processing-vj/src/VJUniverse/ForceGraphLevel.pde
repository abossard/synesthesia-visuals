class ForceGraphLevel extends Level {
  class Node {
    PVector p = new PVector();
    PVector v = new PVector();
    float mass = 1;
  }
  ArrayList<Node> nodes = new ArrayList<Node>();
  ArrayList<int[]> edges = new ArrayList<int[]>();
  
  public void reset() {
    nodes.clear();
    edges.clear();
    for (int i=0;i<24;i++) {
      Node n = new Node();
      n.p.set(random(-180, 180), random(-180, 180), random(-180, 180));
      nodes.add(n);
      if (i>0) edges.add(new int[]{i, (int)random(i)});
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    float repulse = 48000 * (0.8f + audio.getBass()*1.2f);
    float spring = 0.8f + audio.getMid()*1.5f;
    for (int i=0;i<nodes.size();i++) {
      Node a = nodes.get(i);
      for (int j=i+1;j<nodes.size();j++) {
        Node b = nodes.get(j);
        PVector d = PVector.sub(a.p, b.p);
        float dist2 = max(40, d.magSq());
        d.normalize();
        d.mult(repulse/dist2);
        a.v.add(d.mult(dt));
        b.v.sub(d.mult(dt));
      }
    }
    for (int[] e : edges) {
      Node a = nodes.get(e[0]);
      Node b = nodes.get(e[1]);
      PVector d = PVector.sub(b.p, a.p);
      float target = 120;
      float err = d.mag() - target;
      d.normalize();
      d.mult(err * spring * dt);
      a.v.add(d);
      b.v.sub(d);
    }
    for (Node n : nodes) {
      n.v.mult(0.96f);
      n.p.add(PVector.mult(n.v, dt*60));
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.background(6, 7, 12);
    pg.translate(pg.width/2, pg.height/2, -100);
    pg.rotateY(time*0.25f);
    pg.stroke(160, 200, 255, 200);
    pg.strokeWeight(2);
    for (int[] e : edges) {
      PVector a = nodes.get(e[0]).p;
      PVector b = nodes.get(e[1]).p;
      pg.line(a.x, a.y, a.z, b.x, b.y, b.z);
    }
    pg.noStroke();
    for (int i=0;i<nodes.size();i++) {
      Node n = nodes.get(i);
      pg.pushMatrix();
      pg.translate(n.p.x, n.p.y, n.p.z);
      pg.fill(120 + i*5, 200, 255, 220);
      pg.sphere(6);
      pg.popMatrix();
    }
    pg.popStyle();
  }
  
  public String getName() { return "Force Graph"; }
}

