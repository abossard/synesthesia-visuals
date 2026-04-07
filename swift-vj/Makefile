# swift-vj Makefile
# Build targets for shader compilation and app

.PHONY: all build run clean compile-shaders compile-flat-shaders shaders help \
       release bundle bundle-release dmg \
       profile-build profile-hud profile-metal profile-cpu profile-alloc \
       profile-leaks profile-vmmap profile-gpu-power profile-session \
       analyze-session profiling-dir

# Version (override with: make dmg VERSION=1.2.0)
VERSION ?= dev

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
	@echo "  release              - Release build"
	@echo "  bundle               - Create .app bundle (debug)"
	@echo "  bundle-release       - Create .app bundle (release)"
	@echo "  dmg                  - Create distributable DMG (make dmg VERSION=1.0.0)"
	@echo "  clean                - Clean build artifacts"
	@echo ""
	@echo "Profiling (results saved to profiling/):"
	@echo "  profile-hud          - Run with Metal HUD overlay (live GPU stats)"
	@echo "  profile-metal        - Metal System Trace (GPU util, per-pass time)"
	@echo "  profile-cpu          - Time Profiler (CPU hotspots per thread)"
	@echo "  profile-alloc        - Allocations (Metal resource sizes, growth)"
	@echo "  profile-leaks        - Leaks (resource leaks after shader switches)"
	@echo "  profile-vmmap        - Memory snapshot (attach to running app)"
	@echo "  profile-gpu-power    - GPU power/utilization (60 sec capture)"
	@echo "  profile-session      - Full session: CPU trace + vmmap + samples"
	@echo "  analyze-session      - Analyze most recent profiling session"
	@echo ""
	@echo "Shader compilation:"
	@echo "  Input:  $(SHADERS_DIR)/glsl/*.txt, $(SHADERS_DIR)/masks/*.txt"
	@echo "  Output: $(METALLIB)"

all: build shaders

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release --target SwiftVJApp

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

bundle:
	./bundle-app.sh

bundle-release:
	./bundle-app.sh --release --version "$(VERSION)"

dmg: bundle-release
	./create-dmg.sh --app-path "Swift VJ.app" --output "SwiftVJ-$(VERSION).dmg"

clean:
	rm -rf $(BUILD_DIR)
	rm -rf .build

# Development helpers
.PHONY: test lint

test:
	$(SWIFT) test

lint:
	swiftlint lint --quiet

# ─── Profiling Targets ───────────────────────────────────────────────
# No source code changes. All traces saved to profiling/ directory.
# See docs/profiling-guide.md for interpretation.

profiling-dir:
	@mkdir -p profiling

profile-build:
	$(SWIFT) build -c release -Xswiftc -g

profile-hud: profile-build
	MTL_HUD_ENABLED=1 .build/release/SwiftVJApp

profile-metal: profile-build profiling-dir
	$(XCRUN) xctrace record --template "Metal System Trace" \
	  --output profiling/metal-trace-$$(date +%Y%m%d-%H%M%S).trace \
	  --launch .build/release/SwiftVJApp

profile-cpu: profile-build profiling-dir
	$(XCRUN) xctrace record --template "Time Profiler" \
	  --output profiling/cpu-trace-$$(date +%Y%m%d-%H%M%S).trace \
	  --launch .build/release/SwiftVJApp

profile-alloc: profile-build profiling-dir
	$(XCRUN) xctrace record --template "Allocations" \
	  --output profiling/alloc-trace-$$(date +%Y%m%d-%H%M%S).trace \
	  --launch .build/release/SwiftVJApp

profile-leaks: profile-build profiling-dir
	$(XCRUN) xctrace record --template "Leaks" \
	  --output profiling/leaks-trace-$$(date +%Y%m%d-%H%M%S).trace \
	  --launch .build/release/SwiftVJApp

profile-vmmap: profiling-dir
	@PID=$$(pgrep -x SwiftVJApp) && \
	  vmmap --summary $$PID > profiling/vmmap-$$(date +%Y%m%d-%H%M%S).txt && \
	  echo "Saved vmmap to profiling/" || \
	  echo "SwiftVJApp not running. Start it first."

profile-gpu-power: profiling-dir
	sudo powermetrics --samplers gpu_power -i 1000 -n 60 \
	  > profiling/gpu-power-$$(date +%Y%m%d-%H%M%S).txt

profile-session: profile-build profiling-dir
	./Scripts/profile-session.sh

analyze-session:
	./Scripts/analyze-profile.sh
