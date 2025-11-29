/**
 * Bomb class - Fully particle-based bomb
 * 
 * Features:
 * - Particle trail while falling
 * - Particle-based warning indicator
 * - Fast explosion that disappears within 1-2 seconds
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
  
  // Particle trail while falling
  ArrayList<BombTrailParticle> trailParticles;
  // Warning particles when landed
  ArrayList<WarningParticle> warningParticles;
  
  Bomb(float x, float y) {
    this.x = x;
    this.targetY = y;
    this.y = -50;  // Start from above screen
    this.fallSpeed = 15;
    this.radius = 120;  // Explosion radius
    this.fuseTime = 800;  // Faster fuse
    this.landTime = 0;
    this.warningPulse = 0;
    
    trailParticles = new ArrayList<BombTrailParticle>();
    warningParticles = new ArrayList<WarningParticle>();
  }
  
  void update() {
    if (y < targetY) {
      // Falling - emit trail particles
      y += fallSpeed;
      
      // Spawn trail sparks
      for (int i = 0; i < 3; i++) {
        trailParticles.add(new BombTrailParticle(x + random(-5, 5), y + 10));
      }
      
      if (y >= targetY) {
        y = targetY;
        landed = true;
        landTime = millis();
        // Burst of warning particles
        for (int i = 0; i < 30; i++) {
          warningParticles.add(new WarningParticle(x, y, radius));
        }
      }
    } else if (landed) {
      float elapsed = millis() - landTime;
      warningPulse += 0.4f;
      
      // Spawn pulsing warning particles
      if (frameCount % 3 == 0) {
        for (int i = 0; i < 5; i++) {
          warningParticles.add(new WarningParticle(x, y, radius * 0.5f));
        }
      }
      
      if (elapsed >= fuseTime) {
        exploded = true;
      }
    }
    
    // Update trail particles
    for (int i = trailParticles.size() - 1; i >= 0; i--) {
      BombTrailParticle p = trailParticles.get(i);
      p.update();
      if (p.isDead()) trailParticles.remove(i);
    }
    
    // Update warning particles
    for (int i = warningParticles.size() - 1; i >= 0; i--) {
      WarningParticle p = warningParticles.get(i);
      p.update();
      if (p.isDead()) warningParticles.remove(i);
    }
  }
  
  void display() {
    // Draw trail particles
    for (BombTrailParticle p : trailParticles) {
      p.display();
    }
    
    // Draw warning particles
    for (WarningParticle p : warningParticles) {
      p.display();
    }
    
    if (y < targetY) {
      // Falling bomb - particle cluster
      noStroke();
      
      // Core glow
      fill(0, 100, 100, 80);
      ellipse(x, y, 25, 30);
      
      // Hot center
      fill(30, 100, 100);
      ellipse(x, y, 15, 18);
      
      // Fuse spark particles
      fill(60, 80, 100);
      for (int i = 0; i < 5; i++) {
        float sx = x + random(-8, 8);
        float sy = y - 12 + random(-5, 5);
        float ss = random(2, 6);
        ellipse(sx, sy, ss, ss);
      }
      
    } else if (!exploded) {
      // Landed - pulsing particle core
      noStroke();
      
      float pulse = sin(warningPulse) * 0.3f + 0.7f;
      float timeRatio = 1 - ((millis() - landTime) / fuseTime);
      
      // Danger glow
      fill(0, 100, 100, 40 * pulse);
      ellipse(x, y, 60 * pulse, 60 * pulse);
      
      // Core
      fill(0, 100, 100, 90);
      ellipse(x, y, 20, 24);
      
      // Sparking particles around it
      fill(30, 100, 100);
      for (int i = 0; i < 8; i++) {
        float angle = i * TWO_PI / 8 + warningPulse * 0.5f;
        float dist = 25 + sin(warningPulse * 2 + i) * 10;
        float px = x + cos(angle) * dist;
        float py = y + sin(angle) * dist;
        ellipse(px, py, 4, 4);
      }
    }
  }
}

/**
 * BombTrailParticle - Spark trail behind falling bomb
 */
class BombTrailParticle {
  float x, y;
  float vx, vy;
  float life, maxLife;
  float size;
  float hue;
  
  BombTrailParticle(float x, float y) {
    this.x = x;
    this.y = y;
    this.vx = random(-2, 2);
    this.vy = random(-1, 3);
    this.maxLife = random(15, 30);
    this.life = maxLife;
    this.size = random(3, 8);
    this.hue = random(0, 40);
  }
  
  void update() {
    life--;
    x += vx;
    y += vy;
    vy += 0.1f;
    vx *= 0.95f;
    size *= 0.92f;
  }
  
  void display() {
    float alpha = (life / maxLife) * 150;
    noStroke();
    fill(hue, 100, 100, alpha);
    ellipse(x, y, size, size);
  }
  
  boolean isDead() {
    return life <= 0 || size < 0.5f;
  }
}

/**
 * WarningParticle - Pulsing danger indicator particles
 */
class WarningParticle {
  float x, y;
  float vx, vy;
  float life, maxLife;
  float size;
  
  WarningParticle(float cx, float cy, float spread) {
    float angle = random(TWO_PI);
    float dist = random(spread * 0.3f, spread);
    this.x = cx + cos(angle) * dist;
    this.y = cy + sin(angle) * dist;
    
    // Move outward slowly
    this.vx = cos(angle) * random(0.5f, 2);
    this.vy = sin(angle) * random(0.5f, 2);
    
    this.maxLife = random(20, 40);
    this.life = maxLife;
    this.size = random(4, 10);
  }
  
  void update() {
    life--;
    x += vx;
    y += vy;
    vx *= 0.95f;
    vy *= 0.95f;
    size *= 0.95f;
  }
  
  void display() {
    float alpha = (life / maxLife) * 100;
    noStroke();
    fill(0, 100, 100, alpha);
    ellipse(x, y, size, size);
  }
  
  boolean isDead() {
    return life <= 0 || size < 1;
  }
}

/**
 * Explosion class - Fast particle-based explosion
 * 
 * Features:
 * - Hundreds of particles burst outward
 * - Quick smoke that rises and fades
 * - Sparks with trails
 * - Everything disappears within 1-2 seconds
 */

class Explosion {
  float x, y;
  float radius;
  float life;
  float maxLife;
  
  // Particle systems
  ArrayList<FireParticle> fireParticles;
  ArrayList<SmokeParticle> smokeParticles;
  ArrayList<SparkParticle> sparks;
  
  // Flash
  float flashIntensity;
  
  Explosion(float x, float y, float radius) {
    this.x = x;
    this.y = y;
    this.radius = radius;
    this.maxLife = 90;  // 1.5 seconds at 60fps
    this.life = maxLife;
    
    // Initial flash
    this.flashIntensity = 1.0f;
    
    // Create fire particles (burst outward fast)
    fireParticles = new ArrayList<FireParticle>();
    for (int i = 0; i < 150; i++) {
      fireParticles.add(new FireParticle(x, y, radius * 0.8f));
    }
    
    // Create smoke particles (fewer, faster fade)
    smokeParticles = new ArrayList<SmokeParticle>();
    for (int i = 0; i < 40; i++) {
      smokeParticles.add(new SmokeParticle(x, y, radius * 0.4f));
    }
    
    // Create sparks (fast, bright)
    sparks = new ArrayList<SparkParticle>();
    for (int i = 0; i < 60; i++) {
      sparks.add(new SparkParticle(x, y, radius));
    }
  }
  
  void update() {
    life--;
    
    // Flash fades very quickly
    flashIntensity *= 0.75f;
    
    // Update all particle systems
    for (int i = fireParticles.size() - 1; i >= 0; i--) {
      FireParticle p = fireParticles.get(i);
      p.update();
      if (p.isDead()) fireParticles.remove(i);
    }
    
    for (int i = smokeParticles.size() - 1; i >= 0; i--) {
      SmokeParticle p = smokeParticles.get(i);
      p.update();
      if (p.isDead()) smokeParticles.remove(i);
    }
    
    for (int i = sparks.size() - 1; i >= 0; i--) {
      SparkParticle p = sparks.get(i);
      p.update();
      if (p.isDead()) sparks.remove(i);
    }
  }
  
  void display() {
    // Initial flash (very brief)
    if (flashIntensity > 0.1f) {
      noStroke();
      float flashSize = radius * 2 * flashIntensity;
      
      fill(60, 20, 100, flashIntensity * 200);
      ellipse(x, y, flashSize, flashSize);
      
      fill(30, 80, 100, flashIntensity * 120);
      ellipse(x, y, flashSize * 1.3f, flashSize * 1.3f);
    }
    
    // Draw smoke (behind)
    for (SmokeParticle p : smokeParticles) {
      p.display();
    }
    
    // Draw fire particles
    for (FireParticle p : fireParticles) {
      p.display();
    }
    
    // Draw sparks (on top)
    for (SparkParticle p : sparks) {
      p.display();
    }
  }
  
  boolean isDead() {
    return fireParticles.isEmpty() && 
           smokeParticles.isEmpty() && 
           sparks.isEmpty();
  }
}

/**
 * FireParticle - Fast-fading fire particles
 */
class FireParticle {
  float x, y;
  float vx, vy;
  float size;
  float life, maxLife;
  float hue;
  
  FireParticle(float x, float y, float explosionRadius) {
    this.x = x;
    this.y = y;
    
    float angle = random(TWO_PI);
    float speed = random(4, 18);
    this.vx = cos(angle) * speed;
    this.vy = sin(angle) * speed - random(2, 5);
    
    this.size = random(10, 30);
    this.maxLife = random(20, 45);  // Short life
    this.life = maxLife;
    this.hue = random(0, 45);
  }
  
  void update() {
    life--;
    
    // Rise up
    vy -= 0.2f;
    
    // Drag
    vx *= 0.94f;
    vy *= 0.94f;
    
    x += vx;
    y += vy;
    
    // Shrink fast
    float lifeRatio = life / maxLife;
    size *= 0.92f;
  }
  
  void display() {
    if (size < 1) return;
    
    float lifeRatio = life / maxLife;
    float alpha = lifeRatio * 100;
    
    noStroke();
    
    // Glow
    fill(hue, 80, 100, alpha * 0.4f);
    ellipse(x, y, size * 1.5f, size * 1.5f);
    
    // Core
    fill(hue, 90, 100, alpha);
    ellipse(x, y, size, size);
  }
  
  boolean isDead() {
    return life <= 0 || size < 1;
  }
}

/**
 * SmokeParticle - Quick-fading smoke
 */
class SmokeParticle {
  float x, y;
  float vx, vy;
  float size;
  float life, maxLife;
  
  SmokeParticle(float x, float y, float spread) {
    this.x = x + random(-spread, spread);
    this.y = y + random(-spread, spread);
    
    this.vx = random(-1.5f, 1.5f);
    this.vy = random(-3, -1);
    
    this.size = random(15, 40);
    this.maxLife = random(40, 70);  // Quick fade
    this.life = maxLife;
  }
  
  void update() {
    life--;
    
    // Rise
    vy -= 0.1f;
    
    vx *= 0.97f;
    vy *= 0.97f;
    
    x += vx;
    y += vy;
    
    // Grow briefly then shrink
    float lifeRatio = life / maxLife;
    if (lifeRatio > 0.8f) {
      size *= 1.02f;
    } else {
      size *= 0.96f;
    }
  }
  
  void display() {
    if (size < 2) return;
    
    float lifeRatio = life / maxLife;
    float alpha = lifeRatio * 35;
    
    noStroke();
    fill(0, 0, 25, alpha);
    ellipse(x, y, size, size * 0.85f);
  }
  
  boolean isDead() {
    return life <= 0 || size < 2;
  }
}

/**
 * SparkParticle - Fast sparks with short trails
 */
class SparkParticle {
  float x, y;
  float vx, vy;
  float life, maxLife;
  float hue;
  float prevX, prevY;
  
  SparkParticle(float x, float y, float explosionRadius) {
    this.x = x;
    this.y = y;
    this.prevX = x;
    this.prevY = y;
    
    float angle = random(TWO_PI);
    float speed = random(10, 30);
    this.vx = cos(angle) * speed;
    this.vy = sin(angle) * speed;
    
    this.maxLife = random(15, 35);  // Very short
    this.life = maxLife;
    this.hue = random(30, 60);
  }
  
  void update() {
    life--;
    
    prevX = x;
    prevY = y;
    
    // Gravity
    vy += 0.5f;
    
    vx *= 0.96f;
    vy *= 0.96f;
    
    x += vx;
    y += vy;
  }
  
  void display() {
    float lifeRatio = life / maxLife;
    float alpha = lifeRatio * 180;
    
    // Trail line
    stroke(hue, 80, 100, alpha * 0.6f);
    strokeWeight(2 * lifeRatio);
    line(prevX, prevY, x, y);
    
    // Spark head
    noStroke();
    fill(hue, 50, 100, alpha);
    ellipse(x, y, 4 * lifeRatio, 4 * lifeRatio);
    
    strokeWeight(1);
  }
  
  boolean isDead() {
    return life <= 0;
  }
}
