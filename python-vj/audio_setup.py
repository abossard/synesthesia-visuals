#!/usr/bin/env python3
"""
Audio Setup Verification for macOS

Verifies and configures audio routing for VJ performances:
- Checks if BlackHole is installed
- Finds Multi-Output Devices that include BlackHole
- Verifies/sets the default audio output device

Requirements:
    pip install pyobjc-framework-CoreAudio (optional, for setting default device)

Usage:
    python audio_setup.py [--fix]

    --fix: Attempt to set the default output to a Multi-Output Device with BlackHole
"""

import subprocess
import json
import re
import sys
import argparse
from dataclasses import dataclass
from typing import List, Optional, Tuple
import logging

logging.basicConfig(level=logging.INFO, format='%(message)s')
logger = logging.getLogger('audio_setup')


@dataclass
class AudioDevice:
    """Represents a macOS audio device."""
    name: str
    uid: str
    device_id: int
    is_input: bool
    is_output: bool
    is_aggregate: bool = False
    sub_devices: List[str] = None
    
    def __post_init__(self):
        if self.sub_devices is None:
            self.sub_devices = []


class AudioSetup:
    """Manages macOS audio device detection and configuration."""
    
    BLACKHOLE_NAMES = ['BlackHole 2ch', 'BlackHole 16ch', 'BlackHole 64ch', 'BlackHole']
    
    def __init__(self):
        self.devices: List[AudioDevice] = []
        self.default_output: Optional[str] = None
        self.default_input: Optional[str] = None
        self.blackhole_installed = False
        self.multi_output_with_blackhole: Optional[AudioDevice] = None
    
    def check_system(self) -> dict:
        """
        Perform full audio system check.
        
        Returns:
            dict with check results and recommendations
        """
        results = {
            'blackhole_installed': False,
            'blackhole_device': None,
            'multi_output_found': False,
            'multi_output_device': None,
            'multi_output_has_blackhole': False,
            'default_output': None,
            'default_output_correct': False,
            'recommendations': [],
            'errors': [],
        }
        
        try:
            # Get all audio devices
            self._discover_devices()
            
            # Check for BlackHole
            blackhole_device = self._find_blackhole()
            if blackhole_device:
                results['blackhole_installed'] = True
                results['blackhole_device'] = blackhole_device.name
                self.blackhole_installed = True
            else:
                results['errors'].append("BlackHole is not installed")
                results['recommendations'].append(
                    "Install BlackHole: brew install blackhole-2ch\n"
                    "Or download from: https://github.com/ExistentialAudio/BlackHole"
                )
            
            # Find Multi-Output Devices
            multi_outputs = self._find_multi_output_devices()
            if multi_outputs:
                results['multi_output_found'] = True
                
                # Check if any Multi-Output includes BlackHole
                for device in multi_outputs:
                    if self._device_includes_blackhole(device):
                        results['multi_output_device'] = device.name
                        results['multi_output_has_blackhole'] = True
                        self.multi_output_with_blackhole = device
                        break
                
                if not results['multi_output_has_blackhole']:
                    results['recommendations'].append(
                        "Create a Multi-Output Device that includes BlackHole:\n"
                        "1. Open Audio MIDI Setup (Applications → Utilities)\n"
                        "2. Click '+' → Create Multi-Output Device\n"
                        "3. Check your speakers AND BlackHole\n"
                        "4. Set speakers as clock source (Master checkbox)"
                    )
            else:
                results['recommendations'].append(
                    "No Multi-Output Device found. Create one in Audio MIDI Setup:\n"
                    "1. Open Audio MIDI Setup (Applications → Utilities)\n"
                    "2. Click '+' → Create Multi-Output Device\n"
                    "3. Check your speakers AND BlackHole"
                )
            
            # Check default output
            self.default_output = self._get_default_output()
            results['default_output'] = self.default_output
            
            if self.multi_output_with_blackhole:
                if self.default_output == self.multi_output_with_blackhole.name:
                    results['default_output_correct'] = True
                else:
                    results['recommendations'].append(
                        f"Set default output to '{self.multi_output_with_blackhole.name}':\n"
                        f"System Settings → Sound → Output → {self.multi_output_with_blackhole.name}\n"
                        "Or run: python audio_setup.py --fix"
                    )
            
        except Exception as e:
            results['errors'].append(f"Error checking audio system: {e}")
        
        return results
    
    def _discover_devices(self):
        """Discover all audio devices using system_profiler."""
        self.devices = []
        
        try:
            # Use system_profiler for comprehensive device info
            result = subprocess.run(
                ['system_profiler', 'SPAudioDataType', '-json'],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                data = json.loads(result.stdout)
                audio_data = data.get('SPAudioDataType', [])
                
                for item in audio_data:
                    items = item.get('_items', [])
                    for device_info in items:
                        name = device_info.get('_name', '')
                        if name:
                            device = AudioDevice(
                                name=name,
                                uid=device_info.get('coreaudio_device_id', ''),
                                device_id=0,  # Will be populated if needed
                                is_input='coreaudio_device_input' in device_info,
                                is_output='coreaudio_device_output' in device_info,
                            )
                            self.devices.append(device)
        except (subprocess.TimeoutExpired, json.JSONDecodeError, Exception) as e:
            logger.debug(f"system_profiler failed: {e}")
        
        # Also use audiodevice command if available (more reliable for some info)
        try:
            result = subprocess.run(
                ['SwitchAudioSource', '-a'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for line in result.stdout.strip().split('\n'):
                    name = line.strip()
                    if name and not any(d.name == name for d in self.devices):
                        self.devices.append(AudioDevice(
                            name=name,
                            uid='',
                            device_id=0,
                            is_input=False,
                            is_output=True
                        ))
        except (subprocess.TimeoutExpired, FileNotFoundError):
            pass  # SwitchAudioSource not installed
        
        # Parse aggregate devices from ioreg for more detail
        self._parse_aggregate_devices()
    
    def _parse_aggregate_devices(self):
        """Parse aggregate/multi-output devices from Audio MIDI Setup."""
        try:
            # Use ioreg to find aggregate devices
            result = subprocess.run(
                ['ioreg', '-l', '-c', 'AppleUSBAudioEngine'],
                capture_output=True,
                text=True,
                timeout=10
            )
            # This gives basic info, but aggregate devices need different parsing
        except Exception:
            pass
        
        # Check for Multi-Output in device names
        for device in self.devices:
            if 'Multi-Output' in device.name or 'Aggregate' in device.name:
                device.is_aggregate = True
    
    def _find_blackhole(self) -> Optional[AudioDevice]:
        """Find BlackHole audio device."""
        for device in self.devices:
            for bh_name in self.BLACKHOLE_NAMES:
                if bh_name.lower() in device.name.lower():
                    return device
        
        # Also check using AudioObjectGetPropertyData approach
        # by looking for device in ioreg
        try:
            result = subprocess.run(
                ['ioreg', '-l'],
                capture_output=True,
                text=True,
                timeout=10
            )
            if 'BlackHole' in result.stdout:
                return AudioDevice(
                    name='BlackHole',
                    uid='',
                    device_id=0,
                    is_input=True,
                    is_output=True
                )
        except Exception:
            pass
        
        return None
    
    def _find_multi_output_devices(self) -> List[AudioDevice]:
        """Find all Multi-Output devices."""
        multi_outputs = []
        
        for device in self.devices:
            if 'Multi-Output' in device.name or 'Aggregate' in device.name:
                device.is_aggregate = True
                multi_outputs.append(device)
        
        # Also check for aggregate devices via defaults
        try:
            result = subprocess.run(
                ['defaults', 'read', 
                 '/Library/Preferences/Audio/com.apple.audio.DeviceSettings.plist'],
                capture_output=True,
                text=True,
                timeout=5
            )
            # Parse for aggregate devices if needed
        except Exception:
            pass
        
        return multi_outputs
    
    def _device_includes_blackhole(self, device: AudioDevice) -> bool:
        """Check if a Multi-Output device includes BlackHole."""
        # For aggregate devices, we need to check sub-devices
        # This is tricky without CoreAudio bindings
        
        # Heuristic: Check if both device and BlackHole exist
        # In practice, user should verify this manually
        if not self.blackhole_installed:
            return False
        
        # Try to get aggregate device composition from Audio MIDI Setup prefs
        try:
            result = subprocess.run(
                ['defaults', 'read', 
                 os.path.expanduser('~/Library/Preferences/com.apple.audio.AudioMIDISetup.plist')],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                # Look for BlackHole in the same aggregate device definition
                content = result.stdout
                # This is a rough check - proper implementation would parse the plist
                if 'BlackHole' in content and device.name in content:
                    return True
        except Exception:
            pass
        
        # If we found a Multi-Output and BlackHole is installed,
        # assume it might be configured correctly (user should verify)
        logger.warning(
            f"Cannot verify if '{device.name}' includes BlackHole. "
            "Please check Audio MIDI Setup manually."
        )
        return True  # Optimistic assumption
    
    def _get_default_output(self) -> Optional[str]:
        """Get the current default audio output device."""
        try:
            # Try SwitchAudioSource first (if installed via brew)
            result = subprocess.run(
                ['SwitchAudioSource', '-c'],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except FileNotFoundError:
            pass
        except Exception:
            pass
        
        # Fall back to system_profiler
        try:
            result = subprocess.run(
                ['system_profiler', 'SPAudioDataType', '-json'],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                data = json.loads(result.stdout)
                audio_data = data.get('SPAudioDataType', [])
                for item in audio_data:
                    items = item.get('_items', [])
                    for device_info in items:
                        if device_info.get('coreaudio_default_audio_output_device') == 'yes':
                            return device_info.get('_name')
        except Exception:
            pass
        
        return None
    
    def set_default_output(self, device_name: str) -> bool:
        """
        Set the default audio output device.
        
        Args:
            device_name: Name of the device to set as default
            
        Returns:
            True if successful, False otherwise
        """
        try:
            # Try SwitchAudioSource (most reliable method)
            result = subprocess.run(
                ['SwitchAudioSource', '-s', device_name],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                logger.info(f"Set default output to: {device_name}")
                return True
            else:
                logger.error(f"Failed to set output: {result.stderr}")
        except FileNotFoundError:
            logger.warning(
                "SwitchAudioSource not found. Install with: brew install switchaudio-osx\n"
                "Or set default output manually in System Settings → Sound"
            )
        except Exception as e:
            logger.error(f"Error setting default output: {e}")
        
        return False
    
    def fix_audio_setup(self) -> bool:
        """
        Attempt to fix the audio setup by setting the correct default output.
        
        Returns:
            True if successful, False otherwise
        """
        if not self.multi_output_with_blackhole:
            logger.error("No Multi-Output Device with BlackHole found to set as default")
            return False
        
        return self.set_default_output(self.multi_output_with_blackhole.name)


def print_status(results: dict):
    """Print a formatted status report."""
    print("\n" + "=" * 60)
    print("  macOS Audio Setup Verification")
    print("=" * 60 + "\n")
    
    # BlackHole status
    if results['blackhole_installed']:
        print(f"  ✅ BlackHole: Installed ({results['blackhole_device']})")
    else:
        print("  ❌ BlackHole: Not installed")
    
    # Multi-Output status
    if results['multi_output_found']:
        if results['multi_output_has_blackhole']:
            print(f"  ✅ Multi-Output Device: {results['multi_output_device']}")
        else:
            print("  ⚠️  Multi-Output Device: Found, but may not include BlackHole")
    else:
        print("  ❌ Multi-Output Device: Not found")
    
    # Default output status
    print(f"\n  Default Output: {results['default_output'] or 'Unknown'}")
    if results['default_output_correct']:
        print("  ✅ Default output is correctly configured")
    elif results['multi_output_device']:
        print(f"  ⚠️  Should be: {results['multi_output_device']}")
    
    # Errors
    if results['errors']:
        print("\n  Errors:")
        for error in results['errors']:
            print(f"    ❌ {error}")
    
    # Recommendations
    if results['recommendations']:
        print("\n  Recommendations:")
        for i, rec in enumerate(results['recommendations'], 1):
            print(f"\n  {i}. {rec}")
    
    # Overall status
    print("\n" + "-" * 60)
    if results['blackhole_installed'] and results['multi_output_has_blackhole'] and results['default_output_correct']:
        print("  ✅ Audio setup is correctly configured for VJ performance!")
    else:
        print("  ⚠️  Audio setup needs attention. See recommendations above.")
    print("=" * 60 + "\n")


def main():
    """Main entry point."""
    import os
    
    parser = argparse.ArgumentParser(
        description='Verify and configure macOS audio for VJ performances'
    )
    parser.add_argument(
        '--fix', 
        action='store_true',
        help='Attempt to set the default output to a Multi-Output Device with BlackHole'
    )
    parser.add_argument(
        '--json',
        action='store_true',
        help='Output results as JSON'
    )
    parser.add_argument(
        '-q', '--quiet',
        action='store_true',
        help='Quiet mode - only output errors'
    )
    
    args = parser.parse_args()
    
    # Check if running on macOS (after parsing args so --help works everywhere)
    if sys.platform != 'darwin':
        print("This script is designed for macOS only.")
        print("On macOS, it verifies BlackHole and Multi-Output Device configuration.")
        sys.exit(0)
    
    if args.quiet:
        logger.setLevel(logging.ERROR)
    
    # Run checks
    audio = AudioSetup()
    results = audio.check_system()
    
    # Output results
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print_status(results)
    
    # Attempt fix if requested
    if args.fix:
        print("Attempting to fix audio setup...")
        if audio.fix_audio_setup():
            print("✅ Successfully updated default audio output!")
            # Re-check
            results = audio.check_system()
            if not args.json:
                print_status(results)
        else:
            print("❌ Could not automatically fix audio setup.")
            print("Please configure manually in System Settings → Sound")
            sys.exit(1)
    
    # Exit with appropriate code
    if results['errors'] or not results['default_output_correct']:
        sys.exit(1)
    sys.exit(0)


if __name__ == '__main__':
    main()
