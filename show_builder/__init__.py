"""Phase-Based DJ Show Builder — modular architecture.

Separation following Grokking Simplicity:
  DATA        — fixtures.py, palette.py, scenes.py (data lists), layout.py
  CALCULATIONS — scenes.py (compile_*), layout.py (launchpad_channel)
  ACTIONS     — mcp_client.py, builder.py, __main__.py

Module depth (Philosophy of Software Design):
  scenes.py   — deep: all show content + compile logic behind compile_all()
  builder.py  — deep: full orchestration behind build_show()
  fixtures.py — narrow stable data, changes only when physical rig changes

Customization:
  Edit scenes.py data lists to change colors, gobos, timings, EFX.
  Everything else is stable infrastructure.

Usage:
    python -m show_builder [--skip-patch] [--hero-id 0] [--haze-id 2] [--uv-id 1]
"""
