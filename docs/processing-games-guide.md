# Processing VJ Games Development Guide

This guide covers how to create interactive VJ games and visuals using Processing (Java) with MIDI controller input from the Launchpad Mini Mk3.

## Prerequisites

- [Processing 4.x](https://processing.org/download)
- [The MidiBus library](http://www.smallbutdigital.com/projects/themidibus/)
- Launchpad Mini Mk3 in Programmer mode

## Installing The MidiBus

1. Open Processing
2. Go to **Sketch → Import Library → Manage Libraries**
3. Search for "The MidiBus"
4. Click **Install**

---

## Basic Structure

### Minimal MIDI Setup

```java
import themidibus.*;

MidiBus launchpad;

void setup() {
  size(800, 800);
  
  // List all available MIDI devices
  MidiBus.list();
  
  // Connect to Launchpad (use MIDI 2 port for Programmer mode)
  launchpad = new MidiBus(this, "Launchpad Mini MK3 MIDI 2", "Launchpad Mini MK3 MIDI 2");
  
  // Clear all pads at startup
  clearAllPads();
}

void draw() {
  background(0);
  // Your visual code here
}

void noteOn(int channel, int pitch, int velocity) {
  // Handle pad press
  println("Note On: " + pitch + " velocity: " + velocity);
}

void noteOff(int channel, int pitch, int velocity) {
  // Handle pad release
  println("Note Off: " + pitch);
}

void clearAllPads() {
  for (int row = 1; row <= 8; row++) {
    for (int col = 1; col <= 8; col++) {
      int note = row * 10 + col;
      launchpad.sendNoteOn(0, note, 0);
    }
  }
}
```

---

## Launchpad Grid Utilities

### Grid Coordinate System

```java
// Convert MIDI note to grid position (0-7, 0-7)
PVector noteToGrid(int note) {
  int col = (note % 10) - 1;
  int row = (note / 10) - 1;
  return new PVector(col, row);
}

// Convert grid position to MIDI note
int gridToNote(int col, int row) {
  return (row + 1) * 10 + (col + 1);
}

// Check if note is a valid pad (not scene launch button)
boolean isValidPad(int note) {
  int col = note % 10;
  int row = note / 10;
  return col >= 1 && col <= 8 && row >= 1 && row <= 8;
}
```

### LED Control

```java
// Launchpad color palette (simplified)
final int COLOR_OFF = 0;
final int COLOR_RED = 5;
final int COLOR_ORANGE = 9;
final int COLOR_YELLOW = 13;
final int COLOR_GREEN = 21;
final int COLOR_CYAN = 37;
final int COLOR_BLUE = 45;
final int COLOR_PURPLE = 53;
final int COLOR_PINK = 57;
final int COLOR_WHITE = 3;

void lightPad(int col, int row, int colorIndex) {
  int note = gridToNote(col, row);
  launchpad.sendNoteOn(0, note, colorIndex);
}

void clearPad(int col, int row) {
  lightPad(col, row, COLOR_OFF);
}

void lightAllPads(int colorIndex) {
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      lightPad(col, row, colorIndex);
    }
  }
}
```

---

## Example Games

### 1. Whack-a-Mole

A simple reaction game where pads light up and players must hit them quickly.

```java
import themidibus.*;

MidiBus launchpad;
int targetCol = -1, targetRow = -1;
int score = 0;
int lastSpawnTime = 0;
int spawnInterval = 1000; // ms

void setup() {
  size(800, 800);
  textSize(48);
  textAlign(CENTER, CENTER);
  
  MidiBus.list();
  launchpad = new MidiBus(this, "Launchpad Mini MK3 MIDI 2", "Launchpad Mini MK3 MIDI 2");
  
  clearAllPads();
  spawnTarget();
}

void draw() {
  background(0);
  
  // Draw score
  fill(255);
  text("Score: " + score, width/2, 50);
  
  // Draw grid representation
  drawGrid();
  
  // Spawn new target periodically
  if (millis() - lastSpawnTime > spawnInterval) {
    clearTarget();
    spawnTarget();
  }
}

void drawGrid() {
  float cellSize = 80;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = 100;
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      float x = offsetX + col * cellSize;
      float y = offsetY + (7 - row) * cellSize; // Flip Y to match Launchpad
      
      if (col == targetCol && row == targetRow) {
        fill(0, 255, 0);
      } else {
        fill(50);
      }
      stroke(100);
      rect(x, y, cellSize - 2, cellSize - 2);
    }
  }
}

void spawnTarget() {
  targetCol = (int)random(8);
  targetRow = (int)random(8);
  lightPad(targetCol, targetRow, 21); // Green
  lastSpawnTime = millis();
}

void clearTarget() {
  if (targetCol >= 0 && targetRow >= 0) {
    clearPad(targetCol, targetRow);
  }
}

void noteOn(int channel, int pitch, int velocity) {
  if (!isValidPad(pitch)) return;
  
  PVector pos = noteToGrid(pitch);
  int col = (int)pos.x;
  int row = (int)pos.y;
  
  if (col == targetCol && row == targetRow) {
    // Hit!
    score++;
    lightPad(col, row, 5); // Flash red
    delay(100);
    clearPad(col, row);
    spawnTarget();
    
    // Speed up as score increases
    spawnInterval = max(300, 1000 - score * 50);
  } else {
    // Miss - flash red
    lightPad(col, row, 5);
    delay(50);
    clearPad(col, row);
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
  int note = gridToNote(col, row);
  launchpad.sendNoteOn(0, note, colorIndex);
}

void clearPad(int col, int row) {
  lightPad(col, row, 0);
}

void clearAllPads() {
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      clearPad(col, row);
    }
  }
}
```

### 2. Snake Game

Classic snake game on the Launchpad grid.

```java
import themidibus.*;
import java.util.LinkedList;

MidiBus launchpad;

LinkedList<PVector> snake = new LinkedList<PVector>();
PVector food;
PVector direction = new PVector(1, 0);
PVector nextDirection = new PVector(1, 0);
int lastMoveTime = 0;
int moveInterval = 300;
boolean gameOver = false;
int score = 0;

void setup() {
  size(800, 800);
  textSize(32);
  textAlign(CENTER, CENTER);
  
  MidiBus.list();
  launchpad = new MidiBus(this, "Launchpad Mini MK3 MIDI 2", "Launchpad Mini MK3 MIDI 2");
  
  resetGame();
}

void resetGame() {
  snake.clear();
  snake.add(new PVector(4, 4));
  snake.add(new PVector(3, 4));
  snake.add(new PVector(2, 4));
  
  direction = new PVector(1, 0);
  nextDirection = new PVector(1, 0);
  gameOver = false;
  score = 0;
  
  spawnFood();
  updateLaunchpad();
}

void draw() {
  background(0);
  
  if (gameOver) {
    fill(255, 0, 0);
    text("GAME OVER", width/2, height/2 - 30);
    text("Score: " + score, width/2, height/2 + 30);
    text("Press any pad to restart", width/2, height/2 + 90);
    return;
  }
  
  // Move snake
  if (millis() - lastMoveTime > moveInterval) {
    direction = nextDirection.copy();
    moveSnake();
    lastMoveTime = millis();
  }
  
  // Draw grid on screen
  drawGrid();
  
  fill(255);
  text("Score: " + score, width/2, 30);
}

void moveSnake() {
  PVector head = snake.getFirst().copy();
  head.add(direction);
  
  // Wrap around
  if (head.x < 0) head.x = 7;
  if (head.x > 7) head.x = 0;
  if (head.y < 0) head.y = 7;
  if (head.y > 7) head.y = 0;
  
  // Check collision with self
  for (PVector segment : snake) {
    if (segment.x == head.x && segment.y == head.y) {
      gameOver = true;
      flashGameOver();
      return;
    }
  }
  
  snake.addFirst(head);
  
  // Check food
  if (head.x == food.x && head.y == food.y) {
    score++;
    spawnFood();
    // Speed up
    moveInterval = max(100, 300 - score * 10);
  } else {
    snake.removeLast();
  }
  
  updateLaunchpad();
}

void spawnFood() {
  do {
    food = new PVector((int)random(8), (int)random(8));
  } while (isSnakePosition(food));
}

boolean isSnakePosition(PVector pos) {
  for (PVector segment : snake) {
    if (segment.x == pos.x && segment.y == pos.y) {
      return true;
    }
  }
  return false;
}

void updateLaunchpad() {
  // Clear all
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      lightPad(col, row, 0);
    }
  }
  
  // Draw snake (green, head brighter)
  boolean first = true;
  for (PVector segment : snake) {
    lightPad((int)segment.x, (int)segment.y, first ? 21 : 19);
    first = false;
  }
  
  // Draw food (red pulsing)
  lightPad((int)food.x, (int)food.y, 5);
}

void flashGameOver() {
  // Flash red
  for (int i = 0; i < 3; i++) {
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        lightPad(col, row, 5);
      }
    }
    delay(200);
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        lightPad(col, row, 0);
      }
    }
    delay(200);
  }
}

void noteOn(int channel, int pitch, int velocity) {
  if (!isValidPad(pitch)) return;
  
  if (gameOver) {
    resetGame();
    return;
  }
  
  PVector pos = noteToGrid(pitch);
  PVector head = snake.getFirst();
  
  // Determine direction based on pad pressed relative to head
  // Use scene launch buttons for direction, or pads in cardinal directions
  
  // Simple: use quadrant of pressed pad relative to head
  float dx = pos.x - head.x;
  float dy = pos.y - head.y;
  
  if (abs(dx) > abs(dy)) {
    // Horizontal movement
    if (dx > 0 && direction.x != -1) {
      nextDirection = new PVector(1, 0);
    } else if (dx < 0 && direction.x != 1) {
      nextDirection = new PVector(-1, 0);
    }
  } else {
    // Vertical movement
    if (dy > 0 && direction.y != -1) {
      nextDirection = new PVector(0, 1);
    } else if (dy < 0 && direction.y != 1) {
      nextDirection = new PVector(0, -1);
    }
  }
}

void drawGrid() {
  float cellSize = 80;
  float offsetX = (width - cellSize * 8) / 2;
  float offsetY = 80;
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      float x = offsetX + col * cellSize;
      float y = offsetY + (7 - row) * cellSize;
      
      fill(30);
      stroke(60);
      
      // Check if snake
      for (int i = 0; i < snake.size(); i++) {
        PVector seg = snake.get(i);
        if ((int)seg.x == col && (int)seg.y == row) {
          fill(i == 0 ? color(0, 200, 0) : color(0, 150, 0));
          break;
        }
      }
      
      // Check if food
      if ((int)food.x == col && (int)food.y == row) {
        fill(255, 0, 0);
      }
      
      rect(x, y, cellSize - 2, cellSize - 2);
    }
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
  int note = gridToNote(col, row);
  launchpad.sendNoteOn(0, note, colorIndex);
}
```

### 3. Simon Says (Memory Game)

```java
import themidibus.*;
import java.util.ArrayList;

MidiBus launchpad;

ArrayList<Integer> sequence = new ArrayList<Integer>();
int playerIndex = 0;
boolean playerTurn = false;
boolean gameOver = false;
int score = 0;

// Define 4 quadrants with colors
int[][] quadrants = {
  {0, 0, 3, 3},  // Top-left (cols 0-3, rows 4-7)
  {4, 0, 7, 3},  // Top-right
  {0, 4, 3, 7},  // Bottom-left
  {4, 4, 7, 7}   // Bottom-right
};

int[] quadrantColors = {5, 13, 21, 45}; // Red, Yellow, Green, Blue
int[] quadrantDimColors = {1, 9, 17, 41}; // Dim versions

void setup() {
  size(800, 800);
  textSize(32);
  textAlign(CENTER, CENTER);
  
  MidiBus.list();
  launchpad = new MidiBus(this, "Launchpad Mini MK3 MIDI 2", "Launchpad Mini MK3 MIDI 2");
  
  startNewGame();
}

void startNewGame() {
  sequence.clear();
  playerIndex = 0;
  playerTurn = false;
  gameOver = false;
  score = 0;
  
  showQuadrants();
  delay(500);
  addToSequence();
}

void showQuadrants() {
  clearAllPads();
  for (int q = 0; q < 4; q++) {
    lightQuadrant(q, quadrantDimColors[q]);
  }
}

void lightQuadrant(int q, int color) {
  int[] bounds = quadrants[q];
  for (int col = bounds[0]; col <= bounds[2]; col++) {
    for (int row = bounds[1]; row <= bounds[3]; row++) {
      lightPad(col, row, color);
    }
  }
}

void flashQuadrant(int q) {
  lightQuadrant(q, quadrantColors[q]);
  delay(400);
  lightQuadrant(q, quadrantDimColors[q]);
  delay(200);
}

void addToSequence() {
  sequence.add((int)random(4));
  playSequence();
}

void playSequence() {
  playerTurn = false;
  
  // Clear and wait
  showQuadrants();
  delay(500);
  
  // Play each step
  for (int step : sequence) {
    flashQuadrant(step);
  }
  
  // Player's turn
  playerTurn = true;
  playerIndex = 0;
}

int getQuadrant(int col, int row) {
  for (int q = 0; q < 4; q++) {
    int[] bounds = quadrants[q];
    if (col >= bounds[0] && col <= bounds[2] && 
        row >= bounds[1] && row <= bounds[3]) {
      return q;
    }
  }
  return -1;
}

void noteOn(int channel, int pitch, int velocity) {
  if (!isValidPad(pitch)) return;
  
  if (gameOver) {
    startNewGame();
    return;
  }
  
  if (!playerTurn) return;
  
  PVector pos = noteToGrid(pitch);
  int q = getQuadrant((int)pos.x, (int)pos.y);
  
  if (q < 0) return;
  
  // Flash the pressed quadrant
  lightQuadrant(q, quadrantColors[q]);
  
  // Check if correct
  if (q == sequence.get(playerIndex)) {
    playerIndex++;
    
    if (playerIndex >= sequence.size()) {
      // Completed sequence!
      score++;
      delay(300);
      showQuadrants();
      delay(500);
      addToSequence();
    } else {
      delay(200);
      lightQuadrant(q, quadrantDimColors[q]);
    }
  } else {
    // Wrong!
    gameOver = true;
    flashGameOver();
  }
}

void flashGameOver() {
  for (int i = 0; i < 3; i++) {
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        lightPad(col, row, 5);
      }
    }
    delay(200);
    clearAllPads();
    delay(200);
  }
}

void draw() {
  background(0);
  
  if (gameOver) {
    fill(255, 0, 0);
    text("GAME OVER!", width/2, height/2 - 30);
    text("Score: " + score, width/2, height/2 + 30);
    text("Press any pad to restart", width/2, height/2 + 90);
  } else {
    fill(255);
    text("Score: " + score, width/2, 30);
    
    if (playerTurn) {
      text("Your turn! Repeat the sequence", width/2, height - 30);
    } else {
      text("Watch the sequence...", width/2, height - 30);
    }
  }
  
  drawQuadrants();
}

void drawQuadrants() {
  float size = 300;
  float gap = 20;
  float startX = (width - size * 2 - gap) / 2;
  float startY = 80;
  
  color[] colors = {color(255, 0, 0), color(255, 255, 0), color(0, 255, 0), color(0, 0, 255)};
  
  for (int q = 0; q < 4; q++) {
    int col = q % 2;
    int row = q / 2;
    float x = startX + col * (size + gap);
    float y = startY + row * (size + gap);
    
    fill(red(colors[q])/3, green(colors[q])/3, blue(colors[q])/3);
    stroke(colors[q]);
    strokeWeight(3);
    rect(x, y, size, size, 20);
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
  int note = gridToNote(col, row);
  launchpad.sendNoteOn(0, note, colorIndex);
}

void clearAllPads() {
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      lightPad(col, row, 0);
    }
  }
}
```

---

## Advanced Techniques

### Animation Loops

```java
// Animated rainbow wave
void animateRainbow() {
  int offset = (millis() / 100) % 64;
  
  for (int row = 0; row < 8; row++) {
    for (int col = 0; col < 8; col++) {
      int colorIndex = ((col + row + offset) % 8) * 8;
      lightPad(col, row, colorIndex);
    }
  }
}
```

### Visual Effects Synchronized to Pads

```java
// Visual ripple effect from pad press
ArrayList<Ripple> ripples = new ArrayList<Ripple>();

class Ripple {
  float x, y, radius, maxRadius;
  color c;
  
  Ripple(float x, float y) {
    this.x = x;
    this.y = y;
    this.radius = 0;
    this.maxRadius = 400;
    this.c = color(random(255), random(255), random(255));
  }
  
  void update() {
    radius += 5;
  }
  
  void display() {
    noFill();
    stroke(c, map(radius, 0, maxRadius, 255, 0));
    strokeWeight(3);
    ellipse(x, y, radius * 2, radius * 2);
  }
  
  boolean isDead() {
    return radius > maxRadius;
  }
}

void noteOn(int channel, int pitch, int velocity) {
  if (!isValidPad(pitch)) return;
  
  PVector pos = noteToGrid(pitch);
  // Convert grid to screen position
  float x = map(pos.x, 0, 7, 100, width - 100);
  float y = map(7 - pos.y, 0, 7, 100, height - 100);
  
  ripples.add(new Ripple(x, y));
  
  // Light the pad
  lightPad((int)pos.x, (int)pos.y, (int)random(1, 64));
}

void draw() {
  background(0, 20);
  
  for (int i = ripples.size() - 1; i >= 0; i--) {
    Ripple r = ripples.get(i);
    r.update();
    r.display();
    if (r.isDead()) {
      ripples.remove(i);
    }
  }
}
```

### Integrating with MIDImix

```java
// Use MIDImix controls to affect game parameters
float gameSpeed = 1.0;
float colorIntensity = 1.0;

void controllerChange(int channel, int number, int value) {
  // Fader 1: game speed
  if (number == 20) {
    gameSpeed = map(value, 0, 127, 0.5, 2.0);
  }
  
  // Knob 1: color intensity
  if (number == 28) {
    colorIntensity = map(value, 0, 127, 0.2, 1.0);
  }
}

void draw() {
  // Apply gameSpeed to timing
  moveInterval = (int)(300 / gameSpeed);
  
  // Apply colorIntensity to visuals
  fill(255 * colorIntensity);
}
```

---

## Best Practices

### 1. Separate MIDI Logic from Game Logic
Keep MIDI handling clean and delegate to game methods.

### 2. Handle MIDI Disconnects
Check for MIDI availability and provide fallback input (keyboard).

```java
void keyPressed() {
  // Fallback controls when Launchpad unavailable
  if (key == 'w') nextDirection = new PVector(0, 1);
  if (key == 's') nextDirection = new PVector(0, -1);
  if (key == 'a') nextDirection = new PVector(-1, 0);
  if (key == 'd') nextDirection = new PVector(1, 0);
}
```

### 3. Visual Feedback
Always show the game state on screen, not just on the Launchpad.

### 4. Pad Release Events
Use `noteOff` for games requiring hold/release mechanics.

### 5. Performance
Avoid sending too many MIDI messages per frame. Batch LED updates when possible.

---

## Resources

- [Processing Reference](https://processing.org/reference/)
- [The MidiBus Documentation](http://www.smallbutdigital.com/projects/themidibus/)
- [Launchpad Mini Mk3 Programmer's Reference](https://novationmusic.com/)
- [Processing Sound Library](https://processing.org/reference/libraries/sound/) - For audio integration
