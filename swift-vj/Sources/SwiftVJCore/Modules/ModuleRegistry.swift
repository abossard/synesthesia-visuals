// ModuleRegistry - Lifecycle management and dependency injection
// Following Grokking Simplicity: calculation-focused, minimal actions

import Foundation

/// Module registration info
public struct ModuleInfo {
    public let name: String
    public let module: any Module
    public let dependencies: [String]
    
    public init(name: String, module: any Module, dependencies: [String] = []) {
        self.name = name
        self.module = module
        self.dependencies = dependencies
    }
}

/// Module registry - manages module lifecycle and dependencies
///
/// Deep module interface:
/// - `register(_:)` - add module to registry
/// - `startAll()` - start modules respecting dependencies
/// - `stopAll()` - stop in reverse order
/// - `get<T>(_:)` - type-safe module retrieval
///
/// Hides: dependency resolution, start ordering, error aggregation
public actor ModuleRegistry {
    
    // MARK: - State
    
    private var modules: [String: ModuleInfo] = [:]
    private var startOrder: [String] = []
    private var started: Set<String> = []
    
    // MARK: - Init
    
    public init() {}
    
    // MARK: - Registration
    
    /// Register a module
    public func register(_ info: ModuleInfo) {
        modules[info.name] = info
        print("[Registry] Registered: \(info.name)")
    }
    
    /// Register module with name and optional dependencies
    public func register(name: String, module: any Module, dependencies: [String] = []) {
        let info = ModuleInfo(name: name, module: module, dependencies: dependencies)
        modules[name] = info
        print("[Registry] Registered: \(name)")
    }
    
    /// Get module by name
    public func get(_ name: String) -> (any Module)? {
        modules[name]?.module
    }
    
    /// Get typed module
    public func get<T: Module>(_ name: String, as type: T.Type) -> T? {
        modules[name]?.module as? T
    }
    
    /// Check if module registered
    public func has(_ name: String) -> Bool {
        modules[name] != nil
    }
    
    /// List registered module names
    public var registeredNames: [String] {
        Array(modules.keys)
    }
    
    // MARK: - Lifecycle
    
    /// Start all registered modules respecting dependencies
    public func startAll() async throws {
        let order = try resolveDependencies()
        startOrder = order
        
        print("[Registry] Starting \(order.count) modules: \(order.joined(separator: " → "))")
        
        var errors: [(String, Error)] = []
        
        for name in order {
            guard let info = modules[name] else { continue }
            
            do {
                try await info.module.start()
                started.insert(name)
                print("[Registry] Started: \(name)")
            } catch {
                errors.append((name, error))
                print("[Registry] Failed to start \(name): \(error)")
            }
        }
        
        if !errors.isEmpty {
            throw ModuleError.startupFailed("Failed to start: \(errors.map { $0.0 }.joined(separator: ", "))")
        }
    }
    
    /// Stop all modules in reverse order
    public func stopAll() async {
        let reversed = startOrder.reversed()
        
        print("[Registry] Stopping \(reversed.count) modules")
        
        for name in reversed {
            guard let info = modules[name], started.contains(name) else { continue }
            
            await info.module.stop()
            started.remove(name)
            print("[Registry] Stopped: \(name)")
        }
    }
    
    /// Start a specific module and its dependencies
    public func start(_ name: String) async throws {
        guard let info = modules[name] else {
            throw ModuleError.dependencyUnavailable(name)
        }
        
        // Start dependencies first
        for dep in info.dependencies {
            if !started.contains(dep) {
                try await start(dep)
            }
        }
        
        // Start this module
        if !started.contains(name) {
            try await info.module.start()
            started.insert(name)
            
            if !startOrder.contains(name) {
                startOrder.append(name)
            }
            
            print("[Registry] Started: \(name)")
        }
    }
    
    /// Stop a specific module
    public func stop(_ name: String) async {
        guard let info = modules[name], started.contains(name) else { return }
        
        await info.module.stop()
        started.remove(name)
        print("[Registry] Stopped: \(name)")
    }
    
    /// Get status of all modules
    public func getStatus() async -> [String: [String: Any]] {
        var allStatus: [String: [String: Any]] = [:]
        
        for (name, info) in modules {
            var status = await info.module.getStatus()
            status["registered"] = true
            status["started"] = started.contains(name)
            status["dependencies"] = info.dependencies
            allStatus[name] = status
        }
        
        return allStatus
    }
    
    // MARK: - Private
    
    /// Resolve dependencies using topological sort
    private func resolveDependencies() throws -> [String] {
        var visited = Set<String>()
        var visiting = Set<String>()
        var order: [String] = []
        
        func visit(_ name: String) throws {
            if visited.contains(name) { return }
            if visiting.contains(name) {
                throw ModuleError.configurationError("Circular dependency: \(name)")
            }
            
            visiting.insert(name)
            
            if let info = modules[name] {
                for dep in info.dependencies {
                    guard modules[dep] != nil else {
                        throw ModuleError.dependencyUnavailable(dep)
                    }
                    try visit(dep)
                }
            }
            
            visiting.remove(name)
            visited.insert(name)
            order.append(name)
        }
        
        for name in modules.keys {
            try visit(name)
        }
        
        return order
    }
}
