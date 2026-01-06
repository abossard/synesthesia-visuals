"""
E2E tests for AI Analysis module.

Run with: pytest tests/modules/test_ai_analysis.py -v -s
"""


class TestAIAnalysisLifecycle:
    """Test AI Analysis module lifecycle."""

    def test_module_starts_and_stops_cleanly(self):
        """AI Analysis module starts and stops without errors."""
        from modules.ai_analysis import AIAnalysisModule, AIAnalysisConfig

        config = AIAnalysisConfig()
        ai = AIAnalysisModule(config)

        assert not ai.is_started

        success = ai.start()
        assert success, "Module should start successfully"
        assert ai.is_started

        status = ai.get_status()
        assert status["started"] is True

        ai.stop()
        assert not ai.is_started

        print("\nModule started and stopped cleanly")

    def test_module_can_restart(self):
        """AI Analysis module can be stopped and restarted."""
        from modules.ai_analysis import AIAnalysisModule

        ai = AIAnalysisModule()

        ai.start()
        assert ai.is_started

        ai.stop()
        assert not ai.is_started

        success = ai.start()
        assert success, "Should restart successfully"
        assert ai.is_started

        ai.stop()

        print("\nModule restart successful")


class TestAIAnalysisCategorization:
    """Test AI-powered song categorization."""

    def test_categorizes_song_with_lyrics(self, requires_lm_studio, requires_internet):
        """Categorizes song using LLM when available."""
        from modules.ai_analysis import AIAnalysisModule

        ai = AIAnalysisModule()
        ai.start()

        assert ai.is_available, "LM Studio should be available"

        # Fetch lyrics first
        from adapters import LyricsFetcher
        fetcher = LyricsFetcher()
        lyrics = fetcher.fetch("Queen", "Bohemian Rhapsody")
        assert lyrics, "Should fetch lyrics"

        result = ai.categorize(lyrics, "Queen", "Bohemian Rhapsody")

        assert result.primary_mood, "Should have primary mood"
        assert result.scores, "Should have scores dict"
        assert len(result.scores) > 0, "Should have at least one score"

        ai.stop()

        print(f"\nPrimary mood: {result.primary_mood}")
        print(f"Top categories: {result.get_top(3)}")

    def test_returns_valid_energy_valence_scores(self, requires_lm_studio, requires_internet):
        """Returns valid energy and valence scores in expected ranges."""
        from modules.ai_analysis import AIAnalysisModule

        ai = AIAnalysisModule()
        ai.start()

        from adapters import LyricsFetcher
        fetcher = LyricsFetcher()
        lyrics = fetcher.fetch("Queen", "Bohemian Rhapsody")

        result = ai.categorize(lyrics, "Queen", "Bohemian Rhapsody")

        # Energy should be 0.0 - 1.0
        assert 0.0 <= result.energy <= 1.0, f"Energy {result.energy} out of range"

        # Valence should be -1.0 to 1.0
        assert -1.0 <= result.valence <= 1.0, f"Valence {result.valence} out of range"

        # Category scores should all be 0.0 - 1.0
        for name, score in result.scores.items():
            assert 0.0 <= score <= 1.0, f"Score for {name} out of range: {score}"

        ai.stop()

        print(f"\nEnergy: {result.energy:.2f}")
        print(f"Valence: {result.valence:+.2f}")


class TestAIAnalysisGracefulDegradation:
    """Test graceful degradation when LLM unavailable."""

    def test_works_without_llm(self):
        """Falls back to basic analysis when LLM unavailable."""
        from modules.ai_analysis import AIAnalysisModule, AIAnalysisConfig

        # Use a port that's definitely not LM Studio
        config = AIAnalysisConfig(lm_studio_url="http://localhost:59999")
        ai = AIAnalysisModule(config)
        ai.start()

        # Should still work with basic keyword analysis
        lyrics = """
        I'm so happy today, full of joy and love
        The sun is shining bright, dancing in the light
        Everything is wonderful and beautiful
        """

        result = ai.categorize(lyrics, "Test Artist", "Happy Song")

        # Should return valid result even without LLM
        assert result is not None
        assert result.scores is not None
        assert 0.0 <= result.energy <= 1.0
        assert -1.0 <= result.valence <= 1.0

        ai.stop()

        print(f"\nFallback result:")
        print(f"  Primary mood: {result.primary_mood}")
        print(f"  Backend: {result.backend}")

    def test_doesnt_crash_without_llm(self):
        """Module doesn't crash when LLM unavailable."""
        from modules.ai_analysis import AIAnalysisModule, AIAnalysisConfig

        config = AIAnalysisConfig(lm_studio_url="http://localhost:59999")
        ai = AIAnalysisModule(config)

        # All operations should succeed
        success = ai.start()
        assert success

        status = ai.get_status()
        assert status["started"] is True

        # is_available should be False but not error
        available = ai.is_available
        assert isinstance(available, bool)

        ai.stop()
        assert not ai.is_started

        print("\nGraceful degradation working")


class TestAIAnalysisStandalone:
    """Test standalone CLI functionality."""

    def test_cli_module_importable(self):
        """CLI module can be imported without errors."""
        from modules.ai_analysis import main

        assert callable(main), "main should be callable"

        print("\nCLI module imports successfully")
