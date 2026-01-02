/**
 * AudioPanelTile.pde - Audio analysis panel tile
 *
 * Syphon output: VJUniverse/Audio
 */

class AudioPanelTile extends Tile {
  
  int lastLogMs = -10000;
  final int LOG_INTERVAL_MS = 2000;
  
  AudioPanelTile() {
    super("Audio", "VJUniverse/Audio");
    setOSCAddresses(
      new String[] {"/audio/*"},
      new String[] {"Audio levels"}
    );
  }
  
  @Override
  void render() {
    beginDraw();
    buffer.resetShader();
    drawAudioPanelTo(buffer);
    endDraw();
    logStateIfNeeded();
  }
  
  @Override
  String getStatusString() {
    String status = isSynAudioActive() ? "stream" : "wait";
    String level = nf(smoothAudioLevel, 0, 2);
    String energy = nf(energyFast, 0, 2);
    return "Audio " + status + " | Level " + level + " | Energy " + energy + " | Beat " + beat4;
  }
  
  void logStateIfNeeded() {
    int now = millis();
    if (now - lastLogMs < LOG_INTERVAL_MS) return;
    lastLogMs = now;
    String status = isSynAudioActive() ? "stream" : "wait";
    println("[AudioPanelTile] render " + bufferWidth + "x" + bufferHeight
      + " syphon=" + syphonName
      + " status=" + status
      + " level=" + nf(smoothAudioLevel, 0, 2)
      + " energy=" + nf(energyFast, 0, 2)
      + " beat=" + beat4);
  }
}
