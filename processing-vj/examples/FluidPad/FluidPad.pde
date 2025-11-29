/**
 * FluidPad - GPU Fluid Simulation with Launchpad Control
 * 
 * Tap pads on the Launchpad to inject colorful fluid into a GPU-accelerated
 * 2D fluid simulation. Each grid position injects fluid with velocity based
 * on its location from center.
 * 
 * Requirements:
 * - Processing 4.x (Intel/x64 build for Apple Silicon)
 * - PixelFlow library (GPU fluid simulation)
 * - The MidiBus library
 * - Syphon library (for video output)
 * - Launchpad Mini Mk3 in Programmer mode (optional)
 * 
 * Controls:
 * - Tap pads to inject fluid at grid positions
 * - Scene button 1: Cycle color palette
 * - Scene button 2: Toggle vorticity (swirl effect)
 * - Scene button 3: Reset fluid
 * - Scene button 4: Toggle density rendering mode
 * - Mouse click: Inject fluid (fallback)
 * - Mouse drag: Inject fluid with velocity
 * - 'R': Reset fluid
 * - 'C': Cycle colors
 * - '1-4': Toggle rendering modes
 * 
 * Syphon Output:
 * - Broadcasts as "FluidPad" server at 1280x720
 */

import themidibus.*;
import codeanticode.syphon.*;
import com.thomasdiewald.pixelflow.java.DwPixelFlow;
import com.thomasdiewald.pixelflow.java.fluid.DwFluid2D;
import processing.opengl.PGraphics2D;

// MIDI
MidiBus launchpad;
boolean hasLaunchpad = false;

// Syphon
SyphonServer syphon;

// PixelFlow Fluid
DwPixelFlow context;
DwFluid2D fluid;
PGraphics2D pg_fluid;

// Color palettes
int paletteIndex = 0;
float[][] palettes = {
  {0, 0.3f, 1.0f},      // Cyan-blue
  {1.0f, 0.2f, 0.0f},   // Orange-red
  {0.0f, 1.0f, 0.3f},   // Green
  {0.8f, 0.0f, 1.0f},   // Purple
  {1.0f, 0.8f, 0.0f},   // Yellow
  {1.0f, 0.0f, 0.5f}    // Pink
};

// Visual settings
boolean highVorticity = true;
int displayMode = 0;  // 0=density, 1=velocity, 2=pressure

// Launchpad colors
final int LP_OFF = 0;
final int LP_WHITE = 3;
final int LP_RED = 5;
final int LP_ORANGE = 9;
final int LP_YELLOW = 13;
final int LP_GREEN = 21;
final int LP_CYAN = 37;
final int LP_BLUE = 45;
final int LP_PURPLE = 53;
final int LP_PINK = 57;

// Grid to color mapping
int[][] gridColors = new int[8][8];

// Fluid settings
int fluidScale = 1;  // Grid scale (1 = full resolution)

// Injection queue (pad presses inject over multiple frames for smoother effect)
ArrayList<FluidInjection> injections = new ArrayList<FluidInjection>();

void settings() {
  size(800, 800, P2D);  // Square for easier grid mapping
  PJOGL.profile = 3;     // OpenGL 3+ for PixelFlow
}

void setup() {
  // Initialize Syphon
  syphon = new SyphonServer(this, "FluidPad");
  
  // Initialize MIDI
  initMidi();
  
  // Initialize PixelFlow context
  context = new DwPixelFlow(this);
  context.print();
  context.printGL();
  
  // Create fluid simulation - fluidScale is the grid cell size
  fluid = new DwFluid2D(context, width, height, fluidScale);
  
  // Fluid parameters - match the working example
  fluid.param.dissipation_velocity = 0.70f;
  fluid.param.dissipation_density  = 0.99f;
  fluid.param.vorticity = highVorticity ? 0.50f : 0.05f;
  
  // Create render target
  pg_fluid = (PGraphics2D) createGraphics(width, height, P2D);
  pg_fluid.smooth(4);
  
  // Initialize grid colors based on palette
  updateGridColors();
  
  // Add fluid data callback - this runs each frame before fluid.update()
  fluid.addCallback_FluiData(new DwFluid2D.FluidData() {
    public void update(DwFluid2D fluid) {
      // Process injection queue
      for (int i = injections.size() - 1; i >= 0; i--) {
        FluidInjection inj = injections.get(i);
        inj.apply(fluid);
        if (inj.isDone()) {
          injections.remove(i);
        }
      }
      
      // Mouse injection - use screen coordinates directly
      if (mousePressed && mouseButton == LEFT) {
        float px = mouseX;
        float py = height - mouseY;  // PixelFlow Y is flipped
        float vx = (mouseX - pmouseX) * 15;
        float vy = (mouseY - pmouseY) * -15;
        
        float[] col = palettes[paletteIndex];
        fluid.addVelocity(px, py, 14, vx, vy);
        fluid.addDensity(px, py, 20, col[0], col[1], col[2], 1.0f);
        fluid.addDensity(px, py, 8, 1.0f, 1.0f, 1.0f, 1.0f);  // White core
      }
    }
  });
  
  println("FluidPad initialized - tap Launchpad pads to inject fluid!");
}

void initMidi() {
  MidiBus.list();
  
  String[] inputs = MidiBus.availableInputs();
  String[] outputs = MidiBus.availableOutputs();
  
  String launchpadIn = null;
  String launchpadOut = null;
  
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
  
  if (launchpadIn != null && launchpadOut != null) {
    try {
      launchpad = new MidiBus(this, launchpadIn, launchpadOut);
      hasLaunchpad = true;
      println("Launchpad connected: " + launchpadIn);
      updateLaunchpadDisplay();
    } catch (Exception e) {
      println("Failed to connect to Launchpad: " + e.getMessage());
      hasLaunchpad = false;
    }
  } else {
    println("No Launchpad found - using mouse controls");
    hasLaunchpad = false;
  }
}

void draw() {
  // Update fluid simulation
  fluid.update();
  
  // Render fluid
  pg_fluid.beginDraw();
  pg_fluid.background(0);
  pg_fluid.endDraw();
  
  // Render based on display mode
  fluid.renderFluidTextures(pg_fluid, displayMode);
  
  // Draw to screen
  image(pg_fluid, 0, 0);
  
  // Overlay grid hint (faint)
  drawGridOverlay();
  
  // Draw UI
  drawUI();
  
  // Send to Syphon
  syphon.sendScreen();
}

void drawGridOverlay() {
  float cellW = width / 8.0f;
  float cellH = height / 8.0f;
  
  stroke(255, 20);
  strokeWeight(1);
  noFill();
  
  for (int i = 1; i < 8; i++) {
    line(i * cellW, 0, i * cellW, height);
    line(0, i * cellH, width, i * cellH);
  }
}

void drawUI() {
  fill(255, 200);
  textAlign(LEFT, TOP);
  textSize(16);
  
  String modeText = hasLaunchpad ? "Launchpad" : "Mouse";
  String[] modes = {"Density", "Velocity", "Pressure"};
  
  text("FluidPad | " + modeText + " | Mode: " + modes[displayMode] + 
       " | Vorticity: " + (highVorticity ? "HIGH" : "low") +
       " | Palette: " + (paletteIndex + 1), 10, 10);
  
  textAlign(RIGHT, TOP);
  text(String.format("%.1f fps", frameRate), width - 10, 10);
}

// Inject fluid at grid position
void injectAtGrid(int col, int row) {
  // Map grid (0-7, 0-7) to screen coordinates
  float cellW = width / 8.0f;
  float cellH = height / 8.0f;
  
  // Screen X: col 0 = left, col 7 = right
  float px = (col + 0.5f) * cellW;
  // Screen Y for PixelFlow: row 0 = bottom of screen, row 7 = top
  float py = (row + 0.5f) * cellH;  // PixelFlow Y=0 is bottom
  
  // Velocity based on position from center (radial outward)
  float cx = width / 2.0f;
  float cy = height / 2.0f;
  float dx = px - cx;
  float dy = py - cy;
  float dist = sqrt(dx*dx + dy*dy);
  
  // Debug output
  println("Grid: (" + col + "," + row + ") -> Screen: (" + px + "," + py + ")");
  
  float vx = (dist > 0) ? (dx / dist) * 80 : random(-50, 50);
  float vy = (dist > 0) ? (dy / dist) * 80 : random(-50, 50);
  
  // Create injection with color based on grid position
  float hue = (col + row) / 14.0f;  // 0-1 range
  float[] col_rgb = hueToRGB(hue);
  
  injections.add(new FluidInjection(px, py, vx, vy, col_rgb, 15));
  
  // Flash pad on Launchpad
  flashPad(col, row);
}

float[] hueToRGB(float h) {
  // Convert hue (0-1) to RGB
  float r = abs(h * 6 - 3) - 1;
  float g = 2 - abs(h * 6 - 2);
  float b = 2 - abs(h * 6 - 4);
  return new float[] {
    constrain(r, 0, 1),
    constrain(g, 0, 1),
    constrain(b, 0, 1)
  };
}

void flashPad(int col, int row) {
  if (!hasLaunchpad || launchpad == null) return;
  
  int note = gridToNote(col, row);
  int flashColor = LP_WHITE;
  
  // Flash white then return to grid color
  launchpad.sendNoteOn(0, note, flashColor);
  
  // Schedule return to normal color (using frame delay)
  final int c = col;
  final int r = row;
  new Thread(() -> {
    try {
      Thread.sleep(100);
      if (launchpad != null) {
        launchpad.sendNoteOn(0, gridToNote(c, r), gridColors[c][r]);
      }
    } catch (Exception e) {}
  }).start();
}

void updateGridColors() {
  int[] lpColors = {LP_BLUE, LP_CYAN, LP_GREEN, LP_YELLOW, LP_ORANGE, LP_RED, LP_PINK, LP_PURPLE};
  
  for (int c = 0; c < 8; c++) {
    for (int r = 0; r < 8; r++) {
      int colorIdx = (c + r + paletteIndex) % lpColors.length;
      gridColors[c][r] = lpColors[colorIdx];
    }
  }
}

void updateLaunchpadDisplay() {
  if (!hasLaunchpad || launchpad == null) return;
  
  for (int r = 0; r < 8; r++) {
    for (int c = 0; c < 8; c++) {
      launchpad.sendNoteOn(0, gridToNote(c, r), gridColors[c][r]);
    }
  }
  
  // Light scene buttons for functions
  launchpad.sendNoteOn(0, 89, LP_PURPLE);  // Palette
  launchpad.sendNoteOn(0, 79, highVorticity ? LP_CYAN : LP_BLUE);  // Vorticity
  launchpad.sendNoteOn(0, 69, LP_RED);     // Reset
  launchpad.sendNoteOn(0, 59, LP_GREEN);   // Display mode
}

void cyclePalette() {
  paletteIndex = (paletteIndex + 1) % palettes.length;
  updateGridColors();
  updateLaunchpadDisplay();
}

void toggleVorticity() {
  highVorticity = !highVorticity;
  fluid.param.vorticity = highVorticity ? 0.50f : 0.05f;
  updateLaunchpadDisplay();
}

void resetFluid() {
  fluid.reset();
  injections.clear();
  
  // Flash all pads
  if (hasLaunchpad && launchpad != null) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        launchpad.sendNoteOn(0, gridToNote(c, r), LP_WHITE);
      }
    }
    // Restore after delay
    new Thread(() -> {
      try {
        Thread.sleep(200);
        updateLaunchpadDisplay();
      } catch (Exception e) {}
    }).start();
  }
}

void cycleDisplayMode() {
  displayMode = (displayMode + 1) % 3;
}

// MIDI callbacks
void noteOn(int channel, int pitch, int velocity) {
  // Scene buttons (right column)
  if (pitch == 89) { cyclePalette(); return; }
  if (pitch == 79) { toggleVorticity(); return; }
  if (pitch == 69) { resetFluid(); return; }
  if (pitch == 59) { cycleDisplayMode(); return; }
  
  // Grid pads
  if (isValidPad(pitch)) {
    PVector pos = noteToGrid(pitch);
    injectAtGrid((int)pos.x, (int)pos.y);
  }
}

void noteOff(int channel, int pitch, int velocity) {
  // Not used
}

void keyPressed() {
  if (key == 'r' || key == 'R') resetFluid();
  if (key == 'c' || key == 'C') cyclePalette();
  if (key == 'v' || key == 'V') toggleVorticity();
  if (key == '1') displayMode = 0;
  if (key == '2') displayMode = 1;
  if (key == '3') displayMode = 2;
}

void mousePressed() {
  if (mouseButton == RIGHT) {
    // Right click = inject at grid position
    int col = (int)(mouseX / (width / 8.0f));
    int row = 7 - (int)(mouseY / (height / 8.0f));
    col = constrain(col, 0, 7);
    row = constrain(row, 0, 7);
    injectAtGrid(col, row);
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

void exit() {
  // Clear Launchpad
  if (hasLaunchpad && launchpad != null) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        launchpad.sendNoteOn(0, gridToNote(c, r), LP_OFF);
      }
    }
  }
  super.exit();
}

// Fluid injection helper class
class FluidInjection {
  float px, py;
  float vx, vy;
  float[] rgb;
  int framesLeft;
  int totalFrames;
  
  FluidInjection(float px, float py, float vx, float vy, float[] rgb, int frames) {
    this.px = px;
    this.py = py;
    this.vx = vx;
    this.vy = vy;
    this.rgb = rgb;
    this.framesLeft = frames;
    this.totalFrames = frames;
  }
  
  void apply(DwFluid2D fluid) {
    float t = (float)framesLeft / totalFrames;  // 1 -> 0
    float radius = 25 * t + 10;  // Larger radius for visibility
    float intensity = t;
    
    fluid.addVelocity(px, py, radius, vx * intensity, vy * intensity);
    fluid.addDensity(px, py, radius, rgb[0] * intensity, rgb[1] * intensity, rgb[2] * intensity, 1.0f);
    
    // White core on first few frames
    if (framesLeft > totalFrames - 3) {
      fluid.addDensity(px, py, radius * 0.4f, 1.0f, 1.0f, 1.0f, 1.0f);
    }
    
    framesLeft--;
  }
  
  boolean isDone() {
    return framesLeft <= 0;
  }
}
