"""Modules package for VJ system."""
from modules.base import Module
from modules.registry import ModuleRegistry, ModuleRegistryConfig

__all__ = [
    "Module",
    "ModuleRegistry",
    "ModuleRegistryConfig",
]
