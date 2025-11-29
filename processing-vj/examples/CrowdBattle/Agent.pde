/**
 * Agent class - Represents a single agent in the crowd simulation
 * 
 * Behaviors:
 * - Wander: Random movement when nothing interesting nearby
 * - Fight: Attack nearby agents
 * - Flee: Run away from danger zones (learned from bombs)
 * - Aggression: Increases when cornered or chaos is high
 */

class Agent {
  float x, y;           // Position
  float vx, vy;         // Velocity
  float ax, ay;         // Acceleration
  float size;           // Size (also determines strength)
  float health;         // Health points
  float maxHealth;
  float speed;          // Max speed
  float aggression;     // 0-1, how aggressive
  float fear;           // 0-1, how scared (affects avoidance)
  color c;              // Color (based on team/personality)
  float hue;            // Base hue for coloring
  
  // State
  boolean fighting = false;
  float fightCooldown = 0;
  float lastDamageTime = 0;
  
  Agent(float x, float y) {
    this.x = x;
    this.y = y;
    
    // Random initial velocity toward center
    float angle = atan2(height/2 - y, width/2 - x) + random(-0.5f, 0.5f);
    this.speed = random(1.5f, 4.0f);
    this.vx = cos(angle) * speed;
    this.vy = sin(angle) * speed;
    
    this.ax = 0;
    this.ay = 0;
    
    // Random size (affects strength)
    this.size = random(3, 8);
    this.maxHealth = size * 10;
    this.health = maxHealth;
    
    this.aggression = random(0.2f, 0.8f);
    this.fear = random(0.3f, 0.7f);
    
    // Color based on aggression (red = aggressive, blue = peaceful)
    this.hue = lerp(200, 0, aggression);  // Blue to red
    this.c = color(hue, 80, 100);
  }
  
  void update(ArrayList<Agent> allAgents, float[][] dangerMap) {
    // Reset acceleration
    ax = 0;
    ay = 0;
    
    // Apply behaviors
    applyWander();
    applyFlocking(allAgents);
    applyDangerAvoidance(dangerMap);
    applyBoundaryForce();
    
    // Update velocity
    vx += ax;
    vy += ay;
    
    // Limit speed (faster when fleeing)
    float currentMaxSpeed = speed * (1 + fear * 0.5f);
    float currentSpeed = sqrt(vx*vx + vy*vy);
    if (currentSpeed > currentMaxSpeed) {
      vx = (vx / currentSpeed) * currentMaxSpeed;
      vy = (vy / currentSpeed) * currentMaxSpeed;
    }
    
    // Update position
    x += vx;
    y += vy;
    
    // Decay fight cooldown
    if (fightCooldown > 0) {
      fightCooldown -= 1;
      fighting = fightCooldown > 20;
    }
    
    // Heal slowly over time
    if (millis() - lastDamageTime > 3000) {
      health = min(maxHealth, health + 0.01f);
    }
    
    // Update color based on health
    float healthPercent = health / maxHealth;
    c = color(hue, 80, 40 + 60 * healthPercent);
  }
  
  void applyWander() {
    // Small random force for natural movement
    float wanderStrength = 0.1f;
    ax += random(-wanderStrength, wanderStrength);
    ay += random(-wanderStrength, wanderStrength);
  }
  
  void applyFlocking(ArrayList<Agent> allAgents) {
    // Simplified flocking: separation, alignment, cohesion
    float separationDist = size * 4;
    float alignDist = size * 8;
    float cohesionDist = size * 12;
    
    float sepX = 0, sepY = 0;
    float alignX = 0, alignY = 0;
    float cohX = 0, cohY = 0;
    int sepCount = 0, alignCount = 0, cohCount = 0;
    
    for (Agent other : allAgents) {
      if (other == this) continue;
      
      float d = dist(x, y, other.x, other.y);
      
      // Separation - avoid crowding
      if (d < separationDist && d > 0) {
        float dx = x - other.x;
        float dy = y - other.y;
        sepX += dx / (d * d);
        sepY += dy / (d * d);
        sepCount++;
      }
      
      // Alignment - match velocity of nearby agents
      if (d < alignDist) {
        alignX += other.vx;
        alignY += other.vy;
        alignCount++;
      }
      
      // Cohesion - move toward center of nearby agents (unless aggressive)
      if (d < cohesionDist && aggression < 0.5f) {
        cohX += other.x;
        cohY += other.y;
        cohCount++;
      }
    }
    
    // Apply forces
    float sepWeight = 2.0f;  // Strong separation
    float alignWeight = 0.1f;
    float cohWeight = 0.05f * (1 - aggression);  // Less cohesion when aggressive
    
    if (sepCount > 0) {
      ax += (sepX / sepCount) * sepWeight;
      ay += (sepY / sepCount) * sepWeight;
    }
    
    if (alignCount > 0) {
      float avgVx = alignX / alignCount;
      float avgVy = alignY / alignCount;
      ax += (avgVx - vx) * alignWeight;
      ay += (avgVy - vy) * alignWeight;
    }
    
    if (cohCount > 0) {
      float avgX = cohX / cohCount;
      float avgY = cohY / cohCount;
      ax += (avgX - x) * cohWeight * 0.01f;
      ay += (avgY - y) * cohWeight * 0.01f;
    }
  }
  
  void applyDangerAvoidance(float[][] dangerMap) {
    // Check danger level at current position
    int gridCol = constrain((int)(x / (width / 8.0f)), 0, 7);
    int gridRow = constrain((int)(y / (height / 8.0f)), 0, 7);
    
    float danger = dangerMap[gridCol][gridRow];
    
    if (danger > 0.1f) {
      // Find safest direction to flee
      float safestX = 0, safestY = 0;
      float lowestDanger = danger;
      
      for (int dc = -1; dc <= 1; dc++) {
        for (int dr = -1; dr <= 1; dr++) {
          if (dc == 0 && dr == 0) continue;
          
          int c = gridCol + dc;
          int r = gridRow + dr;
          
          if (c >= 0 && c < 8 && r >= 0 && r < 8) {
            if (dangerMap[c][r] < lowestDanger) {
              lowestDanger = dangerMap[c][r];
              float cellW = width / 8.0f;
              float cellH = height / 8.0f;
              safestX = c * cellW + cellW/2;
              safestY = r * cellH + cellH/2;
            }
          }
        }
      }
      
      // Flee toward safer area
      if (lowestDanger < danger) {
        float fleeStrength = danger * fear * 0.5f;
        float dx = safestX - x;
        float dy = safestY - y;
        float d = sqrt(dx*dx + dy*dy);
        if (d > 0) {
          ax += (dx / d) * fleeStrength;
          ay += (dy / d) * fleeStrength;
        }
        
        // Increase fear when in danger
        fear = min(1.0f, fear + 0.01f);
      }
    } else {
      // Slowly reduce fear when safe
      fear = max(0.1f, fear - 0.001f);
    }
  }
  
  void applyBoundaryForce() {
    // Keep agents mostly on screen
    float margin = 100;
    float force = 0.1f;
    
    if (x < margin) ax += force * (margin - x) / margin;
    if (x > width - margin) ax -= force * (x - (width - margin)) / margin;
    if (y < margin) ay += force * (margin - y) / margin;
    if (y > height - margin) ay -= force * (y - (height - margin)) / margin;
  }
  
  void fight(Agent other) {
    // Both agents take damage
    float myDamage = other.size * other.aggression * 0.5f;
    float otherDamage = size * aggression * 0.5f;
    
    health -= myDamage;
    other.health -= otherDamage;
    
    lastDamageTime = millis();
    other.lastDamageTime = millis();
    
    // Push apart
    float dx = x - other.x;
    float dy = y - other.y;
    float d = sqrt(dx*dx + dy*dy);
    if (d > 0) {
      float pushStrength = 2.0f;
      vx += (dx / d) * pushStrength;
      vy += (dy / d) * pushStrength;
      other.vx -= (dx / d) * pushStrength;
      other.vy -= (dy / d) * pushStrength;
    }
    
    // Set fighting state
    fightCooldown = 30;
    other.fightCooldown = 30;
    fighting = true;
    other.fighting = true;
    
    // Aggression increases slightly after fighting
    aggression = min(1.0f, aggression + 0.02f);
    other.aggression = min(1.0f, other.aggression + 0.02f);
  }
  
  void display() {
    noStroke();
    
    // Glow effect when fighting
    if (fighting) {
      fill(0, 100, 100, 50);
      ellipse(x, y, size * 4, size * 4);
    }
    
    // Fear aura (blue glow when scared)
    if (fear > 0.5f) {
      fill(200, 50, 100, (fear - 0.5f) * 60);
      ellipse(x, y, size * 3, size * 3);
    }
    
    // Main body
    fill(c);
    ellipse(x, y, size * 2, size * 2);
    
    // Direction indicator
    float angle = atan2(vy, vx);
    float indicatorSize = size * 0.8f;
    fill(0, 0, 100, 80);
    float tipX = x + cos(angle) * size * 1.2f;
    float tipY = y + sin(angle) * size * 1.2f;
    ellipse(tipX, tipY, indicatorSize, indicatorSize);
    
    // Health bar (only show if damaged)
    if (health < maxHealth * 0.9f) {
      float barWidth = size * 3;
      float barHeight = 3;
      float healthPercent = health / maxHealth;
      
      fill(0, 0, 30);
      rect(x - barWidth/2, y - size - 8, barWidth, barHeight);
      fill(lerp(0, 120, healthPercent), 100, 100);
      rect(x - barWidth/2, y - size - 8, barWidth * healthPercent, barHeight);
    }
  }
  
  boolean isDead() {
    return health <= 0;
  }
}
