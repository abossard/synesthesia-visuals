"""
Unix Domain Socket Control Plane

Provides reliable, bidirectional communication for control messages
between TUI, process manager, and workers.
"""

import socket
import json
import struct
import logging
from pathlib import Path
from typing import Optional, Dict, Any
from .schema import BaseMessage

logger = logging.getLogger('vj_bus.control')


class ControlSocket:
    """
    Unix domain socket for control plane communication.
    
    Features:
    - Length-prefixed JSON messages (reliable framing)
    - Request/response pattern via msg_id correlation
    - Connection-aware (detects worker death)
    - File-based discovery (/tmp/vj-bus/*.sock)
    """
    
    SOCKET_DIR = Path("/tmp/vj-bus")
    MAX_MESSAGE_SIZE = 1024 * 1024  # 1 MB
    
    def __init__(self, name: str):
        """
        Initialize control socket.
        
        Args:
            name: Socket name (e.g., "audio_analyzer", "tui_client")
        """
        self.name = name
        self.socket_path = self.SOCKET_DIR / f"{name}.sock"
        self.sock: Optional[socket.socket] = None
        self._ensure_socket_dir()
    
    def _ensure_socket_dir(self):
        """Create socket directory if it doesn't exist."""
        self.SOCKET_DIR.mkdir(parents=True, exist_ok=True)
    
    def create_server(self) -> None:
        """
        Create server socket (for workers and process manager).
        
        Removes stale socket file if it exists.
        """
        # Remove stale socket
        if self.socket_path.exists():
            try:
                self.socket_path.unlink()
            except Exception as e:
                logger.warning(f"Failed to remove stale socket {self.socket_path}: {e}")
        
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.bind(str(self.socket_path))
        self.sock.listen(5)
        logger.info(f"Control socket listening: {self.socket_path}")
    
    def connect(self, timeout: float = 1.0) -> bool:
        """
        Connect to server socket (for TUI/clients).
        
        Args:
            timeout: Connection timeout in seconds
            
        Returns:
            True if connected successfully, False otherwise
        """
        try:
            self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.sock.settimeout(timeout)
            self.sock.connect(str(self.socket_path))
            logger.info(f"Connected to {self.socket_path}")
            return True
        except FileNotFoundError:
            logger.debug(f"Socket not found: {self.socket_path}")
            return False
        except Exception as e:
            logger.error(f"Failed to connect to {self.socket_path}: {e}")
            return False
    
    def send_message(self, msg: BaseMessage) -> bool:
        """
        Send message (length-prefixed JSON).
        
        Format: [4-byte length (big-endian)][JSON payload]
        
        Args:
            msg: Message to send (Pydantic model)
            
        Returns:
            True if sent successfully, False otherwise
        """
        if not self.sock:
            logger.error("Socket not connected")
            return False
        
        try:
            data = msg.model_dump_json().encode('utf-8')
            length = struct.pack('>I', len(data))  # Big-endian 4-byte length
            self.sock.sendall(length + data)
            return True
        except Exception as e:
            logger.error(f"Failed to send message: {e}")
            return False
    
    def recv_message(self, timeout: float = 1.0) -> Optional[Dict[str, Any]]:
        """
        Receive message (length-prefixed JSON).
        
        Args:
            timeout: Receive timeout in seconds
            
        Returns:
            Message dict if received, None if timeout or error
        """
        if not self.sock:
            logger.error("Socket not connected")
            return None
        
        try:
            self.sock.settimeout(timeout)
            
            # Read 4-byte length prefix
            length_data = self._recv_exact(4)
            if not length_data:
                return None
            
            length = struct.unpack('>I', length_data)[0]
            if length > self.MAX_MESSAGE_SIZE:
                logger.error(f"Message too large: {length} bytes (max {self.MAX_MESSAGE_SIZE})")
                return None
            
            # Read message body
            data = self._recv_exact(length)
            if not data:
                return None
            
            return json.loads(data.decode('utf-8'))
        
        except socket.timeout:
            return None
        except Exception as e:
            logger.debug(f"Failed to receive message: {e}")
            return None
    
    def _recv_exact(self, n: int) -> Optional[bytes]:
        """
        Receive exactly n bytes.
        
        Args:
            n: Number of bytes to receive
            
        Returns:
            Bytes if successful, None if connection closed
        """
        data = b''
        while len(data) < n:
            chunk = self.sock.recv(n - len(data))
            if not chunk:
                return None  # Connection closed
            data += chunk
        return data
    
    def accept(self, timeout: float = 1.0) -> Optional['ControlSocket']:
        """
        Accept incoming connection (for server sockets).
        
        Args:
            timeout: Accept timeout in seconds
            
        Returns:
            New ControlSocket for the connection, or None if timeout
        """
        if not self.sock:
            logger.error("Socket not created as server")
            return None
        
        try:
            self.sock.settimeout(timeout)
            conn, addr = self.sock.accept()
            
            # Create new ControlSocket wrapping the connection
            client_sock = ControlSocket(f"{self.name}_client")
            client_sock.sock = conn
            logger.debug(f"Accepted connection on {self.socket_path}")
            return client_sock
        
        except socket.timeout:
            return None
        except Exception as e:
            logger.error(f"Failed to accept connection: {e}")
            return None
    
    def close(self):
        """Close socket and cleanup."""
        if self.sock:
            try:
                self.sock.close()
            except Exception as e:
                logger.debug(f"Error closing socket: {e}")
            finally:
                self.sock = None
        
        # Remove socket file if we created it (server side)
        if self.socket_path.exists():
            try:
                self.socket_path.unlink()
                logger.debug(f"Removed socket file: {self.socket_path}")
            except Exception as e:
                logger.debug(f"Failed to remove socket file: {e}")
    
    def __enter__(self):
        """Context manager support."""
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager cleanup."""
        self.close()
