#!/usr/bin/env python3
"""
VJ Console Worker Integration Example

Demonstrates how to integrate WorkerCoordinator into vj_console.py.
This would be added to the existing VJConsoleApp class.
"""

from worker_coordinator import WorkerCoordinator
import time


class WorkerIntegrationMixin:
    """
    Mixin to add worker integration to VJConsoleApp.
    
    Usage in vj_console.py:
    
    class VJConsoleApp(App, WorkerIntegrationMixin):
        def __init__(self):
            super().__init__()
            self.worker_coordinator = WorkerCoordinator()
        
        def on_mount(self):
            # Start worker coordinator
            self.worker_coordinator.start()
            
            # Setup periodic state refresh
            self.set_interval(2.0, self.refresh_worker_states)
        
        def on_unmount(self):
            # Stop worker coordinator
            self.worker_coordinator.stop()
    """
    
    def refresh_worker_states(self):
        """Refresh worker states (call periodically)."""
        if not hasattr(self, 'worker_coordinator'):
            return
        
        states = self.worker_coordinator.get_all_states()
        
        # Update UI with worker states
        # Example: self.worker_status_widget.update(states)
    
    def get_worker_status_text(self) -> str:
        """Get formatted worker status for UI display."""
        if not hasattr(self, 'worker_coordinator'):
            return "Worker coordinator not initialized"
        
        lines = []
        lines.append("=== Worker Status ===")
        
        for worker in self.worker_coordinator.get_all_workers():
            status_icon = "●" if worker.connected else "○"
            status_text = "Connected" if worker.connected else "Disconnected"
            color = "green" if worker.connected else "dim"
            
            lines.append(f"[{color}]{status_icon} {worker.name:20} {status_text}[/]")
            
            # Show worker-specific state
            if worker.last_state:
                for key, value in worker.last_state.items():
                    if key not in ['status', 'running']:  # Skip redundant fields
                        lines.append(f"  {key}: {value}")
        
        return "\n".join(lines)
    
    def handle_worker_command(self, worker_name: str, command: str, **kwargs):
        """Send a command to a worker (e.g., from button press)."""
        if not hasattr(self, 'worker_coordinator'):
            return
        
        response = self.worker_coordinator.send_command(worker_name, command, **kwargs)
        
        if response and response.get('success'):
            # Update UI with success message
            # Example: self.show_notification(f"Command successful: {command}")
            pass
        else:
            # Update UI with error message
            message = response.get('message', 'Unknown error') if response else 'No response'
            # Example: self.show_notification(f"Command failed: {message}", severity="error")
            pass


def demo_worker_integration():
    """Demo showing worker integration in action."""
    print("VJ Console Worker Integration Demo")
    print("=" * 60)
    
    # Create coordinator
    coordinator = WorkerCoordinator()
    coordinator.start()
    
    # Wait for discovery
    print("\nDiscovering workers...")
    time.sleep(3)
    
    # Show discovered workers
    workers = coordinator.get_all_workers()
    print(f"\nFound {len(workers)} workers:")
    for worker in workers:
        print(f"  - {worker.name} ({worker.socket_path})")
    
    # Get state from all workers
    print("\nFetching worker states...")
    states = coordinator.get_all_states()
    for name, state in states.items():
        print(f"\n{name}:")
        for key, value in state.items():
            print(f"  {key}: {value}")
    
    # Demo: Send command to process manager
    if coordinator.is_worker_running('process_manager'):
        print("\nSending get_state command to process manager...")
        response = coordinator.send_command('process_manager', 'get_state')
        if response:
            print(f"Response: {response}")
    
    # Cleanup
    print("\nStopping coordinator...")
    coordinator.stop()
    print("Demo complete!")


if __name__ == "__main__":
    demo_worker_integration()
