"""
Worker Discovery Protocol

Discovers running workers by scanning socket files in /tmp/vj-bus/.
Tests worker responsiveness via control socket connection.
"""

from pathlib import Path
from typing import List, Dict, Optional
from .control import ControlSocket
from .schema import CommandMessage
import logging

logger = logging.getLogger('vj_bus.discovery')


class WorkerDiscovery:
    """
    Worker discovery via socket file scanning.
    
    Workers create control sockets at /tmp/vj-bus/{worker_name}.sock.
    Discovery scans this directory and tests connections.
    """
    
    @staticmethod
    def scan_workers() -> List[Dict[str, str]]:
        """
        Scan /tmp/vj-bus/ for worker sockets.
        
        Returns:
            List of dicts with 'name' and 'socket_path' keys
        """
        workers = []
        socket_dir = ControlSocket.SOCKET_DIR
        
        if not socket_dir.exists():
            logger.debug(f"Socket directory does not exist: {socket_dir}")
            return workers
        
        for sock_file in socket_dir.glob("*.sock"):
            name = sock_file.stem  # Remove .sock extension
            
            # Skip client sockets (temporary connection sockets)
            if "_client" in name or name.startswith("test"):
                continue
            
            workers.append({
                'name': name,
                'socket_path': str(sock_file)
            })
        
        logger.info(f"Discovered {len(workers)} workers: {[w['name'] for w in workers]}")
        return workers
    
    @staticmethod
    def test_worker(socket_path: str, timeout: float = 1.0) -> bool:
        """
        Test if worker is responsive.
        
        Attempts to connect to worker's control socket.
        
        Args:
            socket_path: Path to worker's socket file
            timeout: Connection timeout
            
        Returns:
            True if worker responds, False otherwise
        """
        try:
            # Extract worker name from socket path
            name = Path(socket_path).stem
            
            # Create temporary client socket
            client = ControlSocket(f"test_{name}_client")
            
            # Try to connect
            if client.connect(timeout):
                # Send ping command (get_state)
                cmd = CommandMessage(cmd="get_state", msg_id="discovery_ping")
                if client.send_message(cmd):
                    # Wait for response
                    response = client.recv_message(timeout)
                    client.close()
                    
                    if response:
                        logger.debug(f"Worker {name} is responsive")
                        return True
            
            client.close()
            logger.debug(f"Worker {name} did not respond")
            return False
        
        except Exception as e:
            logger.debug(f"Error testing worker {socket_path}: {e}")
            return False
    
    @staticmethod
    def connect_to_worker(name: str, timeout: float = 1.0) -> Optional['ControlSocket']:
        """
        Connect to a specific worker by name.
        
        Args:
            name: Worker name (e.g., "audio_analyzer")
            timeout: Connection timeout
            
        Returns:
            Connected ControlSocket, or None if failed
        """
        try:
            client = ControlSocket(f"{name}_client")
            if client.connect(timeout):
                logger.info(f"Connected to worker: {name}")
                return client
            
            logger.warning(f"Failed to connect to worker: {name}")
            return None
        
        except Exception as e:
            logger.error(f"Error connecting to worker {name}: {e}")
            return None
