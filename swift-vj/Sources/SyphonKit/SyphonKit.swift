// SyphonKit
// Swift wrapper for Syphon - real-time texture sharing on macOS
//
// This module provides Swift-friendly wrappers around the Objective-C
// Syphon framework, enabling Metal texture sharing between apps.

@_exported import Syphon

// Re-export the main types
public typealias SyphonServer = SyphonMetalServer
public typealias SyphonClient = SyphonMetalClient
