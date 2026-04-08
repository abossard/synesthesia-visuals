import AppKit
import Foundation
import RealityKit

@available(macOS 15.0, *)
struct ProceduralMeshParams: LookParams {
    var ribbonLength: Double = 10.0
    var thickness: Double = 0.12
    var noiseScale: Double = 1.0
    var colorSpeed: Double = 0.8

    static var defaultValue: ProceduralMeshParams { .init() }
}

@available(macOS 15.0, *)
final class ProceduralMeshLook: Look {
    typealias Parameters = ProceduralMeshParams

    let name = "Procedural Mesh"
    private let context: LookContext
    private var root = Entity()
    private var meshEntity = ModelEntity()
    private var mesh: LowLevelMesh?
    private let noise = ValueNoise(seed: 42)

    private let segmentCount = 80
    private var vertices: [RibbonVertex] = []
    private var indices: [UInt32] = []

    init(context: LookContext) {
        self.context = context
    }

    func makeRootEntity() -> Entity {
        root = Entity()
        setupMesh()
        if let mesh {
            meshEntity = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
            meshEntity.position = [0, 1.2, 0]
            root.addChild(meshEntity)
        }
        return root
    }

    func update(dt: Double, params: GlobalParams, lookParams: ProceduralMeshParams, time: Double) {
        updateRibbon(time: time, params: lookParams)
        if let mesh {
            mesh.withUnsafeMutableBytes { buffer in
                let vertexPointer = buffer.vertexBuffer(at: 0).bindMemory(to: RibbonVertex.self)
                vertexPointer.assign(from: vertices, count: vertices.count)
                let indexPointer = buffer.indexBuffer.bindMemory(to: UInt32.self)
                indexPointer.assign(from: indices, count: indices.count)
            }
        }

        let hue = Float((time * lookParams.colorSpeed).truncatingRemainder(dividingBy: 1.0))
        if var material = meshEntity.model?.materials.first as? UnlitMaterial {
            material.color = .init(tint: NSColor(hue: CGFloat(hue), saturation: 0.8, brightness: 0.9, alpha: 1.0), texture: nil)
            meshEntity.model?.materials = [material]
        }
    }

    func teardown() {
        root.removeFromParent()
        mesh = nil
    }

    private func setupMesh() {
        vertices = Array(repeating: RibbonVertex(position: .zero, normal: [0, 1, 0], uv: .zero), count: segmentCount * 2)
        indices = []
        for i in 0..<(segmentCount - 1) {
            let base = UInt32(i * 2)
            indices.append(contentsOf: [base, base + 1, base + 2, base + 1, base + 3, base + 2])
        }

        var descriptor = LowLevelMeshDescriptor()
        descriptor.vertexAttributes = [
            .init(name: .position, format: .float3, offset: 0, bufferIndex: 0),
            .init(name: .normal, format: .float3, offset: MemoryLayout<SIMD3<Float>>.stride, bufferIndex: 0),
            .init(name: .texCoord, format: .float2, offset: MemoryLayout<SIMD3<Float>>.stride * 2, bufferIndex: 0),
        ]
        descriptor.vertexLayouts = [
            .init(stride: MemoryLayout<RibbonVertex>.stride)
        ]
        descriptor.indexType = .uint32
        descriptor.primitives = .triangles
        descriptor.vertexBuffer = .init(length: vertices.count * MemoryLayout<RibbonVertex>.stride)
        descriptor.indexBuffer = .init(length: indices.count * MemoryLayout<UInt32>.stride)

        do {
            mesh = try LowLevelMesh(descriptor: descriptor)
            mesh?.withUnsafeMutableBytes { buffer in
                let vertexPointer = buffer.vertexBuffer(at: 0).bindMemory(to: RibbonVertex.self)
                vertexPointer.assign(from: vertices, count: vertices.count)
                let indexPointer = buffer.indexBuffer.bindMemory(to: UInt32.self)
                indexPointer.assign(from: indices, count: indices.count)
            }
        } catch {
            mesh = nil
        }
    }

    private func updateRibbon(time: Double, params: ProceduralMeshParams) {
        let length = Float(params.ribbonLength)
        let thickness = Float(params.thickness)
        for i in 0..<segmentCount {
            let t = Float(i) / Float(segmentCount - 1)
            let z = -length * t
            let offset = Float(noise.sample(x: Double(t * Float(params.noiseScale)), y: time * 0.4))
            let x = sinf(t * 6.0 + Float(time)) * 0.6 + offset * 0.4
            let y = cosf(t * 4.0 + Float(time) * 1.2) * 0.4 + offset * 0.2
            let center = SIMD3<Float>(x, y, z)
            let right = SIMD3<Float>(thickness, 0, 0)

            let v0 = RibbonVertex(position: center - right, normal: [0, 1, 0], uv: [0, t])
            let v1 = RibbonVertex(position: center + right, normal: [0, 1, 0], uv: [1, t])
            vertices[i * 2] = v0
            vertices[i * 2 + 1] = v1
        }
    }
}

@available(macOS 15.0, *)
struct RibbonVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var uv: SIMD2<Float>
}
