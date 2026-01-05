#!/usr/bin/env python3
"""
Worker Coordinator - TUI Integration Layer

Discovers and manages connections to VJ worker processes.
Provides a clean interface for vj_console.py to interact with workers.
"""

import logging
import time
from typing import Dict, List, Optional, Any
from threading import Thread, Lock

from vj_bus import WorkerDiscovery, ControlSocket, TelemetrySender
from vj_bus.schema import CommandMessage, AckMessage

logger = logging.getLogger('worker_coordinator')


class WorkerConnection:
    """Represents a connection to a worker process."""
    
    def __init__(self, name: str, socket_path: str):
        self.name = name
        self.socket_path = socket_path
        self.socket: Optional[ControlSocket] = None
        self.connected = False
        self.last_state = {}
        self.last_heartbeat = 0
    
    def connect(self, timeout: float = 2.0) -> bool:
        """Connect to worker."""
        if self.connected and self.socket:
            return True
        
        try:
            self.socket = ControlSocket(f"{self.name}_tui_client")
            if self.socket.connect(timeout=timeout):
                self.connected = True
                self.last_heartbeat = time.time()
                logger.info(f"Connected to {self.name}")
                return True
        except Exception as e:
            logger.error(f"Failed to connect to {self.name}: {e}")
        
        self.connected = False
        return False
    
    def disconnect(self):
        """Disconnect from worker."""
        if self.socket:
            try:
                self.socket.close()
            except:
                pass
            self.socket = None
        self.connected = False
    
    def send_command(self, command: str, timeout: float = 2.0, **kwargs) -> Optional[Dict[str, Any]]:
        """Send a command to the worker and return response."""
        if not self.connected or not self.socket:
            if not self.connect():
                return None
        
        try:
            cmd = CommandMessage(cmd=command, msg_id=f"{self.name}_{command}_{time.time()}", **kwargs)
            if self.socket.send_message(cmd):
                response = self.socket.recv_message(timeout=timeout)
                if response:
                    self.last_heartbeat = time.time()
                    return response
        except Exception as e:
            logger.error(f"Error sending command to {self.name}: {e}")
            self.connected = False
        
        return None
    
    def get_state(self) -> Optional[Dict[str, Any]]:
        """Get current state from worker."""
        response = self.send_command("get_state")
        if response and response.get('success'):
            self.last_state = response.get('data', {})
            return self.last_state
        return None


class WorkerCoordinator:
    """
    Coordinates connections to all worker processes.
    
    Provides:
    - Worker discovery and connection
    - Command sending to workers
    - State polling from workers
    - Automatic reconnection
    """
    
    def __init__(self):
        self.workers: Dict[str, WorkerConnection] = {}
        self.discovery_thread: Optional[Thread] = None
        self.running = False
        self.lock = Lock()
        
        self.discovery_interval = 5.0  # Rediscover every 5 seconds
        self.state_poll_interval = 2.0  # Poll state every 2 seconds
    
    def start(self):
        """Start worker coordinator."""
        logger.info("Starting worker coordinator...")
        self.running = True
        
        # Initial discovery
        self.discover_workers()
        
        # Start background discovery thread
        self.discovery_thread = Thread(target=self._discovery_loop, daemon=True)
        self.discovery_thread.start()
        
        logger.info("Worker coordinator started")
    
    def stop(self):
        """Stop worker coordinator."""
        logger.info("Stopping worker coordinator...")
        self.running = False
        
        # Disconnect from all workers
        with self.lock:
            for worker in self.workers.values():
                worker.disconnect()
        
        logger.info("Worker coordinator stopped")
    
    def discover_workers(self) -> List[str]:
        """Discover available workers."""
        try:
            found = WorkerDiscovery.scan_workers()
            
            with self.lock:
                # Add new workers
                for worker_info in found:
                    name = worker_info['name']
                    socket_path = worker_info['socket_path']
                    
                    if name not in self.workers:
                        worker = WorkerConnection(name, socket_path)
                        self.workers[name] = worker
                        logger.info(f"Discovered worker: {name}")
                    else:
                        # Update socket path if changed
                        self.workers[name].socket_path = socket_path
                
                # Remove workers that are no longer found
                current_names = {w['name'] for w in found}
                removed = [name for name in self.workers if name not in current_names]
                for name in removed:
                    self.workers[name].disconnect()
                    del self.workers[name]
                    logger.info(f"Worker removed: {name}")
            
            return list(self.workers.keys())
        
        except Exception as e:
            logger.error(f"Error discovering workers: {e}")
            return []
    
    def get_worker(self, name: str) -> Optional[WorkerConnection]:
        """Get a specific worker connection."""
        with self.lock:
            return self.workers.get(name)
    
    def get_all_workers(self) -> List[WorkerConnection]:
        """Get all worker connections."""
        with self.lock:
            return list(self.workers.values())
    
    def send_command(self, worker_name: str, command: str, **kwargs) -> Optional[Dict[str, Any]]:
        """Send a command to a specific worker."""
        worker = self.get_worker(worker_name)
        if worker:
            return worker.send_command(command, **kwargs)
        return None
    
    def get_worker_state(self, worker_name: str) -> Optional[Dict[str, Any]]:
        """Get state from a specific worker."""
        worker = self.get_worker(worker_name)
        if worker:
            return worker.get_state()
        return None
    
    def get_all_states(self) -> Dict[str, Dict[str, Any]]:
        """Get state from all workers."""
        states = {}
        for worker in self.get_all_workers():
            state = worker.get_state()
            if state:
                states[worker.name] = state
        return states
    
    def _discovery_loop(self):
        """Background loop for worker discovery and state polling."""
        last_discovery = 0
        last_poll = 0
        
        while self.running:
            now = time.time()
            
            # Periodic discovery
            if now - last_discovery >= self.discovery_interval:
                self.discover_workers()
                last_discovery = now
            
            # Periodic state polling (keeps connections alive)
            if now - last_poll >= self.state_poll_interval:
                self.get_all_states()
                last_poll = now
            
            time.sleep(0.5)
    
    def is_worker_running(self, worker_name: str) -> bool:
        """Check if a worker is running and connected."""
        worker = self.get_worker(worker_name)
        return worker is not None and worker.connected
    
    def restart_worker(self, worker_name: str) -> bool:
        """Request a worker to restart (via process manager)."""
        pm = self.get_worker('process_manager')
        if pm:
            response = pm.send_command('restart_worker', worker=worker_name)
            return response is not None and response.get('success', False)
        return False
    
    def start_worker(self, worker_name: str) -> bool:
        """Request process manager to start a worker."""
        pm = self.get_worker('process_manager')
        if pm:
            response = pm.send_command('start_worker', worker=worker_name)
            return response is not None and response.get('success', False)
        return False
    
    def stop_worker(self, worker_name: str) -> bool:
        """Request process manager to stop a worker."""
        pm = self.get_worker('process_manager')
        if pm:
            response = pm.send_command('stop_worker', worker=worker_name)
            return response is not None and response.get('success', False)
        return False
