// ShaderSelectionManager.swift - Manages shader selection for rendering
// Uses ObservableShaderRepository as single source of truth

import Foundation
import SwiftUI
import simd
import ShaderRepository

// MARK: - Shader Selection Manager

/// Manages which shader is selected for main/mask output.
/// - Reads from ObservableShaderRepository (single source of truth)
/// - Does NOT own shader list - only selection state
/// - Provides navigation (next/prev) within filtered lists
@MainActor
public final class ShaderSelectionManager: ObservableObject {
    
    // MARK: - State
    
    /// Current main shader display state
    @Published public var mainState: ShaderDisplayState = .empty
    
    /// Current mask shader display state
    @Published public var maskState: ShaderDisplayState = .empty
    
    /// Current index in regular shaders list
    @Published public private(set) var mainIndex: Int = 0
    
    /// Current index in masks list
    @Published public private(set) var maskIndex: Int = 0
    
    // MARK: - Dependencies
    
    /// Reference to the repository (weak to avoid retain cycle, set via configure)
    public weak var repository: ObservableShaderRepository?
    
    /// Logger callback
    public var logger: ((String, LogLevel) -> Void)?
    
    // MARK: - Init
    
    public init() {}
    
    /// Configure with repository reference
    public func configure(repository: ObservableShaderRepository) {
        self.repository = repository
    }
    
    // MARK: - Selection
    
    /// Select a shader for the MAIN output (any shader)
    public func selectMain(name: String) {
        guard let repo = repository else {
            logger?("[Selection] Repository not configured", .error)
            return
        }
        
        guard let shader = repo.shader(named: name) else {
            logger?("[Selection] ❌ '\(name)' not found", .error)
            suggestSimilar(name)
            return
        }
        
        // Update index if in regular shaders list
        if let index = repo.regularShaders.firstIndex(where: { $0.name == name }) {
            mainIndex = index
        }
        
        mainState = ShaderDisplayState(
            current: shader,
            isLoaded: true,
            error: nil,
            audioTime: mainState.audioTime,
            syntheticMouse: mainState.syntheticMouse
        )
        logger?("[Selection] ✓ Main: \(name)\(shader.isMask ? " (mask)" : "")", .debug)
    }
    
    /// Select a shader for the MASK output (any shader)
    public func selectMask(name: String) {
        guard let repo = repository else {
            logger?("[Selection] Repository not configured", .error)
            return
        }
        
        guard let shader = repo.shader(named: name) else {
            logger?("[Selection] ❌ Mask '\(name)' not found", .error)
            suggestSimilar(name)
            return
        }
        
        // Update index if in masks list
        if let index = repo.masks.firstIndex(where: { $0.name == name }) {
            maskIndex = index
        }
        
        maskState = ShaderDisplayState(
            current: shader,
            isLoaded: true,
            error: nil,
            audioTime: 0,
            syntheticMouse: SIMD2(0.5, 0.5)
        )
        logger?("[Selection] ✓ Mask: \(name)\(shader.isMask ? " (mask)" : "")", .debug)
    }
    
    // MARK: - Navigation
    
    /// Navigate to next main shader
    public func nextMain() {
        guard let repo = repository else { return }
        let list = repo.regularShaders
        guard !list.isEmpty else { return }
        
        mainIndex = (mainIndex + 1) % list.count
        selectMainFromList(list)
    }
    
    /// Navigate to previous main shader
    public func prevMain() {
        guard let repo = repository else { return }
        let list = repo.regularShaders
        guard !list.isEmpty else { return }
        
        mainIndex = (mainIndex - 1 + list.count) % list.count
        selectMainFromList(list)
    }
    
    /// Navigate to next mask
    public func nextMask() {
        guard let repo = repository else { return }
        let list = repo.masks
        guard !list.isEmpty else { return }
        
        maskIndex = (maskIndex + 1) % list.count
        selectMaskFromList(list)
    }
    
    /// Navigate to previous mask
    public func prevMask() {
        guard let repo = repository else { return }
        let list = repo.masks
        guard !list.isEmpty else { return }
        
        maskIndex = (maskIndex - 1 + list.count) % list.count
        selectMaskFromList(list)
    }
    
    /// Select random main shader
    public func randomMain() {
        guard let repo = repository else { return }
        let list = repo.regularShaders
        guard !list.isEmpty else { return }
        
        mainIndex = Int.random(in: 0..<list.count)
        selectMainFromList(list)
    }
    
    /// Select random mask
    public func randomMask() {
        guard let repo = repository else { return }
        let list = repo.masks
        guard !list.isEmpty else { return }
        
        maskIndex = Int.random(in: 0..<list.count)
        selectMaskFromList(list)
    }
    
    /// Clear main shader selection
    public func clearMain() {
        mainState = .empty
        mainIndex = 0
    }
    
    /// Clear mask shader selection
    public func clearMask() {
        maskState = .empty
        maskIndex = 0
    }
    
    // MARK: - Convenience Accessors
    
    /// Current main shader name
    public var mainShaderName: String? {
        mainState.current?.name
    }
    
    /// Current mask shader name
    public var maskShaderName: String? {
        maskState.current?.name
    }
    
    /// Check if main shader is loaded
    public var isMainLoaded: Bool {
        mainState.isLoaded
    }
    
    /// Check if mask shader is loaded
    public var isMaskLoaded: Bool {
        maskState.isLoaded
    }
    
    // MARK: - Private Helpers
    
    private func selectMainFromList(_ list: [ShaderInfo]) {
        guard mainIndex < list.count else { return }
        let shader = list[mainIndex]
        mainState = ShaderDisplayState(
            current: shader,
            isLoaded: true,
            error: nil,
            audioTime: mainState.audioTime,
            syntheticMouse: mainState.syntheticMouse
        )
    }
    
    private func selectMaskFromList(_ list: [ShaderInfo]) {
        guard maskIndex < list.count else { return }
        let shader = list[maskIndex]
        maskState = ShaderDisplayState(
            current: shader,
            isLoaded: true,
            error: nil,
            audioTime: 0,
            syntheticMouse: SIMD2(0.5, 0.5)
        )
    }
    
    private func suggestSimilar(_ name: String) {
        guard let repo = repository else { return }
        let similar = repo.allShaders.filter {
            $0.name.lowercased().contains(name.lowercased()) ||
            name.lowercased().contains($0.name.lowercased())
        }
        if !similar.isEmpty {
            let hint = "Similar: \(similar.prefix(5).map { $0.name }.joined(separator: ", "))"
            logger?(hint, .warning)
        }
    }
}

// Note: ShaderDisplayState is defined in RenderingTypes.swift
