/**
 * CrowdBattle - Multi-Agent Crowd Simulation
 * 
 * A chaotic crowd simulation where hundreds of agents fight each other.
 * Drop bombs using the Launchpad to eliminate them - but they learn to avoid!
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - The MidiBus library
 * - Syphon library (for video output)
 * - Launchpad Mini Mk3 in Programmer mode (optional)
 * 
 * Controls:
 * - Press pads to drop bombs at grid locations (Launchpad)
 * - Click grid to drop bombs (mouse fallback)
 * - Press 'R' to reset simulation
 * - Press 'S' to spawn more agents
 * - Press '+'/'-' to adjust spawn rate
 * 
 * Gameplay:
 * - Agents fight each other when they collide
 * - Bombs eliminate agents in blast radius
 * - Agents learn to avoid areas where bombs were dropped
 * - Chaos escalates as agents become more aggressive when cornered
 * 
 * Syphon Output:
 * - Broadcasts as "CrowdBattle" server at 1920x1080
 * - Receivable in Synesthesia, Magic, VPT, etc.
 */

import themidibus.*;
import codeanticode.syphon.*;
import java.util.ArrayList;

MidiBus launchpad;
SyphonServer syphon;
boolean hasLaunchpad = false;

// Agents
ArrayList<Agent> agents = new ArrayList<Agent>();
int maxAgents = 400;
int spawnRate = 3;  // agents per second
float lastSpawnTime = 0;

// Bombs and explosions
ArrayList<Bomb> bombs = new ArrayList<Bomb>();
ArrayList<Explosion> explosions = new ArrayList<Explosion>();

// Danger zones - agents learn to avoid these
float[][] dangerMap = new float[8][8];  // Heat map of dangerous areas
float dangerDecay = 0.995f;  // How fast danger fades

// Game state
int killCount = 0;
int fightCount = 0;
float chaosLevel = 0;  // 0-1, increases as more fighting happens

// Launchpad color palette
final int LP_OFF = 0;
final int LP_RED = 5;
final int LP_ORANGE = 9;
final int LP_YELLOW = 13;
final int LP_GREEN = 21;
final int LP_CYAN = 37;
final int LP_BLUE = 45;
final int LP_PURPLE = 53;
final int LP_PINK = 57;
final int LP_WHITE = 3;
final int LP_RED_DIM = 1;
final int LP_GREEN_DIM = 17;

void settings() {
  size(1920, 1080, P3D);  // Full HD for VJ output, P3D required for Syphon
}

void setup() {
  colorMode(HSB, 360, 100, 100);
  
  // Initialize Syphon server
  syphon = new SyphonServer(this, "CrowdBattle");
  
  // Try to find and connect to Launchpad
  initMidi();
  
  clearAllPads();
  initSimulation();
}

void initMidi() {
  MidiBus.list();
  
  String[] inputs = MidiBus.availableInputs();
  String[] outputs = MidiBus.availableOutputs();
  
  String launchpadIn = null;
  String launchpadOut = null;
  
  // Scan for Launchpad device
  for (String dev : inputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadIn = dev;
      break;
    }
  }
  for (String dev : outputs) {
    if (dev != null && dev.toLowerCase().contains("launchpad")) {
      launchpadOut = dev;
      break;
    }
  }
  
  // Connect if found
  if (launchpadIn != null && launchpadOut != null) {
    try {
      launchpad = new MidiBus(this, launchpadIn, launchpadOut);
      hasLaunchpad = true;
      println("Launchpad connected: " + launchpadIn);
    } catch (Exception e) {
      println("Failed to connect to Launchpad: " + e.getMessage());
      hasLaunchpad = false;
    }
  } else {
    println("No Launchpad found - using mouse/keyboard controls");
    hasLaunchpad = false;
  }
}

void initSimulation() {
  agents.clear();
  bombs.clear();
  explosions.clear();
  killCount = 0;
  fightCount = 0;
  chaosLevel = 0;
  
  // Clear danger map
  for (int c = 0; c < 8; c++) {
    for (int r = 0; r < 8; r++) {
      dangerMap[c][r] = 0;
    }
  }
  
  // Spawn initial agents
  for (int i = 0; i < 100; i++) {
    spawnAgent();
  }
}

void spawnAgent() {
  if (agents.size() >= maxAgents) return;
  
  // Spawn from edges
  float x, y;
  int edge = (int)random(4);
  switch(edge) {
    case 0: x = random(width); y = -20; break;
    case 1: x = random(width); y = height + 20; break;
    case 2: x = -20; y = random(height); break;
    default: x = width + 20; y = random(height); break;
  }
  
  agents.add(new Agent(x, y));
}

void draw() {
  // Dark background with slight fade for trails
  fill(0, 0, 0, 30);
  rect(0, 0, width, height);
  
  // Spawn new agents based on rate
  if (millis() - lastSpawnTime > 1000.0f / spawnRate) {
    spawnAgent();
    lastSpawnTime = millis();
  }
  
  // Update chaos level based on fighting
  chaosLevel = constrain(chaosLevel + fightCount * 0.001f - 0.0005f, 0, 1);
  fightCount = 0;  // Reset counter each frame
  
  // Decay danger map
  for (int c = 0; c < 8; c++) {
    for (int r = 0; r < 8; r++) {
      dangerMap[c][r] *= dangerDecay;
    }
  }
  
  // Draw danger zones (faintly)
  drawDangerZones();
  
  // Update and draw bombs
  for (int i = bombs.size() - 1; i >= 0; i--) {
    Bomb b = bombs.get(i);
    b.update();
    b.display();
    
    if (b.exploded) {
      // Create explosion
      explosions.add(new Explosion(b.x, b.y, b.radius));
      
      // Mark danger zone
      int gridCol = constrain((int)(b.x / (width / 8.0f)), 0, 7);
      int gridRow = constrain((int)(b.y / (height / 8.0f)), 0, 7);
      // Mark surrounding cells too
      for (int dc = -1; dc <= 1; dc++) {
        for (int dr = -1; dr <= 1; dr++) {
          int c = gridCol + dc;
          int r = gridRow + dr;
          if (c >= 0 && c < 8 && r >= 0 && r < 8) {
            dangerMap[c][r] = min(1.0f, dangerMap[c][r] + 0.8f);
          }
        }
      }
      
      // Kill agents in blast radius
      for (int j = agents.size() - 1; j >= 0; j--) {
        Agent a = agents.get(j);
        float d = dist(a.x, a.y, b.x, b.y);
        if (d < b.radius) {
          agents.remove(j);
          killCount++;
        }
      }
      
      bombs.remove(i);
    }
  }
  
  // Update and draw explosions
  for (int i = explosions.size() - 1; i >= 0; i--) {
    Explosion e = explosions.get(i);
    e.update();
    e.display();
    if (e.isDead()) {
      explosions.remove(i);
    }
  }
  
  // Update and draw agents
  for (int i = agents.size() - 1; i >= 0; i--) {
    Agent a = agents.get(i);
    a.update(agents, dangerMap);
    a.display();
    
    if (a.isDead()) {
      agents.remove(i);
    }
  }
  
  // Check for fights
  checkFights();
  
  // Update Launchpad display
  updateLaunchpad();
  
  // Draw UI
  drawUI();
  
  // Send frame to Syphon
  syphon.sendScreen();
}

void checkFights() {
  // Check for collisions between agents
  for (int i = 0; i < agents.size(); i++) {
    Agent a = agents.get(i);
    if (a.isDead()) continue;
    
    for (int j = i + 1; j < agents.size(); j++) {
      Agent b = agents.get(j);
      if (b.isDead()) continue;
      
      float d = dist(a.x, a.y, b.x, b.y);
      if (d < a.size + b.size) {
        // Fight!
        a.fight(b);
        fightCount++;
      }
    }
  }
}

void drawDangerZones() {
  noStroke();
  float cellW = width / 8.0f;
  float cellH = height / 8.0f;
  
  for (int c = 0; c < 8; c++) {
    for (int r = 0; r < 8; r++) {
      if (dangerMap[c][r] > 0.01f) {
        float alpha = dangerMap[c][r] * 30;
        fill(0, 100, 100, alpha);  // Red danger zones
        rect(c * cellW, r * cellH, cellW, cellH);
      }
    }
  }
}

void updateLaunchpad() {
  if (!hasLaunchpad || launchpad == null) return;
  
  float cellW = width / 8.0f;
  float cellH = height / 8.0f;
  
  for (int col = 0; col < 8; col++) {
    for (int row = 0; row < 8; row++) {
      // Count agents in this cell
      int count = 0;
      float cx = col * cellW;
      float cy = row * cellH;
      
      for (Agent a : agents) {
        if (a.x >= cx && a.x < cx + cellW && a.y >= cy && a.y < cy + cellH) {
          count++;
        }
      }
      
      // Determine color based on count and danger
      int colorIndex;
      if (dangerMap[col][7-row] > 0.5f) {
        // High danger - red pulsing
        colorIndex = (frameCount % 20 < 10) ? LP_RED : LP_RED_DIM;
      } else if (count > 20) {
        colorIndex = LP_RED;  // Overcrowded
      } else if (count > 10) {
        colorIndex = LP_ORANGE;
      } else if (count > 5) {
        colorIndex = LP_YELLOW;
      } else if (count > 0) {
        colorIndex = LP_GREEN_DIM;
      } else {
        colorIndex = LP_OFF;
      }
      
      lightPad(col, 7-row, colorIndex);  // Flip Y for Launchpad
    }
  }
}

void drawUI() {
  // Semi-transparent UI background
  fill(0, 0, 0, 70);
  noStroke();
  rect(10, 10, 300, 180, 10);
  
  fill(0, 0, 100);
  textAlign(LEFT, TOP);
  textSize(28);
  text("CROWD BATTLE", 25, 20);
  
  textSize(18);
  fill(0, 0, 80);
  text("Agents: " + agents.size() + "/" + maxAgents, 25, 55);
  text("Kills: " + killCount, 25, 80);
  text("Spawn Rate: " + spawnRate + "/sec", 25, 105);
  
  // Chaos meter
  text("Chaos:", 25, 135);
  fill(0, 0, 40);
  rect(90, 138, 150, 16, 3);
  fill(lerp(120, 0, chaosLevel), 100, 100);  // Green to red
  rect(90, 138, 150 * chaosLevel, 16, 3);
  
  // Controller status
  fill(hasLaunchpad ? color(120, 80, 100) : color(40, 80, 100));
  text(hasLaunchpad ? "Launchpad: Connected" : "Mouse Mode", 25, 162);
  
  // Instructions
  fill(0, 0, 60);
  textSize(14);
  textAlign(CENTER, BOTTOM);
  text("Click/Tap grid to drop bombs | R: Reset | S: Spawn | +/-: Rate", width/2, height - 15);
}

void dropBomb(int gridCol, int gridRow) {
  float cellW = width / 8.0f;
  float cellH = height / 8.0f;
  
  float x = gridCol * cellW + cellW / 2;
  float y = (7 - gridRow) * cellH + cellH / 2;  // Flip Y to match Launchpad
  
  bombs.add(new Bomb(x, y));
  
  // Flash the pad
  lightPad(gridCol, gridRow, LP_WHITE);
}

// MIDI callbacks
void noteOn(int channel, int pitch, int velocity) {
  if (!isValidPad(pitch)) return;
  
  PVector pos = noteToGrid(pitch);
  int col = (int)pos.x;
  int row = (int)pos.y;
  
  dropBomb(col, row);
}

void noteOff(int channel, int pitch, int velocity) {
  // Not used
}

// Mouse fallback
void mousePressed() {
  float cellW = width / 8.0f;
  float cellH = height / 8.0f;
  
  int col = (int)(mouseX / cellW);
  int row = 7 - (int)(mouseY / cellH);  // Flip Y
  
  if (col >= 0 && col < 8 && row >= 0 && row < 8) {
    dropBomb(col, row);
  }
}

void keyPressed() {
  if (key == 'r' || key == 'R') {
    initSimulation();
  } else if (key == 's' || key == 'S') {
    for (int i = 0; i < 20; i++) {
      spawnAgent();
    }
  } else if (key == '+' || key == '=') {
    spawnRate = min(20, spawnRate + 1);
  } else if (key == '-' || key == '_') {
    spawnRate = max(1, spawnRate - 1);
  }
}

// Utility functions
PVector noteToGrid(int note) {
  int col = (note % 10) - 1;
  int row = (note / 10) - 1;
  return new PVector(col, row);
}

int gridToNote(int col, int row) {
  return (row + 1) * 10 + (col + 1);
}

boolean isValidPad(int note) {
  int col = note % 10;
  int row = note / 10;
  return col >= 1 && col <= 8 && row >= 1 && row <= 8;
}

void lightPad(int col, int row, int colorIndex) {
  if (!hasLaunchpad || launchpad == null) return;
  int note = gridToNote(col, row);
  launchpad.sendNoteOn(0, note, colorIndex);
}

void clearPad(int col, int row) {
  lightPad(col, row, LP_OFF);
}

void clearAllPads() {
  if (!hasLaunchpad || launchpad == null) return;
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      clearPad(col, row);
    }
  }
}

void exit() {
  clearAllPads();
  super.exit();
}
