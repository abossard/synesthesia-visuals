/**
 * MidiIO — Thin wrapper around The MidiBus
 * 
 * Handles MIDI device detection, connection, and message routing.
 * Provides graceful fallback when no controller is connected.
 */

class MidiIO {
  
  private MidiBus bus;
  private boolean connected = false;
  private String deviceName = "";
  
  // Listener interface for MIDI events
  private MidiListener listener;
  
  /**
   * Initialize MIDI with auto-detection of Launchpad
   */
  MidiIO(PApplet parent) {
    this(parent, "launchpad");
  }
  
  /**
   * Initialize MIDI with specific device name filter
   */
  MidiIO(PApplet parent, String deviceFilter) {
    String[] inputs = MidiBus.availableInputs();
    String[] outputs = MidiBus.availableOutputs();
    
    println("[MidiIO] Scanning for MIDI devices...");
    for (int i = 0; i < inputs.length; i++) {
      println("  Input [" + i + "]: " + inputs[i]);
    }
    
    String inDev = null, outDev = null;
    String filter = deviceFilter.toLowerCase();
    
    for (String dev : inputs) {
      if (dev != null && dev.toLowerCase().contains(filter)) {
        inDev = dev;
        break;
      }
    }
    for (String dev : outputs) {
      if (dev != null && dev.toLowerCase().contains(filter)) {
        outDev = dev;
        break;
      }
    }
    
    if (inDev != null && outDev != null) {
      try {
        bus = new MidiBus(parent, inDev, outDev);
        connected = true;
        deviceName = inDev;
        println("[MidiIO] Connected: " + deviceName);
      } catch (Exception e) {
        println("[MidiIO] Failed to connect: " + e.getMessage());
        connected = false;
      }
    } else {
      println("[MidiIO] No matching device found for filter: " + deviceFilter);
      connected = false;
    }
  }
  
  /**
   * Set listener for MIDI events
   */
  void setListener(MidiListener l) {
    this.listener = l;
  }
  
  /**
   * Check if MIDI device is connected
   */
  boolean isConnected() {
    return connected;
  }
  
  /**
   * Get connected device name
   */
  String getDeviceName() {
    return deviceName;
  }
  
  // ============================================
  // SENDING
  // ============================================
  
  /**
   * Send note-on message (used for LEDs on Launchpad)
   */
  void sendNoteOn(int channel, int note, int velocity) {
    if (!connected || bus == null) return;
    bus.sendNoteOn(channel, note, velocity);
  }
  
  /**
   * Send note-off message
   */
  void sendNoteOff(int channel, int note) {
    if (!connected || bus == null) return;
    bus.sendNoteOff(channel, note, 0);
  }
  
  /**
   * Send control change message
   */
  void sendCC(int channel, int number, int value) {
    if (!connected || bus == null) return;
    bus.sendControllerChange(channel, number, value);
  }
  
  /**
   * Convenience: send LED color to a note
   */
  void sendLED(int note, int colorIndex) {
    sendNoteOn(0, note, colorIndex);
  }
  
  // ============================================
  // RECEIVING (called from PApplet callbacks)
  // ============================================
  
  /**
   * Called from main sketch's noteOn callback
   */
  void onNoteOn(int channel, int pitch, int velocity) {
    if (listener != null) {
      listener.onNote(channel, pitch, velocity, true);
    }
  }
  
  /**
   * Called from main sketch's noteOff callback
   */
  void onNoteOff(int channel, int pitch, int velocity) {
    if (listener != null) {
      listener.onNote(channel, pitch, velocity, false);
    }
  }
  
  /**
   * Called from main sketch's controllerChange callback
   */
  void onCC(int channel, int number, int value) {
    if (listener != null) {
      listener.onCC(channel, number, value);
    }
  }
}

// ============================================
// LISTENER INTERFACE
// ============================================

interface MidiListener {
  void onNote(int channel, int pitch, int velocity, boolean isOn);
  void onCC(int channel, int number, int value);
}
