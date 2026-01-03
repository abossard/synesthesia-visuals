#!/usr/bin/env python3
"""
Development Harness for VJ Multi-Process Architecture

Starts all workers and provides convenient controls for development and testing.
"""

import subprocess
import time
import signal
import sys
import os
from pathlib import Path
from typing import Dict, Optional

class DevHarness:
    """Development harness for starting and managing VJ workers."""
    
    def __init__(self):
        self.processes: Dict[str, subprocess.Popen] = {}
        self.script_dir = Path(__file__).parent.parent
        self.running = False
        
        # Define workers to start
        self.workers = {
            "process_manager": "vj_process_manager.py",
            # Add more workers as needed for manual testing
            # "audio_analyzer": "vj_audio_worker.py",
        }
    
    def start_all(self):
        """Start all workers."""
        self.running = True
        
        print("=" * 60)
        print("VJ Development Harness")
        print("=" * 60)
        print()
        
        # Start process manager first (it will start other workers)
        self._start_worker("process_manager", self.workers["process_manager"])
        
        print()
        print("All workers started!")
        print()
        print("Workers are running in the background.")
        print("Press Ctrl+C to stop all workers.")
        print()
        
        # Monitor workers
        try:
            while self.running:
                time.sleep(1)
                
                # Check if any workers died
                for name, proc in list(self.processes.items()):
                    if proc.poll() is not None:
                        print(f"⚠️  {name} exited (code {proc.returncode})")
                        del self.processes[name]
        
        except KeyboardInterrupt:
            print("\n\nShutting down...")
            self.stop_all()
    
    def _start_worker(self, name: str, script: str):
        """Start a single worker."""
        print(f"Starting {name}...")
        
        try:
            proc = subprocess.Popen(
                [sys.executable, script],
                cwd=self.script_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT
            )
            
            self.processes[name] = proc
            print(f"  ✓ {name} started (PID: {proc.pid})")
            time.sleep(0.5)  # Give it a moment to start
        
        except Exception as e:
            print(f"  ✗ Failed to start {name}: {e}")
    
    def stop_all(self):
        """Stop all workers."""
        self.running = False
        
        print("Stopping all workers...")
        
        for name, proc in self.processes.items():
            try:
                print(f"  Stopping {name}...")
                proc.terminate()
                proc.wait(timeout=5)
                print(f"  ✓ {name} stopped")
            except subprocess.TimeoutExpired:
                print(f"  ⚠️  {name} did not stop gracefully, killing...")
                proc.kill()
                proc.wait()
            except Exception as e:
                print(f"  ✗ Error stopping {name}: {e}")
        
        self.processes.clear()
        print("\nAll workers stopped.")
    
    def show_status(self):
        """Show status of all workers."""
        from vj_bus.discovery import WorkerDiscovery
        
        print("\n" + "=" * 60)
        print("Worker Status")
        print("=" * 60)
        
        # Discover workers via socket files
        workers = WorkerDiscovery.scan_workers()
        
        if not workers:
            print("No workers found (check /tmp/vj-bus/)")
            return
        
        for worker in workers:
            name = worker['name']
            socket_path = worker['socket_path']
            
            # Test if responsive
            alive = WorkerDiscovery.test_worker(socket_path, timeout=1.0)
            status = "✓ Running" if alive else "✗ Not responding"
            
            print(f"{name:20} {status:20} {socket_path}")


def main():
    """Main entry point."""
    harness = DevHarness()
    
    # Setup signal handlers
    def shutdown_handler(signum, frame):
        print(f"\nReceived signal {signum}")
        harness.stop_all()
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, shutdown_handler)
    signal.signal(signal.SIGINT, shutdown_handler)
    
    # Parse command line args
    if len(sys.argv) > 1:
        if sys.argv[1] == "status":
            harness.show_status()
            return
        elif sys.argv[1] == "stop":
            # Kill all workers
            print("Stopping all workers...")
            import psutil
            for proc in psutil.process_iter(['name', 'cmdline']):
                try:
                    cmdline = proc.info['cmdline']
                    if cmdline and any('vj_' in arg and '_worker.py' in arg for arg in cmdline):
                        print(f"Killing {proc.pid}: {' '.join(cmdline)}")
                        proc.kill()
                except:
                    pass
            return
    
    # Start all workers
    harness.start_all()


if __name__ == "__main__":
    main()
