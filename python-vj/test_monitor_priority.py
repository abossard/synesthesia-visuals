#!/usr/bin/env python3
"""
Test monitor priority system

Verifies that VirtualDJ monitor is only active when Spotify monitors return None.

Run with: python -m pytest test_monitor_priority.py -v
Or simply: python test_monitor_priority.py
"""

import unittest
from unittest.mock import Mock, MagicMock
from orchestrators import PlaybackCoordinator


class TestMonitorPriority(unittest.TestCase):
    """Tests for monitor priority system."""
    
    def test_spotify_takes_priority_over_virtualdj(self):
        """When Spotify returns playback, VirtualDJ should not be checked."""
        # Create mock monitors
        spotify_monitor = Mock()
        spotify_monitor.monitor_key = "spotify_local"
        spotify_monitor.get_playback.return_value = {
            'artist': 'Daft Punk',
            'title': 'Around the World',
            'album': 'Homework',
            'duration_ms': 240000,
            'progress_ms': 60000,
            'is_playing': True
        }
        
        vdj_monitor = Mock()
        vdj_monitor.monitor_key = "virtualdj"
        vdj_monitor.get_playback.return_value = {
            'artist': 'Different Artist',
            'title': 'Different Track',
            'album': '',
            'duration_ms': 0,
            'progress_ms': 0,
            'is_playing': True
        }
        
        # Create coordinator with monitors in priority order
        coordinator = PlaybackCoordinator(monitors=[spotify_monitor, vdj_monitor])
        
        # Poll should use Spotify
        sample = coordinator.poll()
        
        # Verify Spotify was called
        spotify_monitor.get_playback.assert_called_once()
        
        # Verify VirtualDJ was NOT called (due to early break)
        vdj_monitor.get_playback.assert_not_called()
        
        # Verify correct source
        self.assertEqual(sample.source, "spotify_local")
        self.assertEqual(sample.state.track.artist, "Daft Punk")
    
    def test_virtualdj_activates_when_spotify_idle(self):
        """When Spotify returns None, VirtualDJ should be checked."""
        # Create mock monitors
        spotify_monitor = Mock()
        spotify_monitor.monitor_key = "spotify_local"
        spotify_monitor.get_playback.return_value = None  # Spotify idle
        
        vdj_monitor = Mock()
        vdj_monitor.monitor_key = "virtualdj"
        vdj_monitor.get_playback.return_value = {
            'artist': 'VDJ Artist',
            'title': 'VDJ Track',
            'album': '',
            'duration_ms': 0,
            'progress_ms': 5000,
            'is_playing': True
        }
        
        # Create coordinator
        coordinator = PlaybackCoordinator(monitors=[spotify_monitor, vdj_monitor])
        
        # Poll should use VirtualDJ
        sample = coordinator.poll()
        
        # Verify both monitors were called
        spotify_monitor.get_playback.assert_called_once()
        vdj_monitor.get_playback.assert_called_once()
        
        # Verify correct source
        self.assertEqual(sample.source, "virtualdj")
        self.assertEqual(sample.state.track.artist, "VDJ Artist")
    
    def test_multiple_spotify_monitors_priority(self):
        """AppleScript Spotify should have priority over Web API."""
        # Create mock monitors
        applescript_monitor = Mock()
        applescript_monitor.monitor_key = "spotify_local"
        applescript_monitor.get_playback.return_value = {
            'artist': 'AppleScript Track',
            'title': 'Desktop App',
            'album': 'Local',
            'duration_ms': 180000,
            'progress_ms': 30000,
            'is_playing': True
        }
        
        webapi_monitor = Mock()
        webapi_monitor.monitor_key = "spotify_api"
        webapi_monitor.get_playback.return_value = {
            'artist': 'Web API Track',
            'title': 'Should Not Be Used',
            'album': 'API',
            'duration_ms': 200000,
            'progress_ms': 40000,
            'is_playing': True
        }
        
        vdj_monitor = Mock()
        vdj_monitor.monitor_key = "virtualdj"
        vdj_monitor.get_playback.return_value = {
            'artist': 'VDJ Artist',
            'title': 'Should Not Be Used',
            'album': '',
            'duration_ms': 0,
            'progress_ms': 0,
            'is_playing': True
        }
        
        # Create coordinator with all three monitors
        coordinator = PlaybackCoordinator(monitors=[
            applescript_monitor,
            webapi_monitor,
            vdj_monitor
        ])
        
        # Poll should use AppleScript
        sample = coordinator.poll()
        
        # Verify only AppleScript was called
        applescript_monitor.get_playback.assert_called_once()
        webapi_monitor.get_playback.assert_not_called()
        vdj_monitor.get_playback.assert_not_called()
        
        # Verify correct source
        self.assertEqual(sample.source, "spotify_local")
        self.assertEqual(sample.state.track.artist, "AppleScript Track")
    
    def test_webapi_fallback_when_applescript_fails(self):
        """Web API should activate when AppleScript returns None."""
        # Create mock monitors
        applescript_monitor = Mock()
        applescript_monitor.monitor_key = "spotify_local"
        applescript_monitor.get_playback.return_value = None  # AppleScript failed
        
        webapi_monitor = Mock()
        webapi_monitor.monitor_key = "spotify_api"
        webapi_monitor.get_playback.return_value = {
            'artist': 'Web API Track',
            'title': 'Fallback Active',
            'album': 'API',
            'duration_ms': 200000,
            'progress_ms': 40000,
            'is_playing': True
        }
        
        vdj_monitor = Mock()
        vdj_monitor.monitor_key = "virtualdj"
        vdj_monitor.get_playback.return_value = {
            'artist': 'VDJ Artist',
            'title': 'Should Not Be Used',
            'album': '',
            'duration_ms': 0,
            'progress_ms': 0,
            'is_playing': True
        }
        
        # Create coordinator
        coordinator = PlaybackCoordinator(monitors=[
            applescript_monitor,
            webapi_monitor,
            vdj_monitor
        ])
        
        # Poll should use Web API
        sample = coordinator.poll()
        
        # Verify AppleScript and Web API were called, but not VDJ
        applescript_monitor.get_playback.assert_called_once()
        webapi_monitor.get_playback.assert_called_once()
        vdj_monitor.get_playback.assert_not_called()
        
        # Verify correct source
        self.assertEqual(sample.source, "spotify_api")
        self.assertEqual(sample.state.track.artist, "Web API Track")
    
    def test_all_monitors_idle(self):
        """When all monitors return None, source should be 'idle'."""
        # Create mock monitors
        spotify_monitor = Mock()
        spotify_monitor.monitor_key = "spotify_local"
        spotify_monitor.get_playback.return_value = None
        
        vdj_monitor = Mock()
        vdj_monitor.monitor_key = "virtualdj"
        vdj_monitor.get_playback.return_value = None
        
        # Create coordinator
        coordinator = PlaybackCoordinator(monitors=[spotify_monitor, vdj_monitor])
        
        # Poll should return idle
        sample = coordinator.poll()
        
        # Verify both monitors were called
        spotify_monitor.get_playback.assert_called_once()
        vdj_monitor.get_playback.assert_called_once()
        
        # Verify source is idle
        self.assertEqual(sample.source, "idle")
        self.assertIsNone(sample.state.track)


if __name__ == '__main__':
    # Run tests
    unittest.main(verbosity=2)
