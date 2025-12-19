class AgentTrailsLevel extends Level {
  class Agent {
    PVector p = new PVector();
    float heading;
  }
  Agent[] agents;
  
  public void reset() {
    agents = new Agent[400];
    for (int i = 0; i < agents.length; i++) {
      Agent a = new Agent();
      a.p.set(random(width), random(height));
      a.heading = random(TWO_PI);
      agents[i] = a;
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    for (Agent a : agents) {
      float turn = (noise(a.p.x*0.01f, a.p.y*0.01f, t*0.2f) - 0.5f) * 0.8f;
      a.heading += turn;
      a.p.x += cos(a.heading) * 30 * dt * 60;
      a.p.y += sin(a.heading) * 30 * dt * 60;
      if (a.p.x < 0) a.p.x += width;
      if (a.p.x > width) a.p.x -= width;
      if (a.p.y < 0) a.p.y += height;
      if (a.p.y > height) a.p.y -= height;
    }
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    pg.fill(0, 0, 0, 14);
    pg.noStroke();
    pg.rect(0, 0, pg.width, pg.height);
    
    pg.stroke(200, 240, 255, 120);
    pg.strokeWeight(1.2f);
    pg.beginShape(POINTS);
    for (Agent a : agents) {
      pg.vertex(a.p.x, a.p.y);
    }
    pg.endShape();
    pg.popStyle();
  }
  
  public String getName() { return "Agent Trails"; }
}
