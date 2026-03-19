"""
shader_versions — Versioned AI Shader History for TermVJ
========================================================
Stores each AI-generated visualization as an immutable version,
enabling rollback/forward navigation through iterations.
"""

import json
import os
import time
import uuid
from dataclasses import dataclass, field, asdict
from typing import Optional


@dataclass(frozen=True)
class ShaderVersion:
    """Immutable snapshot of an AI-generated visualization."""
    id: str
    code: str
    prompt: str
    timestamp: float
    parent_id: Optional[str] = None
    screenshot_path: Optional[str] = None
    iteration: int = 0
    description: str = ""

    @staticmethod
    def create(code: str, prompt: str, parent_id: Optional[str] = None,
               screenshot_path: Optional[str] = None, iteration: int = 0,
               description: str = "") -> "ShaderVersion":
        return ShaderVersion(
            id=uuid.uuid4().hex[:8],
            code=code,
            prompt=prompt,
            timestamp=time.time(),
            parent_id=parent_id,
            screenshot_path=screenshot_path,
            iteration=iteration,
            description=description,
        )


class ShaderVersionStore:
    """Ordered collection of shader versions with cursor navigation.

    Versions are append-only. The cursor tracks which version is active.
    Supports save/load to JSON for persistence across sessions.
    """

    def __init__(self):
        self._versions: list[ShaderVersion] = []
        self._cursor: int = -1

    @property
    def versions(self) -> list[ShaderVersion]:
        return list(self._versions)

    @property
    def cursor(self) -> int:
        return self._cursor

    @property
    def current(self) -> Optional[ShaderVersion]:
        if 0 <= self._cursor < len(self._versions):
            return self._versions[self._cursor]
        return None

    @property
    def count(self) -> int:
        return len(self._versions)

    def add(self, version: ShaderVersion) -> None:
        """Append a new version and move cursor to it."""
        self._versions.append(version)
        self._cursor = len(self._versions) - 1

    def go_prev(self) -> Optional[ShaderVersion]:
        """Move cursor to previous version. Returns it, or None if at start."""
        if self._cursor > 0:
            self._cursor -= 1
            return self.current
        return None

    def go_next(self) -> Optional[ShaderVersion]:
        """Move cursor to next version. Returns it, or None if at end."""
        if self._cursor < len(self._versions) - 1:
            self._cursor += 1
            return self.current
        return None

    def go_to(self, index: int) -> Optional[ShaderVersion]:
        """Jump to a specific version index."""
        if 0 <= index < len(self._versions):
            self._cursor = index
            return self.current
        return None

    def to_dict(self) -> dict:
        return {
            "versions": [asdict(v) for v in self._versions],
            "cursor": self._cursor,
        }

    @classmethod
    def from_dict(cls, data: dict) -> "ShaderVersionStore":
        store = cls()
        for vd in data.get("versions", []):
            store._versions.append(ShaderVersion(**vd))
        store._cursor = data.get("cursor", len(store._versions) - 1)
        return store

    def save(self, path: str) -> None:
        """Persist to JSON file."""
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        with open(path, "w") as f:
            json.dump(self.to_dict(), f, indent=2)

    @classmethod
    def load(cls, path: str) -> "ShaderVersionStore":
        """Load from JSON file. Returns empty store if file missing."""
        if not os.path.exists(path):
            return cls()
        try:
            with open(path) as f:
                return cls.from_dict(json.load(f))
        except (json.JSONDecodeError, KeyError, TypeError):
            return cls()
