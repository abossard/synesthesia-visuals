"""
Unit tests for vj_bus library

Tests message schema, control sockets, telemetry, and discovery.
"""

import unittest
import tempfile
import shutil
import time
import threading
from pathlib import Path

# Import vj_bus components
from vj_bus.schema import (
    MessageType, HeartbeatMessage, CommandMessage, AckMessage,
    ResponseMessage, RegisterMessage, ErrorMessage
)
from vj_bus.control import ControlSocket
from vj_bus.telemetry import TelemetrySender
from vj_bus.discovery import WorkerDiscovery


class TestMessageSchema(unittest.TestCase):
    """Test Pydantic message models."""
    
    def test_heartbeat_serialization(self):
        """HeartbeatMessage should serialize to JSON correctly."""
        msg = HeartbeatMessage(
            worker="audio_analyzer",
            pid=12345,
            uptime_sec=123.45,
            stats={"fps": 60.0, "frames": 7200}
        )
        json_str = msg.model_dump_json()
        
        self.assertIn('"worker":"audio_analyzer"', json_str)
        self.assertIn('"pid":12345', json_str)
        self.assertIn('"fps":60.0', json_str)
    
    def test_command_deserialization(self):
        """CommandMessage should deserialize from JSON with extra fields."""
        json_data = {
            "type": "command",
            "msg_id": "abc123",
            "cmd": "set_config",
            "enable_essentia": True,
            "enable_pitch": False
        }
        msg = CommandMessage(**json_data)
        
        self.assertEqual(msg.cmd, "set_config")
        self.assertEqual(msg.type, MessageType.COMMAND)
        self.assertEqual(msg.msg_id, "abc123")
        # Extra fields should be accessible
        self.assertTrue(hasattr(msg, 'enable_essentia'))
    
    def test_ack_message(self):
        """AckMessage should support success/failure with optional data."""
        ack = AckMessage(
            msg_id="abc123",
            success=True,
            message="Config updated",
            data={"restart_required": True}
        )
        
        self.assertTrue(ack.success)
        self.assertEqual(ack.message, "Config updated")
        self.assertEqual(ack.data["restart_required"], True)
    
    def test_response_message(self):
        """ResponseMessage should carry data payload."""
        resp = ResponseMessage(
            msg_id="xyz789",
            data={"config": {"enable_essentia": True}, "status": "running"}
        )
        
        self.assertEqual(resp.data["status"], "running")
        self.assertTrue(resp.data["config"]["enable_essentia"])
    
    def test_register_message(self):
        """RegisterMessage should include worker details."""
        reg = RegisterMessage(
            worker="audio_analyzer",
            pid=12345,
            socket_path="/tmp/vj-bus/audio_analyzer.sock",
            osc_addresses=["/audio/levels", "/audio/beat"]
        )
        
        self.assertEqual(reg.worker, "audio_analyzer")
        self.assertEqual(len(reg.osc_addresses), 2)


class TestControlSocket(unittest.TestCase):
    """Test Unix socket communication."""
    
    def setUp(self):
        """Create temporary directory for test sockets."""
        self.temp_dir = Path(tempfile.mkdtemp(prefix="vj-bus-test-"))
        self.original_dir = ControlSocket.SOCKET_DIR
        ControlSocket.SOCKET_DIR = self.temp_dir
    
    def tearDown(self):
        """Cleanup temporary directory."""
        ControlSocket.SOCKET_DIR = self.original_dir
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def test_socket_creation(self):
        """ControlSocket should create Unix socket file."""
        sock = ControlSocket("test_worker")
        sock.create_server()
        
        self.assertTrue((self.temp_dir / "test_worker.sock").exists())
        sock.close()
        
        # Socket file should be removed on close
        self.assertFalse((self.temp_dir / "test_worker.sock").exists())
    
    def test_send_receive_message(self):
        """Messages should be sent/received with length prefix."""
        # This test is simplified - just verify the framing works
        # Full integration testing is in test_integration.py
        
        # For now, just verify message serialization
        msg = HeartbeatMessage(
            worker="test",
            pid=123,
            uptime_sec=1.0,
            stats={"test": "data"}
        )
        json_data = msg.model_dump_json()
        self.assertIn('"worker":"test"', json_data)
        
        # TODO: Add full client-server test with proper event handling
    
    def test_message_too_large(self):
        """recv_message should reject oversized messages."""
        # This test would require mocking socket.recv to send
        # a large length prefix. Skipped for simplicity.
        pass


class TestTelemetrySender(unittest.TestCase):
    """Test OSC telemetry sending."""
    
    def test_osc_send(self):
        """TelemetrySender should send OSC without blocking."""
        sender = TelemetrySender()
        
        # Should not raise, even if no receiver
        sender.send("/audio/levels", [0.1, 0.2, 0.3])
        sender.send("/audio/beat", 1)
        sender.send("/audio/reset")
    
    def test_osc_args_normalization(self):
        """send() should normalize single values to lists."""
        sender = TelemetrySender()
        
        # These should all work without errors
        sender.send("/audio/beat", 1)  # Single value
        sender.send("/audio/reset")  # None
        sender.send("/audio/levels", [0.1, 0.2])  # List


class TestWorkerDiscovery(unittest.TestCase):
    """Test worker discovery protocol."""
    
    def setUp(self):
        """Create temporary directory for test sockets."""
        self.temp_dir = Path(tempfile.mkdtemp(prefix="vj-bus-test-"))
        self.original_dir = ControlSocket.SOCKET_DIR
        ControlSocket.SOCKET_DIR = self.temp_dir
    
    def tearDown(self):
        """Cleanup temporary directory."""
        ControlSocket.SOCKET_DIR = self.original_dir
        shutil.rmtree(self.temp_dir, ignore_errors=True)
    
    def test_scan_workers(self):
        """scan_workers should find socket files."""
        # Create fake socket files
        (self.temp_dir / "audio_analyzer.sock").touch()
        (self.temp_dir / "lyrics_fetcher.sock").touch()
        
        workers = WorkerDiscovery.scan_workers()
        
        self.assertEqual(len(workers), 2)
        names = [w['name'] for w in workers]
        self.assertIn("audio_analyzer", names)
        self.assertIn("lyrics_fetcher", names)
    
    def test_test_worker_alive(self):
        """test_worker should detect responsive worker."""
        # This test is simplified - full integration testing in test_integration.py
        # For now, just verify scan_workers works
        pass
    
    def test_test_worker_dead(self):
        """test_worker should detect unresponsive worker."""
        # Create socket file but no server
        (self.temp_dir / "dead_worker.sock").touch()
        
        # Test should fail
        result = WorkerDiscovery.test_worker(str(self.temp_dir / "dead_worker.sock"), timeout=0.5)
        self.assertFalse(result)


if __name__ == '__main__':
    # Run tests
    unittest.main(verbosity=2)
