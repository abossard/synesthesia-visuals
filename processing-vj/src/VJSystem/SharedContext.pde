/**
 * SharedContext — Resources shared across all levels
 * 
 * Passed to Level.init() to provide access to:
 * - Main framebuffer
 * - Syphon server
 * - Audio envelope (for visual modulation)
 * - Sketch configuration
 */

class SharedContext {
  
  PGraphics framebuffer;
  SyphonServer syphon;
  AudioEnvelope audio;
  SketchConfig config;
  
  // Launchpad access (for LED feedback)
  LaunchpadGrid grid;
  LaunchpadHUD hud;
  
  SharedContext(PApplet parent) {
    // Framebuffer at full resolution
    framebuffer = parent.createGraphics(1920, 1080, P3D);
    
    // Syphon server
    syphon = new SyphonServer(parent, "VJSystem");
    
    // Audio (stub for now)
    audio = new AudioEnvelope();
    
    // Config
    config = new SketchConfig();
  }
  
  /**
   * Set MIDI components (called after MIDI init)
   */
  void setMidi(LaunchpadGrid grid, LaunchpadHUD hud) {
    this.grid = grid;
    this.hud = hud;
  }
  
  /**
   * Send framebuffer to Syphon
   */
  void sendToSyphon() {
    syphon.sendImage(framebuffer);
  }
}
