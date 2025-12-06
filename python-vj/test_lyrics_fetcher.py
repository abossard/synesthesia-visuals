#!/usr/bin/env python3
"""
Test script for LyricsFetcher with web-search fallback.

Run with:
    python test_lyrics_fetcher.py

Requires LM Studio running at http://localhost:1234 for web-search fallback.
"""

import sys
import json
import logging
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('test')

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from adapters import LyricsFetcher

def test_lrclib_fetch():
    """Test fetching lyrics from LRCLIB (should work for popular songs)."""
    print("\n" + "=" * 60)
    print("TEST 1: LRCLIB fetch (popular song)")
    print("=" * 60)
    
    fetcher = LyricsFetcher(enable_web_search=False)  # Disable fallback for this test
    
    # Test with a popular song that should be in LRCLIB
    lyrics = fetcher.fetch("Queen", "Bohemian Rhapsody")
    
    if lyrics:
        print(f"✓ Found lyrics ({len(lyrics)} chars)")
        print(f"First 200 chars:\n{lyrics[:200]}...")
        return True
    else:
        print("✗ No lyrics found (song may not be in LRCLIB)")
        return False

def test_web_search_fallback():
    """Test web-search fallback via LM Studio."""
    print("\n" + "=" * 60)
    print("TEST 2: Web-search fallback (requires LM Studio)")
    print("=" * 60)
    
    fetcher = LyricsFetcher(enable_web_search=True)
    
    # Check if LM Studio is available
    if not fetcher._check_lmstudio():
        print("⚠ LM Studio not available at http://localhost:1234")
        print("  Start LM Studio and load a model to test web-search fallback")
        return None
    
    print(f"✓ LM Studio available: {fetcher._lmstudio_model}")
    
    # Test with a song that might not be in LRCLIB
    # Using a less common song to trigger fallback
    lyrics = fetcher.fetch("Stromae", "Papaoutai")
    
    if lyrics:
        print(f"✓ Found lyrics ({len(lyrics)} chars)")
        print(f"First 200 chars:\n{lyrics[:200]}...")
        return True
    else:
        print("✗ No lyrics found via web search")
        return False

def test_song_info():
    """Test fetching song metadata via web-search."""
    print("\n" + "=" * 60)
    print("TEST 3: Song info via web-search (requires LM Studio)")
    print("=" * 60)
    
    fetcher = LyricsFetcher(enable_web_search=True)
    
    if not fetcher._check_lmstudio():
        print("⚠ LM Studio not available - skipping test")
        return None
    
    info = fetcher.get_song_info("Queen", "Bohemian Rhapsody")
    
    if info:
        print("✓ Found song info:")
        print(json.dumps(info, indent=2))
        return True
    else:
        print("✗ No song info found")
        return False

def test_cache_persistence():
    """Test that results are cached and retrieved."""
    print("\n" + "=" * 60)
    print("TEST 4: Cache persistence")
    print("=" * 60)
    
    # Use a temporary cache directory
    import tempfile
    cache_dir = Path(tempfile.mkdtemp()) / "lyrics_test"
    
    fetcher = LyricsFetcher(cache_dir=cache_dir, enable_web_search=False)
    
    # First fetch (should hit API)
    lyrics1 = fetcher.fetch("Queen", "Bohemian Rhapsody")
    
    # Check cache file exists
    cache_file = cache_dir / "queen_bohemian_rhapsody.json"
    cache_exists = any(cache_dir.glob("*.json"))
    
    if cache_exists:
        print("✓ Cache file created")
        
        # Second fetch (should use cache)
        lyrics2 = fetcher.fetch("Queen", "Bohemian Rhapsody")
        
        if lyrics1 == lyrics2:
            print("✓ Cache retrieval works")
            return True
        else:
            print("✗ Cache retrieval mismatch")
            return False
    else:
        print("✗ No cache file created")
        return False

def main():
    """Run all tests."""
    print("\n" + "=" * 60)
    print("LYRICS FETCHER TEST SUITE")
    print("=" * 60)
    
    results = {
        "LRCLIB fetch": test_lrclib_fetch(),
        "Cache persistence": test_cache_persistence(),
        "Web-search fallback": test_web_search_fallback(),
        "Song info": test_song_info(),
    }
    
    print("\n" + "=" * 60)
    print("RESULTS SUMMARY")
    print("=" * 60)
    
    for test, result in results.items():
        if result is True:
            status = "✓ PASS"
        elif result is False:
            status = "✗ FAIL"
        else:
            status = "⚠ SKIP"
        print(f"{status}: {test}")
    
    # Return exit code
    failures = sum(1 for r in results.values() if r is False)
    return failures

if __name__ == "__main__":
    sys.exit(main())
