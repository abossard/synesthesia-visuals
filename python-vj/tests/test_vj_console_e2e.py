#!/usr/bin/env python3
"""
E2E test for VJ Console using Textual's pilot.

Tests:
1. App starts and engine is VJController
2. Track detection from VDJ
3. Pipeline steps are populated
4. Lyrics are fetched (if available)

Run with: python tests/test_vj_console_e2e.py
Or: pytest tests/test_vj_console_e2e.py -v
"""

import asyncio
import sys
sys.path.insert(0, '.')

from vj_console import VJConsoleApp


async def test_full_pipeline():
    app = VJConsoleApp()
    async with app.run_test(size=(120, 40)) as pilot:
        await pilot.pause()
        
        engine = app.textler_engine
        print('=== VJController E2E Test ===\n')
        
        # 1. Engine setup
        print('1. Engine Setup')
        print(f'   Source: {engine.current_source}')
        print(f'   Running: {engine.is_running}')
        assert engine.is_running, "Engine should be running"
        
        # 2. Wait for track detection (poll a few times)
        print('\n2. Track Detection')
        track_found = False
        for i in range(20):  # 20 x 0.3s = 6 seconds max
            engine.tick()
            await asyncio.sleep(0.3)
            pb = engine.playback
            if pb.has_track:
                track_found = True
                print(f'   ✓ Track: {pb.track.artist} - {pb.track.title}')
                print(f'   Position: {pb.position_sec:.1f}s')
                print(f'   Playing: {pb.is_playing}')
                break
        
        if not track_found:
            print('   ⚠ No track detected (is VDJ playing?)')
            print('   Skipping lyrics/pipeline checks')
            return
        
        # 3. Check pipeline steps
        print('\n3. Pipeline Steps')
        steps = engine.pipeline.get_display_lines()
        assert len(steps) > 0, "Pipeline should have steps after track detection"
        
        for label, status, color, msg in steps:
            symbol = '✓' if status == 'COMPLETE' else ('○' if status == 'SKIP' else '?')
            print(f'   {symbol} {label}: {status} - {msg}')
        
        # Check detect_playback completed
        step_names = [s[0] for s in steps]
        assert 'Detect Playback' in step_names, "Should have Detect Playback step"
        
        # 4. Check lyrics
        print('\n4. Lyrics')
        lines = engine.current_lines
        if lines:
            print(f'   ✓ {len(lines)} lyric lines loaded')
            refrain_count = len([ln for ln in lines if ln.is_refrain])
            print(f'   Refrains: {refrain_count}')
            keywords = engine.keywords
            print(f'   Keywords: {len(keywords)} unique')
            if keywords:
                print(f'   Sample: {", ".join(keywords[:5])}...')
            
            # Verify lyrics structure
            assert all(hasattr(ln, 'time_sec') for ln in lines), "Lines should have time_sec"
            assert all(hasattr(ln, 'text') for ln in lines), "Lines should have text"
        else:
            print('   ○ No lyrics found (song may not have synced lyrics)')
        
        # 5. Check timing offset works
        print('\n5. Timing Offset')
        initial_offset = engine.timing_offset_ms
        engine.adjust_timing(100)
        assert engine.timing_offset_ms == initial_offset + 100, "Timing offset should adjust"
        print(f'   ✓ Offset adjusted: {initial_offset} → {engine.timing_offset_ms}ms')
        
        # 6. Summary
        print('\n=== Summary ===')
        checks = [
            ('Engine running', engine.is_running),
            ('Track detected', track_found),
            ('Pipeline has steps', len(steps) > 0),
        ]
        all_pass = all(v for _, v in checks)
        for label, passed in checks:
            print(f'{"✓" if passed else "✗"} {label}')
        
        print(f'\n{"✓ All core checks passed" if all_pass else "✗ Some checks failed"}')
        assert all_pass, "Core checks should pass"


if __name__ == '__main__':
    asyncio.run(test_full_pipeline())
