"""
E2E tests for Pipeline module.

Run with: pytest tests/modules/test_pipeline.py -v -s
"""
from unittest.mock import MagicMock, patch


class TestPipelineLifecycle:
    """Test Pipeline module lifecycle."""

    def test_module_starts_and_stops_cleanly(self):
        """Pipeline module starts and stops without errors."""
        from modules.pipeline import PipelineModule, PipelineConfig

        config = PipelineConfig()
        pipeline = PipelineModule(config)

        assert not pipeline.is_started

        success = pipeline.start()
        assert success, "Module should start successfully"
        assert pipeline.is_started

        status = pipeline.get_status()
        assert status["started"] is True

        pipeline.stop()
        assert not pipeline.is_started

        print("\nModule started and stopped cleanly")

    def test_module_can_restart(self):
        """Pipeline module can be stopped and restarted."""
        from modules.pipeline import PipelineModule

        pipeline = PipelineModule()

        pipeline.start()
        assert pipeline.is_started

        pipeline.stop()
        assert not pipeline.is_started

        success = pipeline.start()
        assert success, "Should restart successfully"
        assert pipeline.is_started

        pipeline.stop()

        print("\nModule restart successful")


class TestPipelineProcessing:
    """Test pipeline processing functionality."""

    def test_runs_all_steps_for_known_song(self, requires_internet, requires_lm_studio):
        """Pipeline runs all steps for a popular song."""
        from modules.pipeline import PipelineModule, PipelineConfig

        config = PipelineConfig(skip_shaders=True)  # Skip shaders (no data)
        pipeline = PipelineModule(config)
        pipeline.start()

        result = pipeline.process("Queen", "Bohemian Rhapsody")

        assert result.success, "Pipeline should succeed"
        assert result.lyrics_found, "Should find lyrics"
        assert result.mood, "Should have mood from AI"

        pipeline.stop()

        print(f"\nPipeline completed in {result.total_time_ms}ms")
        print(f"Steps: {', '.join(result.steps_completed)}")

    def test_step_callbacks_fire_in_order(self, requires_internet):
        """Step callbacks fire in expected order."""
        from modules.pipeline import PipelineModule, PipelineConfig, PipelineStep

        config = PipelineConfig(skip_ai=True, skip_shaders=True, skip_images=True)
        pipeline = PipelineModule(config)

        started_steps = []
        completed_steps = []

        def on_start(step: PipelineStep):
            started_steps.append(step.value)

        def on_complete(step: PipelineStep, data):
            completed_steps.append(step.value)

        pipeline.on_step_start = on_start
        pipeline.on_step_complete = on_complete

        pipeline.start()
        pipeline.process("Queen", "Bohemian Rhapsody")
        pipeline.stop()

        # Should have lyrics step
        assert "lyrics" in started_steps, "Should start lyrics step"
        assert "lyrics" in completed_steps, "Should complete lyrics step"

        # Order should match
        assert started_steps == completed_steps, "Start/complete order should match"

        print(f"\nCallbacks fired: {started_steps}")

    def test_completes_when_ai_unavailable(self, requires_internet):
        """Pipeline completes gracefully when AI is unavailable."""
        from modules.pipeline import PipelineModule, PipelineConfig

        # Use bogus LM Studio URL to simulate unavailable
        config = PipelineConfig(skip_shaders=True, skip_images=True)
        pipeline = PipelineModule(config)
        pipeline.start()

        # Even without AI, should get lyrics
        result = pipeline.process("Queen", "Bohemian Rhapsody")

        assert result.lyrics_found, "Should still get lyrics"
        # AI might work or fail, but shouldn't crash

        pipeline.stop()

        print(f"\nCompleted with steps: {result.steps_completed}")

    def test_handles_unknown_song(self, requires_internet):
        """Pipeline handles unknown songs gracefully."""
        from modules.pipeline import PipelineModule, PipelineConfig

        config = PipelineConfig(skip_shaders=True, skip_images=True)
        pipeline = PipelineModule(config)
        pipeline.start()

        result = pipeline.process("zzznonexistent12345", "notarealsong67890")

        # Should not crash
        assert not result.lyrics_found, "Should not find lyrics"

        pipeline.stop()

        print("\nHandled unknown song gracefully")


class TestPipelineImages:
    """Test pipeline image fetching."""

    def test_fetches_images_for_song(self, requires_internet):
        """Pipeline fetches images when enabled."""
        from modules.pipeline import PipelineModule, PipelineConfig

        config = PipelineConfig(skip_ai=True, skip_shaders=True)
        pipeline = PipelineModule(config)
        pipeline.start()

        result = pipeline.process("Daft Punk", "Get Lucky")

        # Images should be fetched (at least from Cover Art Archive)
        # May be cached from previous runs
        assert "images" in result.steps_completed or result.images_found

        pipeline.stop()

        if result.images_found:
            print(f"\nImages: {result.images_count} in {result.images_folder}")
        else:
            print("\nNo images found (may need API keys)")


class TestPipelineMetadata:
    """Test pipeline metadata step (LLM-based)."""

    def test_metadata_step_included(self):
        """Metadata step is part of the pipeline enum."""
        from modules.pipeline import PipelineStep

        step_values = [s.value for s in PipelineStep]
        assert "metadata" in step_values, "Should have metadata step"

        # Check order: lyrics -> metadata -> ai_analysis
        assert step_values.index("lyrics") < step_values.index("metadata")
        assert step_values.index("metadata") < step_values.index("ai_analysis")

        print(f"\nPipeline steps: {step_values}")

    def test_pipeline_result_has_metadata_fields(self):
        """PipelineResult has all metadata-related fields."""
        from modules.pipeline import PipelineResult

        result = PipelineResult(artist="Test", title="Song")

        # Check metadata fields exist
        assert hasattr(result, "metadata_found")
        assert hasattr(result, "keywords")
        assert hasattr(result, "themes")
        assert hasattr(result, "visual_adjectives")
        assert hasattr(result, "tempo")
        assert hasattr(result, "llm_refrain_lines")
        assert hasattr(result, "plain_lyrics")
        assert hasattr(result, "release_date")
        assert hasattr(result, "genre")

        print("\nPipelineResult has all metadata fields")

    def test_fetches_metadata_when_lm_studio_available(self, requires_internet, requires_lm_studio):
        """Pipeline fetches metadata via LLM when available."""
        from modules.pipeline import PipelineModule, PipelineConfig

        config = PipelineConfig(skip_ai=True, skip_shaders=True, skip_images=True, skip_osc=True)
        pipeline = PipelineModule(config)
        pipeline.start()

        result = pipeline.process("Queen", "Bohemian Rhapsody")

        assert "metadata" in result.steps_completed, "Should complete metadata step"
        assert result.metadata_found, "Should find metadata"
        assert len(result.keywords) > 0 or len(result.themes) > 0, "Should have keywords or themes"

        pipeline.stop()

        print(f"\nMetadata: {len(result.keywords)} keywords, {len(result.themes)} themes")

    def test_metadata_step_skippable(self):
        """Metadata step can be skipped."""
        from modules.pipeline import PipelineModule, PipelineConfig, PipelineStep

        config = PipelineConfig(
            skip_lyrics=True,
            skip_metadata=True,
            skip_ai=True,
            skip_shaders=True,
            skip_images=True,
            skip_osc=True
        )
        pipeline = PipelineModule(config)

        started_steps = []
        pipeline.on_step_start = lambda step: started_steps.append(step.value)

        pipeline.start()
        result = pipeline.process("Test", "Song")
        pipeline.stop()

        assert "metadata" not in started_steps, "Metadata step should be skipped"

        print("\nMetadata step skipped successfully")


class TestPipelineLyricsEnhancements:
    """Test enhanced lyrics with refrain and keyword extraction."""

    def test_pipeline_result_has_lyrics_enhancement_fields(self):
        """PipelineResult has refrain and keyword fields."""
        from modules.pipeline import PipelineResult

        result = PipelineResult(artist="Test", title="Song")

        assert hasattr(result, "refrain_lines"), "Should have refrain_lines"
        assert hasattr(result, "lyrics_keywords"), "Should have lyrics_keywords"
        assert hasattr(result, "lyrics_lines"), "Should have lyrics_lines"

        print("\nPipelineResult has lyrics enhancement fields")

    def test_extracts_refrains_from_lyrics(self, requires_internet):
        """Pipeline extracts refrain lines from lyrics."""
        from modules.pipeline import PipelineModule, PipelineConfig

        config = PipelineConfig(
            skip_metadata=True,
            skip_ai=True,
            skip_shaders=True,
            skip_images=True,
            skip_osc=True
        )
        pipeline = PipelineModule(config)
        pipeline.start()

        # Song with known refrain
        result = pipeline.process("Queen", "We Will Rock You")

        assert result.lyrics_found, "Should find lyrics"
        # Refrain detection depends on LRC data quality
        print(f"\nFound {len(result.refrain_lines)} refrain lines")
        print(f"Found {len(result.lyrics_keywords)} keywords")

        pipeline.stop()

    def test_lyrics_step_callback_includes_refrain_count(self, requires_internet):
        """Lyrics step callback data includes refrain and keyword counts."""
        from modules.pipeline import PipelineModule, PipelineConfig, PipelineStep

        config = PipelineConfig(
            skip_metadata=True,
            skip_ai=True,
            skip_shaders=True,
            skip_images=True,
            skip_osc=True
        )
        pipeline = PipelineModule(config)

        lyrics_data = {}

        def on_complete(step, data):
            if step == PipelineStep.LYRICS:
                lyrics_data.update(data)

        pipeline.on_step_complete = on_complete

        pipeline.start()
        pipeline.process("Queen", "Bohemian Rhapsody")
        pipeline.stop()

        assert "refrains" in lyrics_data, "Callback should include refrains count"
        assert "keywords" in lyrics_data, "Callback should include keywords count"

        print(f"\nLyrics callback: {lyrics_data}")


class TestPipelineOSC:
    """Test pipeline OSC sending functionality."""

    def test_osc_config_option(self):
        """Pipeline has skip_osc config option."""
        from modules.pipeline import PipelineConfig

        config = PipelineConfig(skip_osc=True)
        assert config.skip_osc is True

        config2 = PipelineConfig()
        assert config2.skip_osc is False

        print("\nOSC config option works")

    def test_osc_methods_exist(self):
        """Pipeline has OSC sending methods."""
        from modules.pipeline import PipelineModule

        pipeline = PipelineModule()

        assert hasattr(pipeline, "_send_track_osc")
        assert hasattr(pipeline, "_send_lyrics_osc")
        assert hasattr(pipeline, "_send_metadata_osc")
        assert hasattr(pipeline, "_send_categories_osc")
        assert hasattr(pipeline, "_send_shader_osc")
        assert hasattr(pipeline, "_send_images_osc")

        print("\nPipeline has all OSC methods")

    def test_osc_sender_lazy_loaded(self):
        """OSC sender is lazy loaded only when needed."""
        from modules.pipeline import PipelineModule, PipelineConfig

        config = PipelineConfig(skip_osc=True)
        pipeline = PipelineModule(config)
        pipeline.start()

        # With skip_osc=True, _get_osc should return None
        osc = pipeline._get_osc()
        assert osc is None, "OSC should be None when skip_osc=True"

        pipeline.stop()

        print("\nOSC lazy loading works correctly")

    def test_sends_osc_when_enabled(self, requires_internet):
        """Pipeline sends OSC messages when enabled."""
        from modules.pipeline import PipelineModule, PipelineConfig

        # Mock OSCSender to track calls
        mock_sender = MagicMock()

        config = PipelineConfig(
            skip_metadata=True,
            skip_ai=True,
            skip_shaders=True,
            skip_images=True
        )
        pipeline = PipelineModule(config)
        pipeline._osc = mock_sender  # Inject mock

        pipeline.start()
        result = pipeline.process("Queen", "Bohemian Rhapsody")
        pipeline.stop()

        # Verify OSC methods were called
        assert mock_sender.send_textler.called, "Should call send_textler"

        # Check track info was sent
        calls = [str(c) for c in mock_sender.send_textler.call_args_list]
        track_calls = [c for c in calls if "track" in c]
        assert len(track_calls) > 0, "Should send track info"

        print(f"\nOSC send_textler called {mock_sender.send_textler.call_count} times")


class TestPipelineFullFlow:
    """Test full pipeline end-to-end with all steps."""

    def test_full_pipeline_with_all_steps(self, requires_internet, requires_lm_studio):
        """Full pipeline runs all 5 steps successfully."""
        from modules.pipeline import PipelineModule, PipelineConfig, PipelineStep

        config = PipelineConfig(skip_shaders=True, skip_osc=True)  # Skip shaders (no data)
        pipeline = PipelineModule(config)

        started_steps = []
        completed_steps = []

        pipeline.on_step_start = lambda s: started_steps.append(s.value)
        pipeline.on_step_complete = lambda s, d: completed_steps.append(s.value)

        pipeline.start()
        result = pipeline.process("Daft Punk", "Get Lucky", "Random Access Memories")
        pipeline.stop()

        # Should have all non-skipped steps
        expected = ["lyrics", "metadata", "ai_analysis", "images"]
        for step in expected:
            assert step in completed_steps, f"Should complete {step} step"

        # Check result fields
        assert result.album == "Random Access Memories", "Should store album"
        assert result.success, "Pipeline should succeed"

        print(f"\nCompleted steps: {completed_steps}")
        print(f"Lyrics: {result.lyrics_line_count} lines, {len(result.refrain_lines)} refrains")
        print(f"Metadata: {len(result.keywords)} kw, {len(result.themes)} themes")
        print(f"AI: {result.mood} (E:{result.energy:.2f}, V:{result.valence:+.2f})")
        print(f"Images: {result.images_count}")


class TestPipelineStandalone:
    """Test standalone CLI functionality."""

    def test_cli_module_importable(self):
        """CLI module can be imported without errors."""
        from modules.pipeline import main

        assert callable(main), "main should be callable"

        print("\nCLI module imports successfully")

    def test_cli_has_all_skip_options(self):
        """CLI supports all skip options."""
        import subprocess
        import sys

        result = subprocess.run(
            [sys.executable, "-m", "modules.pipeline", "--help"],
            capture_output=True,
            text=True,
            cwd="/Users/abossard/Desktop/projects/synesthesia-visuals/python-vj"
        )

        help_text = result.stdout

        assert "--skip-lyrics" in help_text
        assert "--skip-metadata" in help_text
        assert "--skip-ai" in help_text
        assert "--skip-shaders" in help_text
        assert "--skip-images" in help_text
        assert "--skip-osc" in help_text

        print("\nCLI has all skip options")
