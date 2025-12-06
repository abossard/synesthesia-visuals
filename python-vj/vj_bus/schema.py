"""
Message Schema for VJ Bus

Defines Pydantic models for all IPC messages.
Messages are serialized as JSON and sent over Unix sockets.
"""

from pydantic import BaseModel, Field
from typing import Literal, Optional, Dict, Any, List
from enum import Enum


class MessageType(str, Enum):
    """Types of messages in the VJ Bus protocol."""
    HEARTBEAT = "heartbeat"
    COMMAND = "command"
    ACK = "ack"
    RESPONSE = "response"
    REGISTER = "register"
    ERROR = "error"


class BaseMessage(BaseModel):
    """Base class for all VJ Bus messages."""
    type: MessageType
    msg_id: Optional[str] = None  # For request/response correlation
    
    class Config:
        use_enum_values = True


class HeartbeatMessage(BaseMessage):
    """
    Heartbeat message sent by workers to process manager and TUI.
    
    Sent every 5 seconds to indicate worker is alive and healthy.
    Contains worker stats for monitoring.
    """
    type: Literal[MessageType.HEARTBEAT] = MessageType.HEARTBEAT
    worker: str  # Worker name (e.g., "audio_analyzer")
    pid: int  # Process ID
    uptime_sec: float  # Time since worker started
    stats: Dict[str, Any] = Field(default_factory=dict)  # Worker-specific stats


class CommandMessage(BaseMessage):
    """
    Command message sent from TUI/process manager to workers.
    
    Supports commands like:
    - get_state: Request current worker state
    - set_config: Update worker configuration
    - restart: Gracefully restart worker
    
    Additional fields can be added per command using Pydantic's extra="allow".
    """
    type: Literal[MessageType.COMMAND] = MessageType.COMMAND
    cmd: str  # Command name
    
    class Config:
        extra = "allow"  # Allow additional fields based on cmd


class AckMessage(BaseMessage):
    """
    Acknowledgement message sent in response to commands.
    
    Indicates success/failure of command execution.
    """
    type: Literal[MessageType.ACK] = MessageType.ACK
    success: bool
    message: Optional[str] = None  # Human-readable status message
    data: Optional[Dict[str, Any]] = None  # Optional additional data


class ResponseMessage(BaseMessage):
    """
    Response message with data payload.
    
    Used for get_state and other query commands.
    """
    type: Literal[MessageType.RESPONSE] = MessageType.RESPONSE
    data: Dict[str, Any]


class RegisterMessage(BaseMessage):
    """
    Registration message sent by workers to process manager on startup.
    
    Informs process manager about worker's existence and capabilities.
    """
    type: Literal[MessageType.REGISTER] = MessageType.REGISTER
    worker: str  # Worker name
    pid: int  # Process ID
    socket_path: str  # Path to worker's control socket
    osc_addresses: List[str] = Field(default_factory=list)  # OSC addresses worker emits


class ErrorMessage(BaseMessage):
    """
    Error message indicating a failure in message processing.
    """
    type: Literal[MessageType.ERROR] = MessageType.ERROR
    error: str  # Error description
    traceback: Optional[str] = None  # Full traceback for debugging
