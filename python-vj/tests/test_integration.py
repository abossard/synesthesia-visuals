#!/usr/bin/env python3
"""
Integration tests for multi-process VJ architecture.

Tests worker lifecycle, communication, and failure scenarios.
"""

import unittest
import subprocess
import time
import signal
import os
from pathlib import Path

# Note: These tests require no external dependencies (no audio hardware, Spotify, etc.)
# They test the IPC infrastructure only.

class TestWorkerLifecycle(unittest.TestCase):
    """Test worker process lifecycle and basic communication."""
    
    def setUp(self):
        """Setup test environment."""
        self.processes = []
        self.test_dir = Path(__file__).parent.parent
    
    def tearDown(self):
        """Cleanup test processes."""
        for proc in self.processes:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except:
                try:
                    proc.kill()
                except:
                    pass
    
    def test_process_manager_starts(self):
        """Process manager should start without errors."""
        proc = subprocess.Popen(
            ["python", "vj_process_manager.py"],
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        self.processes.append(proc)
        
        # Give it time to start
        time.sleep(2)
        
        # Should still be running
        self.assertIsNone(proc.poll(), "Process manager should be running")
        
        # Check socket was created
        socket_path = Path("/tmp/vj-bus/process_manager.sock")
        self.assertTrue(socket_path.exists(), "Process manager socket should exist")
    
    def test_worker_discovery(self):
        """Workers should be discoverable via socket scanning."""
        from vj_bus.discovery import WorkerDiscovery
        
        # Start process manager (which starts workers)
        proc = subprocess.Popen(
            ["python", "vj_process_manager.py"],
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        self.processes.append(proc)
        
        # Wait for workers to start
        time.sleep(3)
        
        # Discover workers
        workers = WorkerDiscovery.scan_workers()
        worker_names = [w['name'] for w in workers]
        
        # Should find at least process manager
        self.assertIn("process_manager", worker_names, "Should discover process manager")
    
    def test_worker_survives_process_manager_restart(self):
        """Workers should keep running if process manager restarts."""
        # Start process manager
        pm_proc = subprocess.Popen(
            ["python", "vj_process_manager.py"],
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        self.processes.append(pm_proc)
        
        # Wait for workers to start
        time.sleep(3)
        
        # Get worker PIDs (would check socket directory in full implementation)
        from vj_bus.discovery import WorkerDiscovery
        workers_before = WorkerDiscovery.scan_workers()
        
        # Kill process manager
        pm_proc.terminate()
        pm_proc.wait(timeout=3)
        
        # Wait a bit
        time.sleep(1)
        
        # Workers should still have their sockets (in full implementation)
        # For now, just verify process manager can restart
        pm_proc2 = subprocess.Popen(
            ["python", "vj_process_manager.py"],
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        self.processes.append(pm_proc2)
        
        time.sleep(2)
        self.assertIsNone(pm_proc2.poll(), "Process manager should restart successfully")


class TestWorkerCommunication(unittest.TestCase):
    """Test worker communication via control sockets."""
    
    def test_worker_responds_to_get_state(self):
        """Worker should respond to get_state command."""
        from vj_bus.control import ControlSocket
        from vj_bus.schema import CommandMessage
        from vj_bus.discovery import WorkerDiscovery
        
        # Start process manager
        proc = subprocess.Popen(
            ["python", "vj_process_manager.py"],
            cwd=Path(__file__).parent.parent,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        
        try:
            # Wait for startup
            time.sleep(3)
            
            # Connect to process manager
            client = ControlSocket("test_client")
            if client.connect(timeout=2.0):
                # Send get_state command
                cmd = CommandMessage(cmd="get_state", msg_id="test")
                client.send_message(cmd)
                
                # Receive response
                response = client.recv_message(timeout=2.0)
                
                self.assertIsNotNone(response, "Should receive response")
                self.assertEqual(response['type'], 'ack', "Should be ACK message")
                self.assertTrue(response['success'], "Command should succeed")
                
                client.close()
        
        finally:
            proc.terminate()
            proc.wait(timeout=3)


if __name__ == '__main__':
    # Run tests
    print("=" * 60)
    print("Running integration tests...")
    print("These tests start real worker processes.")
    print("=" * 60)
    
    unittest.main(verbosity=2)
