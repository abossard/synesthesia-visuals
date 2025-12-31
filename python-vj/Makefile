.PHONY: test test-baseline test-osc test-vdj test-lyrics test-ai test-all test-osc-runtime help

help:
	@echo "Test targets:"
	@echo "  make test          - Run baseline behavior tests (interactive)"
	@echo "  make test-osc      - Run OSC tests only"
	@echo "  make test-vdj      - Run VDJ integration tests"
	@echo "  make test-lyrics   - Run lyrics fetching tests"
	@echo "  make test-ai       - Run AI categorization tests"
	@echo "  make test-osc-runtime - Run OSC Runtime module tests"
	@echo "  make test-all      - Run all tests"

test: test-baseline

test-baseline:
	@echo "Running baseline behavior tests..."
	@echo "These tests are interactive - you'll be prompted to set up services."
	@echo ""
	pytest tests/test_baseline_behavior.py -v -s

test-osc:
	pytest tests/test_baseline_behavior.py::TestOSCCommunication -v -s

test-vdj:
	pytest tests/test_baseline_behavior.py::TestVDJIntegration -v -s

test-lyrics:
	pytest tests/test_baseline_behavior.py::TestLyricsFetching -v -s

test-ai:
	pytest tests/test_baseline_behavior.py::TestAICategorization -v -s

test-osc-runtime:
	pytest tests/modules/test_osc_runtime.py -v -s

test-all:
	pytest tests/ -v -s
