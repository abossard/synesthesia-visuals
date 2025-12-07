# Synesthesia Visuals - Makefile
# Shader analysis management commands

SHADERS_DIR := processing-vj/src/VJUniverse/data/shaders
SCREENSHOTS_DIR := processing-vj/src/VJUniverse/data/screenshots
CHROMADB_DIR := python-vj/.chromadb
PYTHON := python3

.PHONY: help clean-errors clean-analysis clean-all stats find-black list-black

help:
	@echo "Shader Analysis Management"
	@echo ""
	@echo "  make stats           - Show shader analysis statistics"
	@echo "  make clean-errors    - Delete all .error.json files (allows re-analysis)"
	@echo "  make clean-analysis  - Delete all .analysis.json files (full re-analysis)"
	@echo "  make clean-all       - Delete both error and analysis files"
	@echo ""
	@echo "Screenshot Analysis (requires ImageMagick)"
	@echo ""
	@echo "  make find-black      - Find black/broken shaders from screenshots"
	@echo "  make list-black      - List black shaders (quick, from cache)"
	@echo "  make brightness-all  - Show all shaders sorted by brightness"
	@echo ""

# Show statistics about shader analysis
stats:
	@echo "=== Shader Analysis Statistics ==="
	@echo ""
	@echo "ISF Shaders (.fs):"
	@echo "  Total:    $$(find $(SHADERS_DIR)/isf -name '*.fs' 2>/dev/null | wc -l | tr -d ' ')"
	@echo "  Analyzed: $$(find $(SHADERS_DIR)/isf -name '*.analysis.json' 2>/dev/null | wc -l | tr -d ' ')"
	@echo "  Errors:   $$(find $(SHADERS_DIR)/isf -name '*.error.json' 2>/dev/null | wc -l | tr -d ' ')"
	@echo ""
	@echo "GLSL Shaders (.txt):"
	@echo "  Total:    $$(find $(SHADERS_DIR)/glsl -name '*.txt' 2>/dev/null | wc -l | tr -d ' ')"
	@echo "  Analyzed: $$(find $(SHADERS_DIR)/glsl -name '*.analysis.json' 2>/dev/null | wc -l | tr -d ' ')"
	@echo "  Errors:   $$(find $(SHADERS_DIR)/glsl -name '*.error.json' 2>/dev/null | wc -l | tr -d ' ')"
	@echo ""

# Delete all error files (allows failed shaders to be re-analyzed)
clean-errors:
	@echo "Deleting .error.json files..."
	@find $(SHADERS_DIR) -name '*.error.json' -delete
	@echo "Done. Error files removed."

# Delete all analysis files (forces complete re-analysis)
clean-analysis:
	@echo "Deleting .analysis.json files..."
	@find $(SHADERS_DIR) -name '*.analysis.json' -delete
	@echo "Done. Analysis files removed."

# Delete both error and analysis files
clean-all: clean-errors clean-analysis
	@echo "Deleting ChromaDB cache..."
	@rm -rf $(CHROMADB_DIR)
	@echo "All analysis data cleared."

# List shaders with errors (useful for debugging)
list-errors:
	@echo "Shaders with errors:"
	@find $(SHADERS_DIR) -name '*.error.json' -exec basename {} .error.json \;

# ============================================================================
# Screenshot Analysis (requires ImageMagick)
# ============================================================================

# Find black/broken shaders by analyzing screenshot brightness
find-black:
	@echo "Analyzing screenshots for black/broken shaders..."
	@$(PYTHON) python-vj/scripts/find_black_shaders.py \
		--screenshots $(SCREENSHOTS_DIR) \
		--isf $(SHADERS_DIR)/isf \
		--glsl $(SHADERS_DIR)/glsl \
		--output $(SCREENSHOTS_DIR)/black-broken-shaders.txt
	@echo ""
	@cat $(SCREENSHOTS_DIR)/black-broken-shaders.txt

# Quick list of known black shaders (from cached file)
list-black:
	@if [ -f $(SCREENSHOTS_DIR)/black-broken-shaders.txt ]; then \
		cat $(SCREENSHOTS_DIR)/black-broken-shaders.txt; \
	else \
		echo "No cached black shaders list. Run 'make find-black' first."; \
	fi

# Show all shaders sorted by brightness
brightness-all:
	@$(PYTHON) python-vj/scripts/find_black_shaders.py \
		--screenshots $(SCREENSHOTS_DIR) \
		--isf $(SHADERS_DIR)/isf \
		--glsl $(SHADERS_DIR)/glsl \
		--all
