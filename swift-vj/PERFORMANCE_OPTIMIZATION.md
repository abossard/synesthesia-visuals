# Performance Optimization Opportunities

This document outlines potential performance optimizations for the Swift-VJ application, particularly relevant when running on the same machine as the DJ software.

## GPU Optimization Opportunities

### Shader Compilation and Caching

**Current**: Shaders are compiled at runtime when selected.

**Optimization Opportunities**:
- [ ] Pre-compile all shaders to `.metallib` at app startup or build time
- [ ] Cache compiled Metal pipeline states to avoid recompilation
- [ ] Implement shader warm-up during idle time (compile popular shaders in background)
- [ ] Add shader quality levels (low/medium/high) that adjust complexity

**Implementation Notes**:
```swift
// TODO: In ShaderTile.swift, add pre-compilation support
// - Build .metallib during app startup in background
// - Store compiled pipeline states in LRU cache
// - Add quality setting that reduces shader features
```

**Estimated Impact**: 20-30% reduction in GPU load during shader transitions, smoother performance.

### Metal Pipeline Settings

**Current**: Default Metal pipeline configuration.

**Optimization Opportunities**:
- [ ] Reduce render resolution when GPU is under load (dynamic quality scaling)
- [ ] Implement frame rate limiting (target 30fps instead of 60fps)
- [ ] Use Metal's low-latency mode for better responsiveness
- [ ] Optimize blend modes and texture sampling

**Implementation Notes**:
```swift
// TODO: In RenderEngine.swift, add quality settings
struct RenderQualitySettings {
    var targetFPS: Int = 60  // Can be reduced to 30
    var renderScale: Float = 1.0  // Can be reduced to 0.5 or 0.75
    var useSimpleBlending: Bool = false
    var maxActiveShaders: Int = 2  // Limit concurrent shader tiles
}
```

**Estimated Impact**: 30-40% reduction in GPU usage at lower quality settings.

### Texture and Buffer Management

**Current**: Images and textures loaded on-demand.

**Optimization Opportunities**:
- [ ] Implement texture compression (ASTC/BC7)
- [ ] Use Metal texture streaming for large images
- [ ] Recycle texture buffers instead of reallocating
- [ ] Implement texture resolution limits

**Implementation Notes**:
```swift
// TODO: In ImageTile.swift, add texture optimization
// - Compress textures using Metal's native formats
// - Implement texture pooling for reuse
// - Add max texture size setting (e.g., 2048x2048)
```

**Estimated Impact**: 15-25% reduction in GPU memory usage.

## CPU Optimization Opportunities

### Async Processing and Batching

**Current**: Pipeline processing is async but sequential.

**Optimization Opportunities**:
- [ ] Batch OSC messages to reduce syscall overhead
- [ ] Use structured concurrency to parallelize independent pipeline steps
- [ ] Implement lazy loading for shader analysis
- [ ] Cache shader matching results per track

**Implementation Notes**:
```swift
// TODO: In PipelineModule.swift, add parallel processing
// - Run lyrics fetch and AI analysis in parallel
// - Batch OSC sends (collect and send every 50ms)
// - Add TrackMatchCache for shader selections
```

**Estimated Impact**: 20-30% reduction in CPU load during track changes.

### LLM Backend Optimization

**Current**: LLM calls are made for each track, with caching.

**Optimization Opportunities**:
- [ ] Prefer local LM Studio over OpenAI to reduce latency
- [ ] Implement request timeout and fallback faster
- [ ] Add basic AI analysis fallback that's instant
- [ ] Pre-analyze common tracks during idle time

**Implementation Notes**:
```swift
// TODO: In LLMClient.swift, add optimizations
// - Reduce timeout from 60s to 30s
// - Implement immediate fallback to basic analysis
// - Add background pre-analysis queue
```

**Estimated Impact**: Faster track transitions, 10-15% reduction in CPU wait time.

### OSC Processing

**Current**: High-frequency OSC messages processed individually.

**Optimization Opportunities**:
- [ ] Implement OSC message batching and throttling
- [ ] Use dedicated queue for audio OSC to avoid main thread blocking
- [ ] Add configurable OSC rate limiting
- [ ] Filter redundant messages (position updates)

**Implementation Notes**:
```swift
// TODO: In OSCHub.swift, add batching
// - Collect messages in 16ms windows, process in batch
// - Throttle position updates to 10Hz instead of 60Hz
// - Deduplicate identical messages in batch
```

**Estimated Impact**: 15-20% reduction in CPU overhead from OSC processing.

## Memory Optimization Opportunities

### Cache Management

**Current**: Unlimited caches for lyrics, AI analysis, images.

**Optimization Opportunities**:
- [ ] Implement LRU cache with size limits
- [ ] Add cache eviction policy (e.g., max 100MB)
- [ ] Clear old cache entries (>30 days)
- [ ] Add memory pressure monitoring

**Implementation Notes**:
```swift
// TODO: In Cache infrastructure
// - Add max cache size settings
// - Implement LRU eviction when limit reached
// - Monitor memory pressure and clear caches proactively
```

**Estimated Impact**: Prevent memory bloat, keep app under 500MB RAM.

### Shader Analysis Storage

**Current**: All shader analysis kept in memory.

**Optimization Opportunities**:
- [ ] Lazy-load shader analysis on-demand
- [ ] Keep only top 100 shaders in memory
- [ ] Compress analysis JSON in memory

**Implementation Notes**:
```swift
// TODO: In ShaderMatcher.swift
// - Load analysis only when needed for matching
// - Keep frequently-used shaders in hot cache
// - Store others on disk, load on demand
```

**Estimated Impact**: 50-100MB reduction in memory usage.

## Settings for Performance vs Quality Tradeoffs

### Recommended Settings Structure

Add to Settings.swift:

```swift
public struct PerformanceSettings {
    // GPU Settings
    var targetFPS: Int = 60  // 30 for low-end systems
    var renderScale: Float = 1.0  // 0.5-0.75 for low-end systems
    var precompileShaders: Bool = true
    var maxConcurrentShaders: Int = 2
    
    // CPU Settings
    var parallelPipelineSteps: Bool = true
    var llmTimeout: TimeInterval = 30  // Reduce from 60
    var oscBatchingEnabled: Bool = true
    var oscThrottleHz: Int = 10  // Down from 60
    
    // Memory Settings
    var maxCacheSizeMB: Int = 200
    var lazyLoadShaders: Bool = false  // true for low memory
    
    // Quality Presets
    enum Preset {
        case performance  // Optimized for running alongside DJ software
        case balanced     // Default
        case quality      // Maximum visual quality
    }
    
    static func preset(_ preset: Preset) -> PerformanceSettings {
        switch preset {
        case .performance:
            return PerformanceSettings(
                targetFPS: 30,
                renderScale: 0.75,
                llmTimeout: 20,
                oscThrottleHz: 5,
                maxCacheSizeMB: 100
            )
        case .balanced:
            return PerformanceSettings()
        case .quality:
            return PerformanceSettings(
                targetFPS: 60,
                renderScale: 1.0,
                precompileShaders: true,
                parallelPipelineSteps: true
            )
        }
    }
}
```

## Priority Implementation Order

For auto-drive mode running alongside DJ software, implement in this order:

1. **High Priority** (Immediate performance wins):
   - [ ] OSC message batching and throttling
   - [ ] Reduce LLM timeout from 60s to 30s
   - [ ] Add performance preset (30fps, 0.75 render scale)
   
2. **Medium Priority** (Noticeable improvements):
   - [ ] Pre-compile shaders in background
   - [ ] Parallel pipeline processing
   - [ ] Cache size limits
   
3. **Low Priority** (Nice to have):
   - [ ] Texture compression
   - [ ] Lazy shader loading
   - [ ] Background pre-analysis

## Testing Performance

Add performance monitoring:

```swift
// TODO: Add performance metrics to AppState
struct PerformanceMetrics {
    var averageFPS: Double
    var gpuUsagePercent: Double
    var cpuUsagePercent: Double
    var memoryUsedMB: Double
    var oscMessagesPerSecond: Int
    var shaderSwitchLatencyMs: Double
}
```

## Notes for Implementation

- All performance optimizations should be **opt-in** via settings
- Default should remain "balanced" for best out-of-box experience
- Add "Performance" preset that can be selected with one click
- Monitor and log performance metrics to help users tune settings
- Consider auto-detecting system load and suggesting performance mode
