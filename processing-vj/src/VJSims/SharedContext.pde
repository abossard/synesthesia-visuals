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
  
  
  SharedContext(PApplet parent) {
    // Framebuffer at sketch resolution
    framebuffer = parent.createGraphics(parent.width, parent.height, P3D);

    // Syphon server
    syphon = new SyphonServer(parent, "VJSystem");

    // Audio (stub for now)
    audio = new AudioEnvelope();

    // Config (update with actual dimensions)
    config = new SketchConfig();
    config.width = parent.width;
    config.height = parent.height;
  }
  
  /**
   */
  
  /**
   * Send framebuffer to Syphon
   */
  void sendToSyphon() {
    syphon.sendImage(framebuffer);
  }
}
