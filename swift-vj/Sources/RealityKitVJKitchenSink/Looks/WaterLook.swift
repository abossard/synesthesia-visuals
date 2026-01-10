// WaterLook.swift
// RealityKitVJKitchenSink
//
// Water surface look with CustomMaterial for wave displacement and shading.
// Reference: https://developer.apple.com/documentation/realitykit/custommaterial

import RealityKit
import Metal
import simd
import CoreGraphics

/// Water surface with animated waves using CustomMaterial
@MainActor
final class WaterLook: Look {
    typealias Params = WaterParams

    let rootEntity: Entity

    private var waterPlaneEntity: ModelEntity?
    private var customMaterial: CustomMaterial?
    private var underglowLight: Entity?

    private let context: LookContext
    private var shaderLibrary: MTLLibrary?

    // Animation state
    private var animTime: Float = 0

    required init(context: LookContext) {
        self.context = context
        self.rootEntity = Entity()
        rootEntity.name = "WaterLook"

        // Create shader library from embedded source
        createShaderLibrary(device: context.device)

        setupWaterPlane()
        setupEnvironment()
        setupLighting()
    }

    // MARK: - Setup

    private func createShaderLibrary(device: MTLDevice) {
        // Create Metal library from embedded shader source
        do {
            shaderLibrary = try device.makeLibrary(source: WaterLook.shaderSource, options: nil)
        } catch {
            print("Failed to create water shader library: \(error)")
        }
    }

    private func setupWaterPlane() {
        // Create a high-resolution plane for the water surface
        let planeSize: Float = 30.0
        let mesh = MeshResource.generatePlane(
            width: planeSize,
            depth: planeSize,
            cornerRadius: 0
        )

        // Create a fallback PBR material (CustomMaterial will be applied if available)
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.1, green: 0.3, blue: 0.6, alpha: 1.0))
        material.metallic = .init(floatLiteral: 0.0)
        material.roughness = .init(floatLiteral: 0.1)

        let waterPlane = ModelEntity(mesh: mesh, materials: [material])
        waterPlane.name = "WaterSurface"
        waterPlane.position = SIMD3<Float>(0, 0, 0)

        rootEntity.addChild(waterPlane)
        waterPlaneEntity = waterPlane

        // Try to apply custom material
        applyCustomMaterial()
    }

    private func applyCustomMaterial() {
        guard let library = shaderLibrary,
              let waterPlane = waterPlaneEntity else { return }

        do {
            // Create custom material with surface shader and geometry modifier
            // Reference: https://developer.apple.com/documentation/realitykit/modifying-realitykit-rendering-using-custom-materials
            let surfaceShader = CustomMaterial.SurfaceShader(named: "waterSurfaceShader", in: library)
            let geometryModifier = CustomMaterial.GeometryModifier(named: "waterGeometryModifier", in: library)

            var customMat = try CustomMaterial(
                surfaceShader: surfaceShader,
                geometryModifier: geometryModifier,
                lightingModel: .lit
            )

            // Set initial uniform values
            customMat.custom.value = SIMD4<Float>(0.0, 0.3, 2.0, 0.0)  // time, amplitude, frequency, unused

            // Configure material properties
            customMat.faceCulling = .none

            waterPlane.model?.materials = [customMat]
            self.customMaterial = customMat

        } catch {
            print("Failed to create custom material: \(error)")
            // Keep the fallback PBR material
        }
    }

    private func setupEnvironment() {
        // Add a floor/depth indicator beneath the water
        let floorMesh = MeshResource.generatePlane(width: 40, depth: 40)

        var floorMaterial = PhysicallyBasedMaterial()
        floorMaterial.baseColor = .init(tint: .init(red: 0.02, green: 0.05, blue: 0.1, alpha: 1.0))
        floorMaterial.metallic = .init(floatLiteral: 0.0)
        floorMaterial.roughness = .init(floatLiteral: 0.9)

        let floor = ModelEntity(mesh: floorMesh, materials: [floorMaterial])
        floor.name = "SeaFloor"
        floor.position = SIMD3<Float>(0, -5, 0)

        rootEntity.addChild(floor)

        // Add some underwater objects for visual interest
        addUnderwaterRocks()
    }

    private func addUnderwaterRocks() {
        let rockCount = 8

        for i in 0..<rockCount {
            let angle = Float(i) / Float(rockCount) * 2 * .pi
            let distance = Float.random(in: 5...12)

            let position = SIMD3<Float>(
                cos(angle) * distance,
                Float.random(in: -4 ... -1),
                sin(angle) * distance
            )

            let rockSize = Float.random(in: 0.5...2.0)
            let rock = createRock(size: rockSize, position: position)
            rootEntity.addChild(rock)
        }
    }

    private func createRock(size: Float, position: SIMD3<Float>) -> Entity {
        let mesh = MeshResource.generateSphere(radius: size)

        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: .init(red: 0.15, green: 0.12, blue: 0.1, alpha: 1.0))
        material.roughness = .init(floatLiteral: 0.95)

        let rock = ModelEntity(mesh: mesh, materials: [material])
        rock.name = "UnderwaterRock"
        rock.position = position

        // Random scale distortion for more natural shapes
        rock.scale = SIMD3<Float>(
            Float.random(in: 0.8...1.2),
            Float.random(in: 0.6...1.4),
            Float.random(in: 0.8...1.2)
        )

        return rock
    }

    private func setupLighting() {
        // Key light (sun-like)
        let sunLight = Entity()
        sunLight.components[DirectionalLightComponent.self] = DirectionalLightComponent(
            color: .init(red: 1.0, green: 0.95, blue: 0.8, alpha: 1.0),
            intensity: 2000,
            isRealWorldProxy: false
        )
        sunLight.orientation = simd_quatf(angle: -.pi / 4, axis: SIMD3<Float>(1, 0, 0))
        sunLight.name = "SunLight"
        rootEntity.addChild(sunLight)

        // Underglow for caustic-like effect
        let underGlow = Entity()
        underGlow.components[PointLightComponent.self] = PointLightComponent(
            color: .init(red: 0.2, green: 0.5, blue: 0.8, alpha: 1.0),
            intensity: 1000,
            attenuationRadius: 15
        )
        underGlow.position = SIMD3<Float>(0, -3, 0)
        underGlow.name = "UnderGlow"
        rootEntity.addChild(underGlow)
        underglowLight = underGlow
    }

    // MARK: - Look Protocol

    func activate() {
        animTime = 0
    }

    func deactivate() {
        // Nothing special needed
    }

    func update(time: Double, deltaTime: Double, params: WaterParams) {
        animTime = Float(time)

        // Update custom material uniforms
        updateWaterMaterial(params: params)

        // Animate underglow for caustic effect
        updateCausticGlow(time: animTime, params: params)
    }

    private func updateWaterMaterial(params: WaterParams) {
        guard var material = customMaterial,
              let waterPlane = waterPlaneEntity else { return }

        // Pack parameters into custom value
        // x: time, y: amplitude, z: frequency, w: unused
        material.custom.value = SIMD4<Float>(
            animTime,
            Float(params.waveAmplitude),
            Float(params.waveFrequency),
            0.0
        )

        // Update roughness/specular
        // Note: CustomMaterial has different property access
        // We'd need to pass these through the custom value or separate uniforms

        waterPlane.model?.materials = [material]
        self.customMaterial = material
    }

    private func updateCausticGlow(time: Float, params: WaterParams) {
        guard let glow = underglowLight else { return }

        // Animate caustic glow position
        let wanderX = sin(time * 0.5) * 3.0
        let wanderZ = cos(time * 0.7) * 3.0
        glow.position = SIMD3<Float>(wanderX, -3, wanderZ)

        // Pulse intensity
        let pulse = 800 + sin(time * 2.0) * 200
        if var light = glow.components[PointLightComponent.self] {
            light.intensity = pulse * Float(params.specular)

            // Tint based on params
            let tint = params.causticTint
            light.color = .init(
                red: CGFloat(tint.x),
                green: CGFloat(tint.y),
                blue: CGFloat(tint.z),
                alpha: 1.0
            )

            glow.components[PointLightComponent.self] = light
        }
    }

    func teardown() {
        rootEntity.removeFromParent()
    }

    // MARK: - Embedded Shader Source

    private static let shaderSource = """
    #include <metal_stdlib>
    #include <RealityKit/RealityKit.h>
    using namespace metal;

    // Geometry modifier for wave displacement
    [[visible]]
    void waterGeometryModifier(realitykit::geometry_parameters params) {
        // Get custom uniforms: x=time, y=amplitude, z=frequency
        float time = params.uniforms().custom_parameter()[0];
        float amplitude = params.uniforms().custom_parameter()[1];
        float frequency = params.uniforms().custom_parameter()[2];

        // Get world position
        float3 worldPos = params.geometry().world_position();

        // Calculate wave displacement
        float wave1 = sin(worldPos.x * frequency + time * 2.0) * amplitude;
        float wave2 = sin(worldPos.z * frequency * 0.8 + time * 1.5) * amplitude * 0.7;
        float wave3 = sin((worldPos.x + worldPos.z) * frequency * 0.5 + time) * amplitude * 0.5;

        float totalWave = wave1 + wave2 + wave3;

        // Displace vertex in model space (Y up)
        float3 offset = float3(0, totalWave, 0);
        params.geometry().set_model_position_offset(offset);

        // Calculate normal from wave derivatives
        float dx = cos(worldPos.x * frequency + time * 2.0) * frequency * amplitude
                 + cos((worldPos.x + worldPos.z) * frequency * 0.5 + time) * frequency * 0.25 * amplitude;
        float dz = cos(worldPos.z * frequency * 0.8 + time * 1.5) * frequency * 0.56 * amplitude
                 + cos((worldPos.x + worldPos.z) * frequency * 0.5 + time) * frequency * 0.25 * amplitude;

        float3 normal = normalize(float3(-dx, 1.0, -dz));
        params.geometry().set_normal(normal);
    }

    // Surface shader for water appearance
    [[visible]]
    void waterSurfaceShader(realitykit::surface_parameters params) {
        float time = params.uniforms().custom_parameter()[0];
        float3 worldPos = params.geometry().world_position();

        // Base water color with depth fade
        float depth = saturate(-worldPos.y * 0.1 + 0.5);
        float3 shallowColor = float3(0.2, 0.5, 0.7);
        float3 deepColor = float3(0.05, 0.15, 0.3);
        float3 waterColor = mix(shallowColor, deepColor, depth);

        // Add foam on wave peaks
        float foam = smoothstep(0.2, 0.4, worldPos.y);
        waterColor = mix(waterColor, float3(0.9), foam * 0.3);

        // Fresnel effect for reflectivity
        float3 viewDir = normalize(params.geometry().view_direction());
        float3 normal = params.geometry().normal();
        float fresnel = pow(1.0 - saturate(dot(viewDir, normal)), 3.0);

        // Set surface properties
        params.surface().set_base_color(half3(waterColor));
        params.surface().set_metallic(half(0.0));
        params.surface().set_roughness(half(mix(0.1, 0.4, fresnel)));
        params.surface().set_specular(half(0.8));

        // Add slight emissive for underwater glow effect
        float3 emissive = waterColor * 0.05 * (1.0 + sin(time + worldPos.x * 0.5) * 0.5);
        params.surface().set_emissive_color(half3(emissive));
    }
    """
}
