/**
 * CinematicCamera.pde - Smooth 6DOF Cinematic Camera System
 *
 * Key design principles:
 * - ALL movement uses spring physics - never snaps or hard cuts
 * - Mode changes blend smoothly - targets transition, not positions
 * - Subject tracking keeps the subject ~85% visible
 * - Layered Perlin noise for organic micro-movements
 */

// ============================================
// EASING FUNCTIONS (Static utility class)
// ============================================

static class Easing {
  static float linear(float t) { return t; }
  static float easeInQuad(float t) { return t * t; }
  static float easeOutQuad(float t) { return 1 - (1 - t) * (1 - t); }
  static float easeInOutQuad(float t) { return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2; }
  static float easeInCubic(float t) { return t * t * t; }
  static float easeOutCubic(float t) { return 1 - pow(1 - t, 3); }
  static float easeInOutCubic(float t) { return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2; }
  static float easeInQuart(float t) { return t * t * t * t; }
  static float easeOutQuart(float t) { return 1 - pow(1 - t, 4); }
  static float easeInOutQuart(float t) { return t < 0.5 ? 8 * t * t * t * t : 1 - pow(-2 * t + 2, 4) / 2; }
  static float easeInExpo(float t) { return t == 0 ? 0 : pow(2, 10 * t - 10); }
  static float easeOutExpo(float t) { return t == 1 ? 1 : 1 - pow(2, -10 * t); }
  static float easeInOutExpo(float t) {
    if (t == 0) return 0;
    if (t == 1) return 1;
    return t < 0.5 ? pow(2, 20 * t - 10) / 2 : (2 - pow(2, -20 * t + 10)) / 2;
  }
  static float easeOutBack(float t) {
    float c1 = 1.70158;
    float c3 = c1 + 1;
    return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2);
  }
  static float smoothStep(float t) { return t * t * (3 - 2 * t); }
  static float smootherStep(float t) { return t * t * t * (t * (t * 6 - 15) + 10); }
}

// ============================================
// CINEMATIC CAMERA
// ============================================

class CinematicCamera {

  // Camera modes (determine how target position is calculated)
  static final int MODE_STATIC = 0;
  static final int MODE_FOLLOW = 1;
  static final int MODE_CHASE = 2;
  static final int MODE_ORBIT = 3;

  // Current mode
  int mode = MODE_ORBIT;

  // === ACTUAL CAMERA STATE (what gets rendered) ===
  PVector position;
  PVector lookAt;
  float roll;

  // === TARGET STATE (what we're moving toward - NEVER set position directly) ===
  PVector targetPosition;
  PVector targetLookAt;
  float targetRoll;

  // === VELOCITY (for spring physics) ===
  PVector velocity;
  PVector lookAtVelocity;
  float rollVelocity;

  // === SPRING PARAMETERS ===
  float positionStiffness = 2.5;   // How quickly position catches up
  float lookAtStiffness = 4.0;     // Look-at is usually snappier
  float damping = 0.88;            // Oscillation damping (0-1)
  float maxSpeed = 3000;           // Velocity limit

  // === SUBJECT TRACKING ===
  PVector subject;                 // The thing we're filming (ship, planet, etc)
  float subjectRadius = 200;       // Approximate size of subject
  float idealDistance = 300;       // How far camera should be from subject
  float minDistance = 150;         // Never closer than this
  float maxDistance = 600;         // Never farther than this

  // === ORBIT PARAMETERS ===
  float orbitAngle = 0;
  float orbitSpeed = 0.25;
  float orbitRadius = 300;
  float orbitHeight = -80;
  float orbitTilt = 0.15;

  // === FOLLOW/CHASE PARAMETERS ===
  PVector followOffset;
  float chaseDistance = 300;
  float chaseHeight = 80;

  // === 6DOF NOISE ===
  boolean noiseEnabled = true;
  float noiseFrequency = 0.12;
  float noiseAmplitude = 4.0;
  float noiseRotAmplitude = 0.01;
  PVector noiseSeed;

  // === INTERNAL STATE ===
  float internalTime = 0;

  // ============================================
  // CONSTRUCTOR
  // ============================================

  CinematicCamera() {
    position = new PVector(0, -100, -400);
    lookAt = new PVector(0, 0, 0);
    roll = 0;

    targetPosition = position.copy();
    targetLookAt = lookAt.copy();
    targetRoll = 0;

    velocity = new PVector(0, 0, 0);
    lookAtVelocity = new PVector(0, 0, 0);
    rollVelocity = 0;

    subject = new PVector(0, 0, 0);
    followOffset = new PVector(0, -80, -250);

    noiseSeed = new PVector(random(1000), random(1000), random(1000));
  }

  // ============================================
  // SIMPLE API - Set what to track
  // ============================================

  /**
   * Track a subject - camera will always keep it in frame
   * Call this every frame with the subject's current position
   */
  void trackSubject(PVector subjectPos) {
    // Smooth transition of subject position
    subject.x = lerp(subject.x, subjectPos.x, 0.1);
    subject.y = lerp(subject.y, subjectPos.y, 0.1);
    subject.z = lerp(subject.z, subjectPos.z, 0.1);
  }

  /**
   * Set orbit mode - camera orbits around subject
   */
  void setOrbit(float radius, float speed, float height) {
    mode = MODE_ORBIT;
    // Smooth transition of orbit parameters
    orbitRadius = lerp(orbitRadius, radius, 0.05);
    orbitSpeed = lerp(orbitSpeed, speed, 0.1);
    orbitHeight = lerp(orbitHeight, height, 0.05);
  }

  /**
   * Set follow mode - camera follows behind subject
   */
  void setFollow(PVector offset) {
    mode = MODE_FOLLOW;
    followOffset.x = lerp(followOffset.x, offset.x, 0.05);
    followOffset.y = lerp(followOffset.y, offset.y, 0.05);
    followOffset.z = lerp(followOffset.z, offset.z, 0.05);
  }

  /**
   * Set chase mode - camera chases subject from behind
   */
  void setChase(float distance, float height) {
    mode = MODE_CHASE;
    chaseDistance = lerp(chaseDistance, distance, 0.05);
    chaseHeight = lerp(chaseHeight, height, 0.05);
  }

  // ============================================
  // UPDATE - Call every frame
  // ============================================

  void update(float dt) {
    internalTime += dt;

    // Calculate target position based on current mode
    calculateTarget(dt);

    // Apply spring physics to move toward target (SMOOTH, no hard cuts)
    applySpringPhysics(dt);

    // Ensure we never lose the subject
    enforceVisibility();
  }

  void calculateTarget(float dt) {
    switch (mode) {
      case MODE_STATIC:
        // Target stays where it is
        break;

      case MODE_ORBIT:
        // Orbit around subject
        orbitAngle += orbitSpeed * dt;
        float ox = subject.x + cos(orbitAngle) * orbitRadius;
        float oz = subject.z + sin(orbitAngle) * orbitRadius;
        float oy = subject.y + orbitHeight + sin(internalTime * 0.2) * 20;

        targetPosition.set(ox, oy, oz);
        targetLookAt.set(subject.x, subject.y, subject.z);
        targetRoll = sin(orbitAngle) * orbitTilt * 0.3;
        break;

      case MODE_FOLLOW:
        // Follow with offset
        targetPosition.set(
          subject.x + followOffset.x,
          subject.y + followOffset.y,
          subject.z + followOffset.z
        );
        targetLookAt.set(subject.x, subject.y, subject.z);
        break;

      case MODE_CHASE:
        // Chase from behind
        targetPosition.set(
          subject.x,
          subject.y + chaseHeight,
          subject.z - chaseDistance
        );
        targetLookAt.set(subject.x, subject.y, subject.z);
        break;
    }
  }

  void applySpringPhysics(float dt) {
    // Position spring
    PVector posForce = PVector.sub(targetPosition, position);
    velocity.add(PVector.mult(posForce, positionStiffness));
    velocity.mult(pow(damping, 60 * dt));
    velocity.limit(maxSpeed);
    position.add(PVector.mult(velocity, dt));

    // Look-at spring (usually snappier to keep subject centered)
    PVector lookForce = PVector.sub(targetLookAt, lookAt);
    lookAtVelocity.add(PVector.mult(lookForce, lookAtStiffness));
    lookAtVelocity.mult(pow(damping, 60 * dt));
    lookAtVelocity.limit(maxSpeed);
    lookAt.add(PVector.mult(lookAtVelocity, dt));

    // Roll spring
    float rollForce = (targetRoll - roll) * positionStiffness;
    rollVelocity += rollForce * dt;
    rollVelocity *= pow(damping, 60 * dt);
    roll += rollVelocity;
  }

  void enforceVisibility() {
    // Ensure camera doesn't get too close or too far from subject
    float dist = PVector.dist(position, subject);

    if (dist < minDistance) {
      // Push camera away
      PVector away = PVector.sub(position, subject).normalize();
      position = PVector.add(subject, PVector.mult(away, minDistance));
    } else if (dist > maxDistance) {
      // Pull camera closer
      PVector toward = PVector.sub(subject, position).normalize();
      position.add(PVector.mult(toward, (dist - maxDistance) * 0.1));
    }

    // Ensure look-at is always on subject
    float lookDist = PVector.dist(lookAt, subject);
    if (lookDist > subjectRadius * 0.5) {
      lookAt = PVector.lerp(lookAt, subject, 0.1);
    }
  }

  // ============================================
  // NOISE
  // ============================================

  PVector getNoiseOffset() {
    float t = internalTime;
    float px = (noise(noiseSeed.x + t * noiseFrequency, 0) * 2 - 1) * noiseAmplitude;
    float py = (noise(noiseSeed.y + t * noiseFrequency, 100) * 2 - 1) * noiseAmplitude;
    float pz = (noise(noiseSeed.z + t * noiseFrequency, 200) * 2 - 1) * noiseAmplitude;

    // Add high-frequency detail
    px += (noise(noiseSeed.x + t * noiseFrequency * 3, 300) * 2 - 1) * noiseAmplitude * 0.25;
    py += (noise(noiseSeed.y + t * noiseFrequency * 3, 400) * 2 - 1) * noiseAmplitude * 0.25;

    return new PVector(px, py, pz);
  }

  float getNoiseRoll() {
    return (noise(noiseSeed.x + internalTime * noiseFrequency * 0.5, 600) * 2 - 1) * noiseRotAmplitude;
  }

  // ============================================
  // APPLY TO GRAPHICS
  // ============================================

  void apply(PGraphics pg) {
    PVector noiseOff = noiseEnabled ? getNoiseOffset() : new PVector(0, 0, 0);
    float noiseRoll = noiseEnabled ? getNoiseRoll() : 0;

    PVector finalPos = PVector.add(position, noiseOff);
    float finalRoll = roll + noiseRoll;

    pg.camera(
      finalPos.x, finalPos.y, finalPos.z,
      lookAt.x, lookAt.y, lookAt.z,
      sin(finalRoll), cos(finalRoll), 0
    );
  }

  // ============================================
  // CONFIGURATION
  // ============================================

  void setSpringParams(float posStiff, float damp) {
    this.positionStiffness = posStiff;
    this.damping = damp;
  }

  void setNoiseParams(float freq, float amp, float rotAmp) {
    this.noiseFrequency = freq;
    this.noiseAmplitude = amp;
    this.noiseRotAmplitude = rotAmp;
  }

  void setDistanceLimits(float min, float max, float ideal) {
    this.minDistance = min;
    this.maxDistance = max;
    this.idealDistance = ideal;
  }

  void setSubjectRadius(float r) {
    this.subjectRadius = r;
  }

  void reset() {
    velocity.set(0, 0, 0);
    lookAtVelocity.set(0, 0, 0);
    rollVelocity = 0;
    roll = 0;
    internalTime = 0;
    orbitAngle = random(TWO_PI);
  }

  // ============================================
  // GETTERS
  // ============================================

  PVector getPosition() {
    return noiseEnabled ? PVector.add(position, getNoiseOffset()) : position.copy();
  }

  PVector getLookAt() {
    return lookAt.copy();
  }

  float getDistanceToSubject() {
    return PVector.dist(position, subject);
  }
}
