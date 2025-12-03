"""
Base Worker Class

Abstract base class for all VJ workers.
Handles control socket, heartbeats, and command dispatch.
"""

import os
import time
import signal
import logging
import threading
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
from .control import ControlSocket
from .telemetry import TelemetrySender
from .schema import HeartbeatMessage, CommandMessage, AckMessage, RegisterMessage

logger = logging.getLogger('vj_bus.worker')


class Worker(ABC):
    """
    Base class for all VJ workers.
    
    Provides:
    - Control socket server for commands
    - Heartbeat mechanism
    - Graceful shutdown handling
    - Command dispatch framework
    - OSC telemetry sending
    
    Subclasses must implement:
    - on_start(): Worker-specific initialization
    - on_stop(): Worker-specific cleanup
    - on_command(cmd): Handle command messages
    - get_stats(): Return current stats for heartbeat
    """
    
    HEARTBEAT_INTERVAL = 5.0  # seconds
    
    def __init__(self, name: str, osc_addresses: list = None):
        """
        Initialize worker.
        
        Args:
            name: Worker name (used for socket filename)
            osc_addresses: List of OSC addresses this worker emits
        """
        self.name = name
        self.osc_addresses = osc_addresses or []
        self.control = ControlSocket(name)
        self.telemetry = TelemetrySender()
        self.running = False
        self.start_time = time.time()
        self._clients = []  # Connected clients (TUI, process manager)
        self._shutdown_requested = False
        
        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)
        
        logger.info(f"Worker initialized: {name}")
    
    def _handle_shutdown(self, signum, frame):
        """Graceful shutdown on SIGTERM/SIGINT."""
        logger.info(f"{self.name} received shutdown signal {signum}")
        self._shutdown_requested = True
        self.running = False
    
    def start(self):
        """
        Start worker (creates control socket, starts heartbeat).
        
        This is the main entry point for workers. It blocks until shutdown.
        """
        logger.info(f"Starting worker: {self.name}")
        
        # Create control socket
        self.control.create_server()
        self.running = True
        
        # Register with process manager (if running)
        self._register()
        
        # Start worker-specific initialization
        try:
            self.on_start()
        except Exception as e:
            logger.exception(f"Error in on_start: {e}")
            self.running = False
            self.control.close()
            return
        
        # Main loop
        try:
            self._run_loop()
        except Exception as e:
            logger.exception(f"Fatal error in worker main loop: {e}")
        finally:
            self.stop()
    
    def stop(self):
        """Stop worker gracefully."""
        if not self.running:
            return
        
        logger.info(f"Stopping worker: {self.name}")
        self.running = False
        
        # Worker-specific shutdown
        try:
            self.on_stop()
        except Exception as e:
            logger.exception(f"Error in on_stop: {e}")
        
        # Close all client connections
        for client in self._clients:
            try:
                client.close()
            except:
                pass
        self._clients.clear()
        
        # Close control socket
        self.control.close()
        
        logger.info(f"Worker stopped: {self.name}")
    
    @abstractmethod
    def on_start(self):
        """
        Worker-specific startup logic.
        
        Called after control socket is created.
        Subclasses should initialize resources here.
        """
        pass
    
    @abstractmethod
    def on_stop(self):
        """
        Worker-specific shutdown logic.
        
        Called before control socket is closed.
        Subclasses should cleanup resources here.
        """
        pass
    
    @abstractmethod
    def on_command(self, cmd: CommandMessage) -> AckMessage:
        """
        Handle command from TUI/process manager.
        
        Args:
            cmd: Command message
            
        Returns:
            Acknowledgement message
        """
        pass
    
    @abstractmethod
    def get_stats(self) -> Dict[str, Any]:
        """
        Get current stats for heartbeat.
        
        Returns:
            Dict with worker-specific statistics
        """
        pass
    
    def _run_loop(self):
        """
        Main worker loop.
        
        Handles:
        - Heartbeat sending
        - Control socket connections
        - Command dispatch
        """
        last_heartbeat = 0
        
        while self.running and not self._shutdown_requested:
            now = time.time()
            
            # Send heartbeat every HEARTBEAT_INTERVAL seconds
            if now - last_heartbeat > self.HEARTBEAT_INTERVAL:
                self._send_heartbeat()
                last_heartbeat = now
            
            # Accept new connections (non-blocking)
            client = self.control.accept(timeout=0.1)
            if client:
                self._clients.append(client)
                logger.debug(f"New client connected to {self.name}")
            
            # Handle commands from all clients
            for client in self._clients[:]:  # Copy list to allow removal
                try:
                    msg = client.recv_message(timeout=0.01)
                    if msg:
                        self._handle_message(client, msg)
                except Exception as e:
                    logger.error(f"Error handling client message: {e}")
                    # Remove dead client
                    self._clients.remove(client)
                    client.close()
            
            # Small sleep to prevent busy waiting
            time.sleep(0.05)
    
    def _handle_message(self, client: ControlSocket, msg: Dict[str, Any]):
        """
        Handle incoming message from client.
        
        Args:
            client: Client socket
            msg: Message dict
        """
        msg_type = msg.get('type')
        
        if msg_type == 'command':
            try:
                cmd = CommandMessage(**msg)
                ack = self.on_command(cmd)
                ack.msg_id = cmd.msg_id
                client.send_message(ack)
            except Exception as e:
                logger.exception(f"Error handling command: {e}")
                error_ack = AckMessage(
                    msg_id=msg.get('msg_id'),
                    success=False,
                    message=f"Error: {e}"
                )
                client.send_message(error_ack)
        else:
            logger.warning(f"Unknown message type: {msg_type}")
    
    def _send_heartbeat(self):
        """Send heartbeat to all connected clients."""
        try:
            heartbeat = HeartbeatMessage(
                worker=self.name,
                pid=os.getpid(),
                uptime_sec=time.time() - self.start_time,
                stats=self.get_stats()
            )
            
            # Send to all clients
            for client in self._clients[:]:
                try:
                    client.send_message(heartbeat)
                except Exception as e:
                    logger.debug(f"Failed to send heartbeat to client: {e}")
                    # Remove dead client
                    self._clients.remove(client)
                    client.close()
            
            logger.debug(f"Heartbeat sent: uptime={heartbeat.uptime_sec:.1f}s, stats={heartbeat.stats}")
        
        except Exception as e:
            logger.error(f"Error sending heartbeat: {e}")
    
    def _register(self):
        """
        Register with process manager (if running).
        
        Attempts to connect to process manager socket and send registration.
        Silently fails if process manager is not running.
        """
        try:
            pm_socket = ControlSocket(f"{self.name}_pm_client")
            if pm_socket.connect(timeout=0.5):
                # Send registration
                reg = RegisterMessage(
                    worker=self.name,
                    pid=os.getpid(),
                    socket_path=str(self.control.socket_path),
                    osc_addresses=self.osc_addresses
                )
                pm_socket.send_message(reg)
                pm_socket.close()
                logger.info(f"Registered with process manager")
            else:
                logger.debug("Process manager not running (registration skipped)")
        except Exception as e:
            logger.debug(f"Failed to register with process manager: {e}")
