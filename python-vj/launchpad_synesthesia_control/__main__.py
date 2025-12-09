#!/usr/bin/env python3
"""
Launchpad Synesthesia Control - Main Entry Point

Standalone launcher for the Launchpad configuration tool.
"""

if __name__ == "__main__":
    import sys
    from pathlib import Path
    
    # Add parent directory to path so module can be imported when run directly
    sys.path.insert(0, str(Path(__file__).parent.parent))
    
    from launchpad_synesthesia_control.app.ui.tui import run_app
    run_app()
