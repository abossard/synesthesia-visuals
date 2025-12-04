#!/usr/bin/env python3
"""
Quick test to ensure VJ Console starts without errors.
"""

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

print("=" * 60)
print("VJ Console - Startup Test")
print("=" * 60)

try:
    print("1. Testing imports...")
    from vj_console import VJConsoleApp
    print("   ✓ Imports successful")

    print("\n2. Creating app instance...")
    app = VJConsoleApp()
    print("   ✓ App instance created")

    print("\n3. Testing configuration...")
    print(f"   - Auto-start workers: {app._auto_start_workers}")
    print(f"   - Auto-healing: {app._auto_heal_workers}")
    print(f"   - Audio available: {'Yes' if hasattr(app, 'audio_analyzer') else 'No'}")

    print("\n✅ All tests passed!")
    print("\nTo start the console, run:")
    print("   ./start_vj.sh")
    print("   or")
    print("   python vj_console.py")

except Exception as e:
    print(f"\n❌ Test failed: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("=" * 60)
