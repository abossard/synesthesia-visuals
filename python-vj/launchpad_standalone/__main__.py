"""
Launchpad Standalone - Entry point

Run with: python -m launchpad_standalone
"""

import asyncio
from .app import main

if __name__ == "__main__":
    asyncio.run(main())
