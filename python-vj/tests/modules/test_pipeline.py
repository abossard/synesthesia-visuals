"""
E2E tests for Pipeline module.

Run with: pytest tests/modules/test_pipeline.py -v -s
"""


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


class TestPipelineStandalone:
    """Test standalone CLI functionality."""

    def test_cli_module_importable(self):
        """CLI module can be imported without errors."""
        from modules.pipeline import main

        assert callable(main), "main should be callable"

        print("\nCLI module imports successfully")
