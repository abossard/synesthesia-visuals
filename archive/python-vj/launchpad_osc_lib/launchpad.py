"""
Launchpad Mini Mk3 Driver

This module has been replaced by the lpminimk3 library.

Usage:
    import lpminimk3
    
    # Find and connect to Launchpad
    lp = lpminimk3.find_launchpads()[0]
    lp.open()
    lp.mode = lpminimk3.Mode.PROG
    
    # Handle button events
    while True:
        event = lp.panel.buttons().poll_for_event()
        if event and event.type == lpminimk3.ButtonEvent.PRESS:
            event.button.led.color = lpminimk3.colors.ColorPalette.Red.SHADE_5
    
For full API documentation, see: https://github.com/obeezzy/lpminimk3
"""
