#!/usr/bin/env python3
"""
MIDI Router CLI

Command-line interface for the MIDI router with learn mode support.
"""

import sys
import logging
import argparse
import time
from pathlib import Path

from midi_domain import RouterConfig, DeviceConfig
from midi_infrastructure import list_available_ports, MidiDeviceInfo
from midi_router import MidiRouter, ConfigManager

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('midi_router_cli')


# =============================================================================
# DEFAULT CONFIG
# =============================================================================

def create_default_config(
    controller_pattern: str = "Launchpad",
    virtual_pattern: str = "MagicBus"
) -> RouterConfig:
    """
    Create a default router configuration.
    
    Args:
        controller_pattern: Substring to match controller device
        virtual_pattern: Substring to match virtual MIDI port
    
    Returns:
        Default RouterConfig
    """
    return RouterConfig(
        controller=DeviceConfig(name_pattern=controller_pattern),
        virtual_output=DeviceConfig(name_pattern=virtual_pattern),
        toggles={}
    )


# =============================================================================
# CLI COMMANDS
# =============================================================================

def cmd_list_devices(args):
    """List all available MIDI devices."""
    input_ports, output_ports = list_available_ports()
    
    print("\n=== Available MIDI Devices ===\n")
    
    print("INPUT PORTS:")
    if input_ports:
        for i, port in enumerate(input_ports):
            print(f"  {i+1}. {port}")
    else:
        print("  (none)")
    
    print("\nOUTPUT PORTS:")
    if output_ports:
        for i, port in enumerate(output_ports):
            print(f"  {i+1}. {port}")
    else:
        print("  (none)")
    
    print()


def cmd_init_config(args):
    """Initialize a new configuration file."""
    config_path = Path(args.config)
    
    if config_path.exists() and not args.force:
        print(f"Error: Config file already exists: {config_path}")
        print("Use --force to overwrite")
        return 1
    
    # Create default config
    config = create_default_config(
        controller_pattern=args.controller,
        virtual_pattern=args.virtual
    )
    
    # Save
    config_manager = ConfigManager(config_path)
    config_manager.save(config)
    
    print(f"Created config file: {config_path}")
    print(f"Controller pattern: {args.controller}")
    print(f"Virtual output pattern: {args.virtual}")
    return 0


def cmd_run(args):
    """Run the MIDI router."""
    config_path = Path(args.config)
    
    if not config_path.exists():
        print(f"Error: Config file not found: {config_path}")
        print("Run 'midi_router_cli.py init' to create a config file")
        return 1
    
    # Load config
    config_manager = ConfigManager(config_path)
    config = config_manager.load()
    
    if not config:
        print("Error: Failed to load config")
        return 1
    
    # Create router
    router = MidiRouter(config_manager)
    
    # Start
    if not router.start(config):
        print("Error: Failed to start router")
        return 1
    
    print("\n=== MIDI Router Running ===")
    print(f"Toggles configured: {len(config.toggles)}")
    print("\nCommands:")
    print("  l - Enter learn mode (capture next pad press)")
    print("  s - Show toggle list")
    print("  r <note> <name> - Rename toggle")
    print("  d <note> - Delete toggle")
    print("  q - Quit")
    print()
    
    # Interactive loop
    try:
        while True:
            cmd = input("> ").strip().lower()
            
            if cmd == 'q':
                break
            
            elif cmd == 'l':
                router.enter_learn_mode(lambda note, name: print(f"Learned: {name} (note {note})"))
                print("Learn mode active - press a pad on your controller")
            
            elif cmd == 's':
                toggles = router.get_toggle_list()
                if toggles:
                    print("\nConfigured Toggles:")
                    for note, name, state in toggles:
                        state_str = "ON" if state else "OFF"
                        print(f"  Note {note:3d}: {name:20s} [{state_str}]")
                else:
                    print("No toggles configured")
                print()
            
            elif cmd.startswith('r '):
                parts = cmd.split(None, 2)
                if len(parts) < 3:
                    print("Usage: r <note> <name>")
                    continue
                
                try:
                    note = int(parts[1])
                    name = parts[2]
                    if router.set_toggle_name(note, name):
                        print(f"Renamed toggle {note} to '{name}'")
                    else:
                        print(f"Failed to rename toggle {note}")
                except ValueError:
                    print("Error: note must be a number")
            
            elif cmd.startswith('d '):
                parts = cmd.split()
                if len(parts) < 2:
                    print("Usage: d <note>")
                    continue
                
                try:
                    note = int(parts[1])
                    if router.remove_toggle(note):
                        print(f"Removed toggle {note}")
                    else:
                        print(f"Failed to remove toggle {note}")
                except ValueError:
                    print("Error: note must be a number")
            
            elif cmd:
                print("Unknown command. Try 'l', 's', 'r', 'd', or 'q'")
    
    except KeyboardInterrupt:
        print("\nInterrupted")
    
    finally:
        router.stop()
        print("Router stopped")
    
    return 0


# =============================================================================
# MAIN
# =============================================================================

def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="MIDI Router - Toggle state manager with LED feedback",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # List available MIDI devices
  %(prog)s list
  
  # Initialize config for Launchpad -> MagicBus
  %(prog)s init --controller Launchpad --virtual MagicBus
  
  # Run the router
  %(prog)s run
  
  # Run with custom config
  %(prog)s run --config /path/to/config.json
        """
    )
    
    parser.add_argument(
        '--config',
        default=str(Path.home() / '.midi_router' / 'config.json'),
        help='Path to config file (default: ~/.midi_router/config.json)'
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to run')
    
    # list command
    list_parser = subparsers.add_parser('list', help='List available MIDI devices')
    list_parser.set_defaults(func=cmd_list_devices)
    
    # init command
    init_parser = subparsers.add_parser('init', help='Initialize config file')
    init_parser.add_argument(
        '--controller',
        default='Launchpad',
        help='Controller device name pattern (default: Launchpad)'
    )
    init_parser.add_argument(
        '--virtual',
        default='MagicBus',
        help='Virtual MIDI port name pattern (default: MagicBus)'
    )
    init_parser.add_argument(
        '--force',
        action='store_true',
        help='Overwrite existing config file'
    )
    init_parser.set_defaults(func=cmd_init_config)
    
    # run command
    run_parser = subparsers.add_parser('run', help='Run the MIDI router')
    run_parser.set_defaults(func=cmd_run)
    
    # Parse args
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return 1
    
    # Run command
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
