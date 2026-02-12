// Shaders.metal
// ViewportKit
//
// Metal shaders for shaded and wireframe rendering.

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniform Structs

struct Uniforms {
    float4x4 viewProjectionMatrix;
    float4x4 modelMatrix;
    float3   lightDirection;
    float    lightIntensity;
    float    ambientIntensity;
    float3   cameraPosition;
};

struct BodyUniforms {
    float4 color;
};

// MARK: - Vertex Structs

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct ShadedVertexOut {
    float4 clipPosition [[position]];
    float3 worldNormal;
    float3 worldPosition;
};

struct WireframeVertexOut {
    float4 clipPosition [[position]];
};

// MARK: - Grid / Axis Structs

struct GridVertexIn {
    float3 position [[attribute(0)]];
};

struct GridVertexOut {
    float4 clipPosition [[position]];
    float  pointSize [[point_size]];
};

struct LineVertexOut {
    float4 clipPosition [[position]];
};

// MARK: - Shaded Pipeline

vertex ShadedVertexOut shaded_vertex(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    ShadedVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition = uniforms.viewProjectionMatrix * worldPos;
    out.worldNormal = normalize((uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.worldPosition = worldPos.xyz;
    return out;
}

fragment float4 shaded_fragment(
    ShadedVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant BodyUniforms &bodyUniforms [[buffer(2)]]
) {
    float3 normal = normalize(in.worldNormal);
    float3 lightDir = normalize(-uniforms.lightDirection);

    // Diffuse lighting
    float diff = max(dot(normal, lightDir), 0.0);
    float3 diffuse = bodyUniforms.color.rgb * diff * uniforms.lightIntensity;

    // Ambient
    float3 ambient = bodyUniforms.color.rgb * uniforms.ambientIntensity;

    float3 finalColor = diffuse + ambient;
    return float4(finalColor, bodyUniforms.color.a);
}

// MARK: - Wireframe Pipeline

vertex WireframeVertexOut wireframe_vertex(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    WireframeVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition = uniforms.viewProjectionMatrix * worldPos;
    // Small depth bias to prevent z-fighting over shaded surfaces
    out.clipPosition.z -= 0.0001 * out.clipPosition.w;
    return out;
}

fragment float4 wireframe_fragment(
    WireframeVertexOut in [[stage_in]],
    constant BodyUniforms &bodyUniforms [[buffer(2)]]
) {
    // Darker version of body colour for edge lines
    float3 edgeColor = bodyUniforms.color.rgb * 0.3;
    return float4(edgeColor, 1.0);
}

// MARK: - Grid Pipeline (Instanced Dots)

struct GridUniforms {
    float4x4 viewProjectionMatrix;
    float3   gridOrigin;
    float    spacing;
    int      halfCount;
    float    dotSize;
    float4   dotColor;
};

vertex GridVertexOut grid_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    constant GridUniforms &uniforms [[buffer(0)]]
) {
    int count = uniforms.halfCount * 2 + 1;
    int ix = int(instanceID) % count - uniforms.halfCount;
    int iz = int(instanceID) / count - uniforms.halfCount;

    float3 pos = uniforms.gridOrigin + float3(float(ix) * uniforms.spacing, 0.0, float(iz) * uniforms.spacing);
    GridVertexOut out;
    out.clipPosition = uniforms.viewProjectionMatrix * float4(pos, 1.0);
    out.pointSize = uniforms.dotSize;
    return out;
}

fragment float4 grid_fragment(
    GridVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]],
    constant GridUniforms &uniforms [[buffer(0)]]
) {
    // Circular dot via distance from center
    float dist = length(pointCoord - float2(0.5));
    if (dist > 0.5) discard_fragment();
    return uniforms.dotColor;
}

// MARK: - Axis Pipeline (Coloured Lines)

struct AxisUniforms {
    float4x4 viewProjectionMatrix;
};

struct AxisVertexIn {
    float3 position [[attribute(0)]];
    float4 color    [[attribute(1)]];
};

struct AxisVertexOut {
    float4 clipPosition [[position]];
    float4 color;
};

vertex AxisVertexOut axis_vertex(
    AxisVertexIn in [[stage_in]],
    constant AxisUniforms &uniforms [[buffer(1)]]
) {
    AxisVertexOut out;
    out.clipPosition = uniforms.viewProjectionMatrix * float4(in.position, 1.0);
    out.color = in.color;
    return out;
}

fragment float4 axis_fragment(
    AxisVertexOut in [[stage_in]]
) {
    return in.color;
}
