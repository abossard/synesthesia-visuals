// ProceduralMeshLook.swift
// RealityKitVJKitchenSink
//
// Procedural mesh look using LowLevelMesh for dynamic geometry.
// Reference: https://developer.apple.com/documentation/realitykit/lowlevelmesh
// Reference: https://developer.apple.com/documentation/realitykit/adding-procedural-assets-to-a-scene

import RealityKit
import Metal
import simd
import CoreGraphics

/// Procedural ribbon/worm mesh with noise-driven animation
@MainActor
final class ProceduralMeshLook: Look {
    typealias Params = ProceduralMeshParams

    let rootEntity: Entity

    private var ribbonEntity: ModelEntity?
    private var lowLevelMesh: LowLevelMesh?

    private let context: LookContext

    // Mesh configuration
    private var segmentCount: Int = 100
    private let radialSegments: Int = 8

    // Animation state
    private var colorPhase: Float = 0

    // Vertex data buffers
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var colors: [SIMD4<Float>] = []
    private var indices: [UInt32] = []

    required init(context: LookContext) {
        self.context = context
        self.rootEntity = Entity()
        rootEntity.name = "ProceduralMeshLook"

        setupEnvironment()
        setupRibbon()
    }

    // MARK: - Setup

    private func setupEnvironment() {
        // Dark background floor
        let floorMesh = MeshResource.generatePlane(width: 20, depth: 20)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0))
        material.metallic = .init(floatLiteral: 0.5)
        material.roughness = .init(floatLiteral: 0.6)

        let floor = ModelEntity(mesh: floorMesh, materials: [material])
        floor.position = SIMD3<Float>(0, -2, 0)

        rootEntity.addChild(floor)

        // Add ambient lighting
        let light = Entity()
        light.components[PointLightComponent.self] = PointLightComponent(
            color: .init(red: 0.6, green: 0.7, blue: 1.0, alpha: 1.0),
            intensity: 3000,
            attenuationRadius: 30
        )
        light.position = SIMD3<Float>(0, 5, 5)
        rootEntity.addChild(light)

        // Secondary light for color variety
        let light2 = Entity()
        light2.components[PointLightComponent.self] = PointLightComponent(
            color: .init(red: 1.0, green: 0.5, blue: 0.3, alpha: 1.0),
            intensity: 2000,
            attenuationRadius: 25
        )
        light2.position = SIMD3<Float>(-5, 3, -3)
        rootEntity.addChild(light2)
    }

    private func setupRibbon() {
        // Initialize vertex buffers
        initializeBuffers()

        // Create initial mesh data
        generateRibbonMesh(time: 0, params: ProceduralMeshParams.defaults)

        // Create LowLevelMesh
        createLowLevelMesh()
    }

    private func initializeBuffers() {
        let vertexCount = segmentCount * radialSegments
        let triangleCount = (segmentCount - 1) * radialSegments * 2

        positions = Array(repeating: .zero, count: vertexCount)
        normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: vertexCount)
        colors = Array(repeating: SIMD4<Float>(1, 1, 1, 1), count: vertexCount)
        indices = Array(repeating: 0, count: triangleCount * 3)
    }

    private func createLowLevelMesh() {
        // Note: LowLevelMesh requires macOS 15+
        // Reference: https://developer.apple.com/documentation/realitykit/lowlevelmesh

        do {
            // Define vertex attributes
            var descriptor = LowLevelMesh.Descriptor()

            descriptor.vertexAttributes = [
                .init(semantic: .position, format: .float3, layoutIndex: 0, offset: 0),
                .init(semantic: .normal, format: .float3, layoutIndex: 0, offset: MemoryLayout<SIMD3<Float>>.stride),
                // Using vertex color as a custom attribute
            ]

            descriptor.vertexLayouts = [
                .init(bufferIndex: 0, bufferStride: MemoryLayout<Vertex>.stride)
            ]

            descriptor.indexType = .uint32

            let vertexCount = segmentCount * radialSegments
            let indexCount = (segmentCount - 1) * radialSegments * 2 * 3

            descriptor.vertexCapacity = vertexCount
            descriptor.indexCapacity = indexCount

            let mesh = try LowLevelMesh(descriptor: descriptor)
            self.lowLevelMesh = mesh

            // Create material
            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: .init(red: 0.8, green: 0.5, blue: 1.0, alpha: 1.0))
            material.metallic = .init(floatLiteral: 0.3)
            material.roughness = .init(floatLiteral: 0.4)

            // Create mesh resource and entity
            let meshResource = try MeshResource(from: mesh)

            let ribbon = ModelEntity(mesh: meshResource, materials: [material])
            ribbon.name = "ProceduralRibbon"

            rootEntity.addChild(ribbon)
            ribbonEntity = ribbon

            // Initial mesh update
            updateMeshData(time: 0, params: ProceduralMeshParams.defaults)

        } catch {
            print("Failed to create LowLevelMesh: \(error)")
            createFallbackRibbon()
        }
    }

    private func createFallbackRibbon() {
        // Fallback using standard mesh generation if LowLevelMesh fails
        let mesh = MeshResource.generateCylinder(height: 5, radius: 0.1)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.8, green: 0.5, blue: 1.0, alpha: 1.0))
        material.metallic = .init(floatLiteral: 0.3)
        material.roughness = .init(floatLiteral: 0.4)

        let ribbon = ModelEntity(mesh: mesh, materials: [material])
        ribbon.name = "FallbackRibbon"

        rootEntity.addChild(ribbon)
        ribbonEntity = ribbon
    }

    // MARK: - Vertex Structure

    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
    }

    // MARK: - Mesh Generation

    private func generateRibbonMesh(time: Float, params: ProceduralMeshParams) {
        let thickness = Float(params.thickness)
        let noiseScale = Float(params.noiseScale)
        let waveCount = Float(params.waveCount)

        // Generate spine curve using noise
        var spinePoints: [SIMD3<Float>] = []

        for i in 0..<segmentCount {
            let t = Float(i) / Float(segmentCount - 1)

            // Base helix
            let helixAngle = t * .pi * 2.0 * waveCount + time * 0.5
            let helixRadius: Float = 2.0 + sin(t * .pi) * 1.0
            let helixHeight = (t - 0.5) * 6.0

            var point = SIMD3<Float>(
                cos(helixAngle) * helixRadius,
                helixHeight,
                sin(helixAngle) * helixRadius
            )

            // Apply noise displacement
            let noiseInput = SIMD3<Float>(t * noiseScale, time * 0.3, 0)
            let noiseOffset = Noise.fbm(SIMD2<Float>(noiseInput.x, noiseInput.y + time * 0.1))

            point.x += (noiseOffset - 0.5) * 1.5
            point.z += (Noise.fbm(SIMD2<Float>(noiseInput.x + 10, noiseInput.y)) - 0.5) * 1.5

            spinePoints.append(point)
        }

        // Generate tube around spine
        for i in 0..<segmentCount {
            let point = spinePoints[i]

            // Calculate tangent
            let tangent: SIMD3<Float>
            if i == 0 {
                tangent = normalize(spinePoints[1] - spinePoints[0])
            } else if i == segmentCount - 1 {
                tangent = normalize(spinePoints[i] - spinePoints[i-1])
            } else {
                tangent = normalize(spinePoints[i+1] - spinePoints[i-1])
            }

            // Calculate normal and binormal (Frenet frame)
            let up = SIMD3<Float>(0, 1, 0)
            var normal = normalize(cross(tangent, up))
            if length(normal) < 0.001 {
                normal = SIMD3<Float>(1, 0, 0)
            }
            let binormal = normalize(cross(tangent, normal))

            // Generate ring of vertices
            let t = Float(i) / Float(segmentCount - 1)
            let localThickness = thickness * (1.0 - abs(t - 0.5) * 0.5)  // Taper at ends

            for j in 0..<radialSegments {
                let angle = Float(j) / Float(radialSegments) * .pi * 2.0

                let radialNormal = normal * cos(angle) + binormal * sin(angle)
                let vertexPos = point + radialNormal * localThickness

                let vertexIndex = i * radialSegments + j
                positions[vertexIndex] = vertexPos
                normals[vertexIndex] = radialNormal

                // Color gradient along ribbon
                let hue = fmod(t + colorPhase, 1.0)
                let color = SIMD3<Float>.fromHSV(h: hue, s: 0.7, v: 1.0)
                colors[vertexIndex] = SIMD4<Float>(color.x, color.y, color.z, 1.0)
            }
        }

        // Generate indices
        var indexOffset = 0
        for i in 0..<(segmentCount - 1) {
            for j in 0..<radialSegments {
                let current = UInt32(i * radialSegments + j)
                let next = UInt32(i * radialSegments + (j + 1) % radialSegments)
                let currentNext = UInt32((i + 1) * radialSegments + j)
                let nextNext = UInt32((i + 1) * radialSegments + (j + 1) % radialSegments)

                // First triangle
                indices[indexOffset] = current
                indices[indexOffset + 1] = currentNext
                indices[indexOffset + 2] = next
                indexOffset += 3

                // Second triangle
                indices[indexOffset] = next
                indices[indexOffset + 1] = currentNext
                indices[indexOffset + 2] = nextNext
                indexOffset += 3
            }
        }
    }

    private func updateMeshData(time: Float, params: ProceduralMeshParams) {
        guard let mesh = lowLevelMesh else { return }

        // Regenerate geometry
        generateRibbonMesh(time: time, params: params)

        // Update LowLevelMesh buffers
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { rawBuffer in
            let vertexBuffer = rawBuffer.bindMemory(to: Vertex.self)
            for i in 0..<positions.count {
                vertexBuffer[i] = Vertex(position: positions[i], normal: normals[i])
            }
        }

        mesh.withUnsafeMutableIndices { rawBuffer in
            let indexBuffer = rawBuffer.bindMemory(to: UInt32.self)
            for i in 0..<indices.count {
                indexBuffer[i] = indices[i]
            }
        }

        // Update mesh parts
        let partCount = (segmentCount - 1) * radialSegments * 2
        
        // Calculate bounds first
        var minBounds = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maxBounds = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for pos in positions {
            minBounds = min(minBounds, pos)
            maxBounds = max(maxBounds, pos)
        }
        let bounds = BoundingBox(min: minBounds, max: maxBounds)
        
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: partCount * 3,
                topology: .triangle,
                materialIndex: 0,
                bounds: bounds
            )
        ])
    }

    // MARK: - Look Protocol

    func activate() {
        colorPhase = 0
    }

    func deactivate() {
        // Nothing special needed
    }

    func update(time: Double, deltaTime: Double, params: ProceduralMeshParams) {
        let t = Float(time)
        let dt = Float(deltaTime)

        // Update color gradient phase
        colorPhase += dt * Float(params.colorGradientSpeed)
        if colorPhase > 1.0 { colorPhase -= 1.0 }

        // Check if segment count changed
        if params.ribbonLength != segmentCount {
            segmentCount = params.ribbonLength
            initializeBuffers()
        }

        // Update mesh geometry
        updateMeshData(time: t, params: params)

        // Apply overall rotation for visual interest
        ribbonEntity?.orientation = simd_quatf(angle: t * 0.1, axis: SIMD3<Float>(0, 1, 0))

        // Update material color based on phase
        updateMaterial(params: params)
    }

    private func updateMaterial(params: ProceduralMeshParams) {
        guard let ribbon = ribbonEntity else { return }

        // Create gradient color based on phase
        let hue = colorPhase
        let color = SIMD3<Float>.fromHSV(h: hue, s: 0.7, v: 1.0)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(
            red: CGFloat(color.x),
            green: CGFloat(color.y),
            blue: CGFloat(color.z),
            alpha: 1.0
        ))
        material.metallic = .init(floatLiteral: 0.3)
        material.roughness = .init(floatLiteral: 0.4)

        ribbon.model?.materials = [material]
    }

    func teardown() {
        lowLevelMesh = nil
        rootEntity.removeFromParent()
    }
}
