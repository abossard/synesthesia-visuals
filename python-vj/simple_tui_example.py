#!/usr/bin/env python3
"""
Simple TUI Example - Demonstrates Worker Integration

This is a minimal proof-of-concept showing how vj_console.py
would integrate with the multi-process worker architecture.

Not a full replacement for vj_console.py, just a demonstration.
"""

import time
import sys
from pathlib import Path

# Add parent to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from vj_bus import WorkerDiscovery, ControlSocket
from vj_bus.schema import CommandMessage


class SimpleTUI:
    """
    Simple TUI demonstrating worker integration.
    
    Shows how the real vj_console.py would:
    - Discover workers on startup
    - Connect to workers
    - Send commands
    - Display worker status
    """
    
    def __init__(self):
        self.workers = {}
        self.running = True
    
    def discover_workers(self):
        """Discover and connect to all running workers."""
        print("\n" + "=" * 60)
        print("Discovering workers...")
        print("=" * 60)
        
        found = WorkerDiscovery.scan_workers()
        
        if not found:
            print("⚠️  No workers found. Start workers with:")
            print("  python vj_process_manager.py")
            return
        
        print(f"\nFound {len(found)} workers:")
        
        for worker_info in found:
            name = worker_info['name']
            socket_path = worker_info['socket_path']
            
            # Connect to worker
            client = ControlSocket(f"{name}_tui_client")
            if client.connect(timeout=2.0):
                self.workers[name] = client
                print(f"  ✓ {name:20} {socket_path}")
                
                # Request state
                cmd = CommandMessage(cmd="get_state", msg_id=f"init_{name}")
                client.send_message(cmd)
                
                response = client.recv_message(timeout=2.0)
                if response and response.get('success'):
                    print(f"    Status: {response.get('data', {}).get('status', 'unknown')}")
            else:
                print(f"  ✗ {name:20} (connection failed)")
    
    def show_menu(self):
        """Show interactive menu."""
        print("\n" + "=" * 60)
        print("Simple TUI - Worker Control Demo")
        print("=" * 60)
        print()
        print("Commands:")
        print("  1 - Refresh worker discovery")
        print("  2 - Get status from all workers")
        print("  3 - Send test command to process manager")
        print("  q - Quit")
        print()
    
    def get_all_status(self):
        """Get status from all connected workers."""
        print("\n" + "=" * 60)
        print("Worker Status")
        print("=" * 60)
        
        for name, client in self.workers.items():
            cmd = CommandMessage(cmd="get_state", msg_id=f"status_{name}")
            if client.send_message(cmd):
                response = client.recv_message(timeout=2.0)
                if response:
                    print(f"\n{name}:")
                    if response.get('success'):
                        data = response.get('data', {})
                        for key, value in data.items():
                            print(f"  {key}: {value}")
                    else:
                        print(f"  Error: {response.get('message')}")
                else:
                    print(f"  No response (worker may have restarted)")
    
    def test_process_manager_command(self):
        """Send a test command to process manager."""
        pm_client = self.workers.get('process_manager')
        if not pm_client:
            print("\n⚠️  Process manager not connected")
            return
        
        print("\n" + "=" * 60)
        print("Sending get_state to process manager...")
        print("=" * 60)
        
        cmd = CommandMessage(cmd="get_state", msg_id="test_pm")
        if pm_client.send_message(cmd):
            response = pm_client.recv_message(timeout=2.0)
            if response and response.get('success'):
                data = response.get('data', {})
                print(f"\nProcess Manager Status:")
                print(f"  Total workers: {data.get('total_managed', 0)}")
                print(f"  Worker status:")
                for worker_name, status in data.get('workers', {}).items():
                    running = "✓ Running" if status.get('running') else "✗ Stopped"
                    enabled = "Enabled" if status.get('enabled') else "Disabled"
                    print(f"    {worker_name:20} {running:15} {enabled}")
    
    def run(self):
        """Run the TUI."""
        print("\n" + "=" * 60)
        print("Simple TUI - VJ Worker Integration Demo")
        print("=" * 60)
        print()
        print("This demonstrates how vj_console.py would integrate with workers.")
        print()
        
        # Initial discovery
        self.discover_workers()
        
        # Interactive loop
        while self.running:
            self.show_menu()
            
            try:
                choice = input("Enter command: ").strip().lower()
                
                if choice == '1':
                    # Reconnect to workers
                    for client in self.workers.values():
                        client.close()
                    self.workers.clear()
                    self.discover_workers()
                
                elif choice == '2':
                    self.get_all_status()
                
                elif choice == '3':
                    self.test_process_manager_command()
                
                elif choice == 'q':
                    self.running = False
                    print("\nGoodbye!")
                
                else:
                    print(f"\nUnknown command: {choice}")
            
            except KeyboardInterrupt:
                self.running = False
                print("\n\nGoodbye!")
            
            except Exception as e:
                print(f"\nError: {e}")
        
        # Cleanup
        for client in self.workers.values():
            client.close()


def main():
    """Main entry point."""
    tui = SimpleTUI()
    tui.run()


if __name__ == "__main__":
    main()
