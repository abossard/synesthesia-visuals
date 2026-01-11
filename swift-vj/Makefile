# swift-vj Makefile
# Build targets for shader compilation and app

.PHONY: all build run clean compile-shaders compile-flat-shaders shaders help

# Directories
BUILD_DIR := Build
SHADERS_DIR := Shaders
METALLIB := Sources/SwiftVJApp/Resources/Shaders.metallib

# Tools
SWIFT := swift
XCRUN := xcrun

help:
	@echo "swift-vj Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build                - Build the Swift package"
	@echo "  run                  - Run the app"
	@echo "  shaders              - Compile GLSL shaders using ShaderRepository module (recommended)"
	@echo "  compile-flat-shaders - Legacy: Compile using shell script"
	@echo "  clean                - Clean build artifacts"
	@echo ""
	@echo "Shader compilation:"
	@echo "  Input:  $(SHADERS_DIR)/glsl/*.txt, $(SHADERS_DIR)/masks/*.txt"
	@echo "  Output: $(METALLIB)"

all: build shaders

build:
	$(SWIFT) build

run: build
	$(SWIFT) run SwiftVJApp

# New: Compile shaders using the ShaderRepository module CLI
# This is the recommended way to compile shaders
shaders: build
	@echo "🔧 Compiling shaders with ShaderRepository..."
	$(SWIFT) run compile-shaders \
		--shaders-dir $(SHADERS_DIR) \
		--build-dir $(BUILD_DIR)/Shaders \
		--output $(METALLIB)
	@echo ""
	@echo "✅ Metallib at: $(METALLIB)"
	@ls -lh $(METALLIB)

# Legacy: Compile shaders using shell script
# Kept for backwards compatibility
compile-flat-shaders: $(BUILD_DIR)
	@echo "⚠️  Using legacy shell-based compilation. Consider 'make shaders' instead."
	@echo "Converting GLSL shaders to Metal..."
	@SUCCESS=0; FAIL=0; \
	for f in $(SHADERS_DIR)/glsl/*.txt $(SHADERS_DIR)/masks/*.txt; do \
		[ -f "$$f" ] || continue; \
		b=$$(basename "$$f" .txt); \
		if ./Scripts/convert-flat-glsl.sh "$$f" "$(BUILD_DIR)/$$b.metal" >/dev/null 2>&1; then \
			SUCCESS=$$((SUCCESS+1)); \
		else \
			FAIL=$$((FAIL+1)); \
		fi; \
	done; \
	echo "Converted: $$SUCCESS, Failed: $$FAIL"
	@echo "Including shared vertex function..."
	@cp Sources/SwiftVJApp/Resources/SharedVertex.metal $(BUILD_DIR)/SharedVertex.metal
	@echo "Compiling to Metal bytecode..."
	@for f in $(BUILD_DIR)/*.metal; do \
		[ -f "$$f" ] || continue; \
		$(XCRUN) metal -c "$$f" -o "$(BUILD_DIR)/air/$$(basename "$$f" .metal).air" 2>/dev/null; \
	done
	@echo "Linking metallib..."
	@$(XCRUN) metallib $(BUILD_DIR)/air/*.air -o $(METALLIB)
	@ls -lh $(METALLIB)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/air
	mkdir -p $(BUILD_DIR)/Shaders

clean:
	rm -rf $(BUILD_DIR)
	rm -rf .build

# Development helpers
.PHONY: test lint

test:
	$(SWIFT) test

lint:
	swiftlint lint --quiet
