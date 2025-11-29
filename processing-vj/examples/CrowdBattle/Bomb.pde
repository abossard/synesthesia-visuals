/**
 * Bomb class - A bomb dropped by the player
 * 
 * Features:
 * - Falls from above with a warning indicator
 * - Explodes after a short delay
 * - Creates a danger zone that agents learn to avoid
 */

class Bomb {
  float x, y;           // Position
  float targetY;        // Where the bomb will land
  float fallSpeed;
  float radius;         // Explosion radius
  float landTime;       // Time when bomb landed (millis)
  float fuseTime;       // How long until explosion after landing (ms)
  boolean landed = false;
  boolean exploded = false;
  float warningPulse = 0;
  
  Bomb(float x, float y) {
    this.x = x;
    this.targetY = y;
    this.y = -50;  // Start from above screen
    this.fallSpeed = 15;
    this.radius = 120;  // Explosion radius
    this.fuseTime = 1000;  // ms until explosion after landing
    this.landTime = 0;
    this.warningPulse = 0;
  }
  
  void update() {
    if (y < targetY) {
      // Falling
      y += fallSpeed;
      if (y >= targetY) {
        y = targetY;
        landed = true;
        landTime = millis();
      }
    } else if (landed) {
      // Landed, countdown to explosion using frame-rate independent timing
      float elapsed = millis() - landTime;
      warningPulse += 0.3f;
      
      if (elapsed >= fuseTime) {
        exploded = true;
      }
    }
  }
  
  // Get remaining time until explosion (for display)
  float getTimeRemaining() {
    if (!landed) return fuseTime;
    return max(0, fuseTime - (millis() - landTime));
  }
  
  void display() {
    if (y < targetY) {
      // Falling bomb
      fill(0, 100, 100);
      noStroke();
      
      // Bomb body
      pushMatrix();
      translate(x, y);
      
      // Main body
      ellipse(0, 0, 20, 25);
      
      // Fins
      triangle(-8, 5, 0, 15, 8, 5);
      
      // Fuse spark
      fill(30, 100, 100);
      float sparkSize = 5 + sin(frameCount * 0.5f) * 2;
      ellipse(0, -15, sparkSize, sparkSize);
      
      popMatrix();
      
      // Target indicator on ground
      stroke(0, 100, 100, 50);
      strokeWeight(2);
      noFill();
      float indicatorSize = radius * 0.5f;
      ellipse(x, targetY, indicatorSize, indicatorSize);
      line(x - indicatorSize/2, targetY, x + indicatorSize/2, targetY);
      line(x, targetY - indicatorSize/2, x, targetY + indicatorSize/2);
      
    } else {
      // Landed - pulsing warning
      noFill();
      
      // Danger zone indicator
      float pulseSize = sin(warningPulse) * 20;
      float timeRemaining = getTimeRemaining();
      float alpha = map(timeRemaining, fuseTime, 0, 30, 100);
      
      stroke(0, 100, 100, alpha);
      strokeWeight(3);
      ellipse(x, y, radius + pulseSize, radius + pulseSize);
      
      stroke(30, 100, 100, alpha * 0.7f);
      strokeWeight(2);
      ellipse(x, y, radius * 0.7f + pulseSize, radius * 0.7f + pulseSize);
      
      stroke(60, 100, 100, alpha * 0.5f);
      strokeWeight(1);
      ellipse(x, y, radius * 0.4f + pulseSize, radius * 0.4f + pulseSize);
      
      // Bomb at center
      noStroke();
      fill(0, 100, 100);
      ellipse(x, y, 25, 30);
      
      // Pulsing glow
      fill(0, 100, 100, 30 + sin(warningPulse * 2) * 20);
      ellipse(x, y, 50, 50);
      
      // Countdown text
      fill(0, 0, 100);
      textAlign(CENTER, CENTER);
      textSize(12);
      text(nf(timeRemaining/1000, 1, 1), x, y - 30);
    }
    
    strokeWeight(1);
  }
}

/**
 * Explosion class - Visual effect when a bomb detonates
 * 
 * Features:
 * - Expanding shockwave ring
 * - Particle burst
 * - Screen shake effect
 */

class Explosion {
  float x, y;
  float radius;
  float maxRadius;
  float life;
  float maxLife;
  ArrayList<ExplosionParticle> particles;
  
  Explosion(float x, float y, float radius) {
    this.x = x;
    this.y = y;
    this.radius = 10;
    this.maxRadius = radius * 1.5f;
    this.maxLife = 60;
    this.life = maxLife;
    
    // Create explosion particles
    particles = new ArrayList<ExplosionParticle>();
    for (int i = 0; i < 50; i++) {
      particles.add(new ExplosionParticle(x, y));
    }
  }
  
  void update() {
    life--;
    
    // Expand quickly then slow down
    float progress = 1 - (life / maxLife);
    radius = maxRadius * easeOutQuart(progress);
    
    // Update particles
    for (ExplosionParticle p : particles) {
      p.update();
    }
  }
  
  float easeOutQuart(float t) {
    return 1 - pow(1 - t, 4);
  }
  
  void display() {
    float alpha = (life / maxLife) * 255;
    
    // Core flash
    if (life > maxLife * 0.8f) {
      float coreAlpha = map(life, maxLife, maxLife * 0.8f, 200, 0);
      fill(30, 80, 100, coreAlpha);
      noStroke();
      ellipse(x, y, radius * 0.5f, radius * 0.5f);
    }
    
    // Shockwave rings
    noFill();
    
    // Outer ring
    stroke(0, 100, 100, alpha * 0.8f);
    strokeWeight(8 * (life / maxLife));
    ellipse(x, y, radius * 2, radius * 2);
    
    // Middle ring
    stroke(30, 100, 100, alpha * 0.6f);
    strokeWeight(5 * (life / maxLife));
    ellipse(x, y, radius * 1.5f, radius * 1.5f);
    
    // Inner ring
    stroke(60, 100, 100, alpha * 0.4f);
    strokeWeight(3 * (life / maxLife));
    ellipse(x, y, radius, radius);
    
    // Draw particles
    for (ExplosionParticle p : particles) {
      p.display(life / maxLife);
    }
    
    strokeWeight(1);
  }
  
  boolean isDead() {
    return life <= 0;
  }
}

/**
 * ExplosionParticle - Individual particle in an explosion
 */
class ExplosionParticle {
  float x, y;
  float vx, vy;
  float size;
  float hue;
  
  ExplosionParticle(float x, float y) {
    this.x = x;
    this.y = y;
    
    float angle = random(TWO_PI);
    float speed = random(3, 15);
    this.vx = cos(angle) * speed;
    this.vy = sin(angle) * speed;
    
    this.size = random(3, 10);
    this.hue = random(0, 60);  // Red to yellow
  }
  
  void update() {
    x += vx;
    y += vy;
    
    // Slow down
    vx *= 0.95f;
    vy *= 0.95f;
    
    // Gravity
    vy += 0.1f;
    
    // Shrink
    size *= 0.97f;
  }
  
  void display(float lifeRatio) {
    noStroke();
    fill(hue, 100, 100, lifeRatio * 200);
    ellipse(x, y, size, size);
  }
}
