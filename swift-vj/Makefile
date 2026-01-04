# swift-vj Makefile
# Build targets for shader compilation and app

.PHONY: all build run clean compile-shaders compile-flat-shaders help

# Directories
BUILD_DIR := Build
SHADERS_DIR := Shaders
METALLIB := $(BUILD_DIR)/Shaders.metallib

# Tools
SWIFT := swift
XCRUN := xcrun
SHADER_COMPILE := $(shell $(SWIFT) build --show-bin-path)/shader-compile

help:
	@echo "swift-vj Build System"
	@echo ""
	@echo "Targets:"
	@echo "  build                - Build the Swift package"
	@echo "  run                  - Run the app"
	@echo "  compile-shaders      - Compile Shadertoy-format shaders to Metal library"
	@echo "  compile-flat-shaders - Compile simple GLSL files (*.txt) to Metal library"
	@echo "  clean                - Clean build artifacts"
	@echo ""
	@echo "Shader compilation:"
	@echo "  Input:  $(SHADERS_DIR)/glsl/*.txt, $(SHADERS_DIR)/masks/*.txt"
	@echo "  Output: $(METALLIB)"

all: build compile-flat-shaders

build:
	$(SWIFT) build

run: build
	$(SWIFT) run SwiftVJApp

# Compile shaders using the shader-compile CLI tool
# This produces individual .metal files + a combined .metallib
compile-shaders: build $(BUILD_DIR)
	@echo "Compiling shaders..."
	@if [ -d "$(SHADERS_DIR)/glsl" ]; then \
		$(SHADER_COMPILE) compile $(SHADERS_DIR)/glsl --output $(BUILD_DIR) --report; \
	else \
		echo "No GLSL shaders found in $(SHADERS_DIR)/glsl"; \
	fi
	@echo ""
	@echo "Creating Metal library..."
	@if ls $(BUILD_DIR)/*.metal 1> /dev/null 2>&1; then \
		$(XCRUN) -sdk macosx metal -c $(BUILD_DIR)/*.metal -o $(BUILD_DIR)/shaders.air && \
		$(XCRUN) -sdk macosx metallib $(BUILD_DIR)/shaders.air -o $(METALLIB) && \
		echo "Created: $(METALLIB)"; \
	else \
		echo "No .metal files found to compile"; \
	fi

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/air

# Compile all flat GLSL shaders (glsl/ and masks/) + SharedVertex
compile-flat-shaders: $(BUILD_DIR)
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
	@cp $(METALLIB) Sources/SwiftVJApp/Resources/
	@ls -lh $(METALLIB)

clean:
	rm -rf $(BUILD_DIR)
	rm -rf .build

# Development helpers
.PHONY: test lint

test:
	$(SWIFT) test

lint:
	swiftlint lint --quiet
