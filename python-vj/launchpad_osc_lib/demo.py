"""
Launchpad Mini Mk3 Demo / Showcase Module

Demonstrates all Launchpad capabilities:
1. Random color party - all pads flash random colors
2. Diagonal rainbow waves - sweeping in multiple directions
3. Text scroller - NATIVE SysEx scrolling text ("WELCOME TO THE SHOW")
4. Countdown - 10 to 1 with final white flash and fade

Usage:
    # Async version
    from launchpad_osc_lib.demo import run_demo
    await run_demo(device)
    
    # Or run standalone
    python -m launchpad_osc_lib.demo
"""

import asyncio
import logging
import random
import time
from typing import Optional, List, Dict, Any

from .launchpad import (
    LaunchpadDevice,
    LaunchpadConfig,
    PadId,
    LedMode,
    LP_OFF, LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN,
    LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK, LP_WHITE,
    MIDO_AVAILABLE,
)

if MIDO_AVAILABLE:
    from mido import Message

logger = logging.getLogger(__name__)


# =============================================================================
# COLOR UTILITIES
# =============================================================================

# Bright colors for demo effects
DEMO_COLORS = [LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN, LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK]

# Rainbow sequence for wave effects
RAINBOW = [LP_RED, LP_ORANGE, LP_YELLOW, LP_GREEN, LP_CYAN, LP_BLUE, LP_PURPLE, LP_PINK]


# =============================================================================
# SYSEX TEXT SCROLLING (Native Hardware Feature)
# =============================================================================

# SysEx header for Launchpad Mini MK3
SYSEX_HEADER = [0x00, 0x20, 0x29, 0x02, 0x0D]


def build_scroll_text_sysex(
    text: str,
    color: int = LP_CYAN,
    speed: int = 7,
    loop: bool = False,
    use_rgb: bool = False,
    r: int = 0, g: int = 127, b: int = 127
) -> List[int]:
    """
    Build SysEx message for native text scrolling.
    
    Args:
        text: Text to scroll (ASCII only)
        color: Palette color index (0-127) when use_rgb=False
        speed: Scroll speed in pads/second (1-63)
               If speed >= 64 (0x40), scrolls right-to-left
        loop: Whether to loop the text
        use_rgb: If True, use RGB color instead of palette
        r, g, b: RGB values (0-127) when use_rgb=True
    
    Returns:
        List of SysEx data bytes (without F0/F7)
    """
    # Command: 07 = text scroll
    sysex = SYSEX_HEADER + [0x07]
    
    # Loop flag: 0 = no loop, 1 = loop
    sysex.append(0x01 if loop else 0x00)
    
    # Speed (1-63, or 64+ for right-to-left)
    sysex.append(speed & 0x7F)
    
    # Color specification
    if use_rgb:
        sysex.extend([0x01, r & 0x7F, g & 0x7F, b & 0x7F])
    else:
        sysex.extend([0x00, color & 0x7F])
    
    # Text as ASCII bytes
    for char in text:
        sysex.append(ord(char) & 0x7F)
    
    return sysex


def build_stop_scroll_sysex() -> List[int]:
    """Build SysEx message to stop text scrolling."""
    return SYSEX_HEADER + [0x07]


# =============================================================================
# 5x7 FONT FOR COUNTDOWN NUMBERS
# =============================================================================

FONT_5X7: Dict[str, List[int]] = {
    ' ': [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
    '0': [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E],
    '1': [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
    '2': [0x0E, 0x11, 0x01, 0x06, 0x08, 0x10, 0x1F],
    '3': [0x0E, 0x11, 0x01, 0x06, 0x01, 0x11, 0x0E],
    '4': [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02],
    '5': [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
    '6': [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E],
    '7': [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
    '8': [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E],
    '9': [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
}


def get_char_column(char: str, col: int) -> List[bool]:
    """Get a single column (0-4) of a character's bitmap."""
    if char not in FONT_5X7:
        char = ' '
    bitmap = FONT_5X7[char]
    bit_mask = 0x10 >> col
    return [bool(bitmap[row] & bit_mask) for row in range(7)]


# =============================================================================
# DEMO EFFECTS
# =============================================================================

class LaunchpadDemo:
    """Showcase all Launchpad Mini Mk3 capabilities."""
    
    def __init__(self, device: LaunchpadDevice):
        self.device = device
    
    def _send_sysex(self, data: List[int]):
        """Send SysEx message to Launchpad."""
        if self.device._output_port and MIDO_AVAILABLE:
            self.device._output_port.send(Message('sysex', data=data))
    
    async def clear(self):
        """Clear all LEDs."""
        self.device.clear_all_leds()
        await asyncio.sleep(0.05)
    
    async def random_color_party(self, duration: float = 4.0):
        """Phase 1: Random colors on all pads."""
        logger.info("Demo: Random color party")
        
        start = time.time()
        while time.time() - start < duration:
            for y in range(8):
                for x in range(8):
                    color = random.choice(DEMO_COLORS)
                    self.device._led_cache.pop(PadId(x, y), None)
                    self.device.set_led(PadId(x, y), color, LedMode.STATIC)
            await asyncio.sleep(0.15)
        
        await self.clear()
    
    async def diagonal_rainbow_wave(self, direction: str = "down-right", cycles: int = 2, speed: float = 0.05):
        """Diagonal rainbow wave effect."""
        for _ in range(cycles):
            for offset in range(16):
                for y in range(8):
                    for x in range(8):
                        if direction == "down-right":
                            diag = (x + y + offset) % len(RAINBOW)
                        elif direction == "down-left":
                            diag = ((7 - x) + y + offset) % len(RAINBOW)
                        elif direction == "up-right":
                            diag = (x + (7 - y) + offset) % len(RAINBOW)
                        else:
                            diag = ((7 - x) + (7 - y) + offset) % len(RAINBOW)
                        
                        self.device._led_cache.pop(PadId(x, y), None)
                        self.device.set_led(PadId(x, y), RAINBOW[diag], LedMode.STATIC)
                await asyncio.sleep(speed)
    
    async def rainbow_rush(self):
        """Phase 2: Multiple rainbow waves in different directions."""
        logger.info("Demo: Rainbow rush")
        
        for direction in ["down-right", "up-left", "down-left", "up-right"]:
            await self.diagonal_rainbow_wave(direction, cycles=2, speed=0.03)
        
        await self.clear()
    
    async def scroll_text_native(self, text: str, color: int = LP_CYAN, speed: int = 10, duration: float = None):
        """
        Phase 3: Native hardware text scrolling via SysEx.
        
        Args:
            text: Text to scroll
            color: Palette color index
            speed: Pads per second (1-63)
            duration: How long to show (None = calculate from text length)
        """
        logger.info(f"Demo: Native text scroll '{text}'")
        
        # Start scrolling
        sysex = build_scroll_text_sysex(text, color=color, speed=speed, loop=False)
        self._send_sysex(sysex)
        
        # Calculate duration if not specified
        # Text scrolls at `speed` pads/second, each char ~6 pixels + 8 for off-screen
        if duration is None:
            total_pixels = len(text) * 6 + 16  # ~6 pixels per char + margins
            duration = total_pixels / speed + 0.5  # Add buffer
        
        await asyncio.sleep(duration)
        
        # Stop scrolling
        self._send_sysex(build_stop_scroll_sysex())
        await self.clear()
    
    async def countdown(self, start: int = 10):
        """Phase 4: Countdown from start to 1."""
        logger.info(f"Demo: Countdown from {start}")
        
        for num in range(start, 0, -1):
            await self.clear()
            
            # Color based on progress
            if num > 5:
                color = LP_GREEN
            elif num > 2:
                color = LP_YELLOW
            else:
                color = LP_RED
            
            await self._draw_large_number(num, color)
            await asyncio.sleep(1.0)
        
        await self.final_flash()
    
    async def _draw_large_number(self, num: int, color: int):
        """Draw a number (0-99) on the grid."""
        text = str(num)
        
        if len(text) == 1:
            char = text[0]
            for col in range(5):
                screen_x = col + 1
                for row, pixel_on in enumerate(get_char_column(char, col)):
                    if pixel_on:
                        screen_y = 7 - row
                        if 0 <= screen_y < 8:
                            self.device.set_led(PadId(screen_x, screen_y), color, LedMode.STATIC)
        else:
            for char_idx, char in enumerate(text):
                for col in range(5):
                    screen_x = char_idx * 4 + col
                    if screen_x < 8:
                        for row, pixel_on in enumerate(get_char_column(char, col)):
                            if pixel_on:
                                screen_y = 7 - row
                                if 0 <= screen_y < 8:
                                    self.device.set_led(PadId(screen_x, screen_y), color, LedMode.STATIC)
    
    async def final_flash(self):
        """Final phase: All white flash then fade to black."""
        logger.info("Demo: Final flash and fade")
        
        # Bright white flash
        for y in range(8):
            for x in range(8):
                self.device._led_cache.pop(PadId(x, y), None)
                self.device.set_led(PadId(x, y), LP_WHITE, LedMode.STATIC)
        
        await asyncio.sleep(0.5)
        
        # Fade out
        fade_colors = [119, 71, 70, 1, 0]
        for fade_color in fade_colors:
            for y in range(8):
                for x in range(8):
                    self.device._led_cache.pop(PadId(x, y), None)
                    self.device.set_led(PadId(x, y), fade_color, LedMode.STATIC)
            await asyncio.sleep(0.3)
        
        await self.clear()


# =============================================================================
# MAIN DEMO RUNNER
# =============================================================================

async def run_demo(device: LaunchpadDevice):
    """Run the full demo sequence."""
    demo = LaunchpadDemo(device)
    
    logger.info("=== Starting Launchpad Demo ===")
    
    # Phase 1: Random color party (4s)
    await demo.random_color_party(duration=4.0)
    await asyncio.sleep(0.3)
    
    # Phase 2: Rainbow waves
    await demo.rainbow_rush()
    await asyncio.sleep(0.3)
    
    # Phase 3: Native text scroll - "WELCOME TO THE SHOW"
    await demo.scroll_text_native("WELCOME TO THE SHOW", color=LP_CYAN, speed=12)
    await asyncio.sleep(0.3)
    
    # Phase 4: Countdown 10 to 1
    await demo.countdown(start=10)
    
    logger.info("=== Demo Complete ===")


async def run_startup_demo(device):
    """
    Run a brief startup demo. Works with any device that has:
    - set_led(pad_id, color) method
    - clear_all() method  
    - _output_port attribute (for SysEx)
    - _led_cache dict attribute
    
    Args:
        device: Launchpad device instance (from launchpad_osc_lib or launchpad_standalone)
    """
    logger.info("Running startup demo...")
    
    # Phase 1: Quick rainbow wave
    for offset in range(16):
        for y in range(8):
            for x in range(8):
                diag = (x + y + offset) % len(RAINBOW)
                # Clear cache to force update
                if hasattr(device, '_led_cache'):
                    device._led_cache.pop((x, y), None)
                # Use simple set_led (works with both device types)
                pad = PadId(x, y) if hasattr(PadId, '__init__') else type('PadId', (), {'x': x, 'y': y})()
                device.set_led(pad, RAINBOW[diag])
        await asyncio.sleep(0.12)
    
    # Phase 2: Native text scroll "READY"
    if MIDO_AVAILABLE and hasattr(device, '_output_port') and device._output_port:
        sysex = build_scroll_text_sysex("READY", color=LP_CYAN, speed=15, loop=False)
        device._output_port.send(Message('sysex', data=sysex))
        await asyncio.sleep(2.5)
        device._output_port.send(Message('sysex', data=build_stop_scroll_sysex()))
    
    # Phase 3: Quick flash and clear
    for y in range(8):
        for x in range(8):
            if hasattr(device, '_led_cache'):
                device._led_cache.pop((x, y), None)
            pad = PadId(x, y) if hasattr(PadId, '__init__') else type('PadId', (), {'x': x, 'y': y})()
            device.set_led(pad, LP_WHITE)
    await asyncio.sleep(0.2)
    
    # Clear all
    if hasattr(device, 'clear_all'):
        device.clear_all()
    elif hasattr(device, 'clear_all_leds'):
        device.clear_all_leds()
    await asyncio.sleep(0.1)
    
    logger.info("Startup demo complete")


async def main():
    """Standalone demo runner."""
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    
    device = LaunchpadDevice(LaunchpadConfig(auto_detect=True))
    
    if not await device.connect():
        logger.error("Failed to connect to Launchpad")
        return
    
    try:
        await run_demo(device)
    finally:
        await device.stop()


if __name__ == "__main__":
    asyncio.run(main())
