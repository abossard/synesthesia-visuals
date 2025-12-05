#!/usr/bin/env python3
"""
MIDI Router Setup Verification Script

Checks all prerequisites and provides setup instructions if anything is missing.
Run this before using the MIDI router to ensure everything is configured correctly.

Usage:
    python verify_midi_setup.py
"""

import sys
import os
from pathlib import Path
from typing import List, Tuple


class SetupChecker:
    """Verifies MIDI router setup and provides instructions."""
    
    def __init__(self):
        self.checks_passed = 0
        self.checks_failed = 0
        self.warnings = []
        self.instructions = []
    
    def print_header(self):
        """Print script header."""
        print("\n" + "="*70)
        print("  MIDI Router Setup Verification")
        print("="*70 + "\n")
    
    def print_result(self, check_name: str, passed: bool, message: str = ""):
        """Print check result with formatting."""
        status = "✓" if passed else "✗"
        color = "\033[92m" if passed else "\033[91m"
        reset = "\033[0m"
        
        print(f"{color}{status}{reset} {check_name}")
        if message:
            print(f"  {message}")
        
        if passed:
            self.checks_passed += 1
        else:
            self.checks_failed += 1
    
    def check_python_version(self) -> bool:
        """Check Python version is 3.8+."""
        version = sys.version_info
        passed = version >= (3, 8)
        
        if passed:
            self.print_result(
                "Python Version",
                True,
                f"Python {version.major}.{version.minor}.{version.micro}"
            )
        else:
            self.print_result(
                "Python Version",
                False,
                f"Python {version.major}.{version.minor} (need 3.8+)"
            )
            self.instructions.append(
                "Install Python 3.8 or higher from https://www.python.org/"
            )
        
        return passed
    
    def check_dependencies(self) -> bool:
        """Check required Python packages."""
        required = [
            ('rtmidi', 'python-rtmidi', 'MIDI I/O'),
            ('textual', 'textual', 'Terminal UI'),
            ('dotenv', 'python-dotenv', 'Environment config'),
        ]
        
        all_installed = True
        missing = []
        
        for module_name, package_name, description in required:
            try:
                __import__(module_name)
                self.print_result(f"Package: {package_name}", True, description)
            except ImportError:
                self.print_result(f"Package: {package_name}", False, f"Missing - {description}")
                all_installed = False
                missing.append(package_name)
        
        if not all_installed:
            self.instructions.append(
                f"Install missing packages:\n"
                f"  cd python-vj\n"
                f"  pip install {' '.join(missing)}\n"
                f"Or install all requirements:\n"
                f"  pip install -r requirements.txt"
            )
        
        return all_installed
    
    def check_midi_devices(self) -> Tuple[bool, List[str], List[str]]:
        """Check if MIDI devices are available."""
        try:
            import rtmidi
            
            midi_in = rtmidi.MidiIn()
            midi_out = rtmidi.MidiOut()
            
            input_ports = midi_in.get_ports()
            output_ports = midi_out.get_ports()
            
            # Clean up
            midi_in.close_port()
            midi_out.close_port()
            del midi_in
            del midi_out
            
            # Check for controllers (devices with both input and output)
            controllers = []
            for port in input_ports:
                if port in output_ports:
                    controllers.append(port)
            
            if controllers:
                self.print_result(
                    "MIDI Controllers",
                    True,
                    f"Found {len(controllers)} controller(s):"
                )
                for ctrl in controllers:
                    print(f"    - {ctrl}")
            else:
                self.print_result(
                    "MIDI Controllers",
                    False,
                    "No MIDI controllers found"
                )
                self.warnings.append(
                    "Connect a MIDI controller (e.g., Launchpad, MIDImix) via USB"
                )
            
            # Check for virtual ports
            virtual_keywords = ['iac', 'bus', 'virtual', 'magic', 'loopback']
            virtual_ports = [
                p for p in output_ports 
                if any(kw in p.lower() for kw in virtual_keywords)
            ]
            
            if virtual_ports:
                self.print_result(
                    "Virtual MIDI Ports",
                    True,
                    f"Found {len(virtual_ports)} virtual port(s):"
                )
                for vp in virtual_ports:
                    print(f"    - {vp}")
            else:
                self.print_result(
                    "Virtual MIDI Ports",
                    False,
                    "No virtual MIDI ports found"
                )
                if sys.platform == 'darwin':
                    self.instructions.append(
                        "Setup virtual MIDI port (macOS):\n"
                        "  1. Open 'Audio MIDI Setup' app\n"
                        "  2. Window → Show MIDI Studio\n"
                        "  3. Double-click 'IAC Driver'\n"
                        "  4. Check 'Device is online'\n"
                        "  5. Add a port named 'MagicBus' (or any name)\n"
                        "  6. Click 'Apply'"
                    )
                elif sys.platform == 'linux':
                    self.instructions.append(
                        "Setup virtual MIDI port (Linux):\n"
                        "  sudo modprobe snd-virmidi\n"
                        "Or install and configure JACK Audio"
                    )
                elif sys.platform == 'win32':
                    self.instructions.append(
                        "Setup virtual MIDI port (Windows):\n"
                        "  Install loopMIDI or similar virtual MIDI driver\n"
                        "  Create a port named 'MagicBus'"
                    )
            
            return len(controllers) > 0, controllers, virtual_ports
            
        except ImportError:
            self.print_result(
                "MIDI Support",
                False,
                "python-rtmidi not installed"
            )
            return False, [], []
        except Exception as e:
            self.print_result(
                "MIDI Detection",
                False,
                f"Error: {e}"
            )
            return False, [], []
    
    def check_config_file(self) -> bool:
        """Check if config file exists."""
        config_path = Path.home() / '.midi_router' / 'config.json'
        
        if config_path.exists():
            self.print_result(
                "Config File",
                True,
                f"Found at {config_path}"
            )
            return True
        else:
            self.print_result(
                "Config File",
                False,
                "Not yet created (will be created on first run)"
            )
            self.warnings.append(
                "Config will be auto-created when you first run the VJ Console"
            )
            return False
    
    def check_vj_console(self) -> bool:
        """Check if vj_console.py exists."""
        vj_console_path = Path(__file__).parent / 'vj_console.py'
        
        if vj_console_path.exists():
            self.print_result(
                "VJ Console",
                True,
                f"Found at {vj_console_path}"
            )
            return True
        else:
            self.print_result(
                "VJ Console",
                False,
                "vj_console.py not found"
            )
            return False
    
    def print_summary(self):
        """Print summary and instructions."""
        print("\n" + "="*70)
        print(f"  Summary: {self.checks_passed} passed, {self.checks_failed} failed")
        print("="*70 + "\n")
        
        if self.warnings:
            print("⚠️  WARNINGS:")
            for warning in self.warnings:
                print(f"  • {warning}")
            print()
        
        if self.instructions:
            print("📋 SETUP INSTRUCTIONS:")
            print()
            for i, instruction in enumerate(self.instructions, 1):
                print(f"{i}. {instruction}")
                print()
        
        if self.checks_failed == 0:
            print("✅ All checks passed! You're ready to use the MIDI router.\n")
            print("Quick Start:")
            print("  1. Launch VJ Console:")
            print("     python vj_console.py")
            print()
            print("  2. Press '5' to go to MIDI screen")
            print()
            print("  3. Press 'c' to select your MIDI controller")
            print()
            print("  4. Press 'l' to enter learn mode and capture toggle buttons")
            print()
            print("For detailed instructions, see MIDI_ROUTER_QUICK_REF.md")
        else:
            print("❌ Some checks failed. Please follow the setup instructions above.\n")
    
    def run(self):
        """Run all verification checks."""
        self.print_header()
        
        # Run checks
        self.check_python_version()
        self.check_dependencies()
        self.check_midi_devices()
        self.check_config_file()
        self.check_vj_console()
        
        # Print summary
        self.print_summary()
        
        return self.checks_failed == 0


def main():
    """Main entry point."""
    checker = SetupChecker()
    success = checker.run()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
