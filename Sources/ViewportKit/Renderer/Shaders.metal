// Shaders.metal
// ViewportKit
//
// Metal shaders for shaded and wireframe rendering.

#include <metal_stdlib>
using namespace metal;

// MARK: - Uniform Structs

struct LightData {
    float4 directionAndIntensity;  // xyz = normalized direction, w = intensity
    float4 colorAndEnabled;        // rgb = color, a = 1.0 if enabled, 0.0 if not
};

struct Uniforms {
    float4x4 viewProjectionMatrix;
    float4x4 modelMatrix;
    float4x4 viewMatrix;              // needed for matcap UV calculation
    float4   cameraPosition;           // xyz = position, w = nearPlane
    LightData lights[3];               // key, fill, back
    float4   ambientSkyColor;          // rgb = sky color, w = specularPower
    float4   ambientGroundColor;       // rgb = ground color, w = specularIntensity
    float4   materialParams;           // x = fresnelPower, y = fresnelIntensity,
                                       // z = matcapBlend, w = farPlane
};

struct BodyUniforms {
    float4 color;
    uint   objectIndex;
    uint   _pad0;
    uint   _pad1;
    uint   _pad2;
};

// MARK: - Fragment Output (dual color attachment for pick ID)

struct ShadedFragmentOut {
    float4 color  [[color(0)]];
    uint   pickID [[color(1)]];
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
    float3 viewNormal;       // for matcap UV
    float4 clipPositionCopy; // for depth-based effects
};

struct WireframeVertexOut {
    float4 clipPosition [[position]];
    float4 clipPositionCopy; // for depth-based edge alpha
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
    // View-space normal for matcap
    out.viewNormal = normalize((uniforms.viewMatrix * uniforms.modelMatrix * float4(in.normal, 0.0)).xyz);
    out.clipPositionCopy = out.clipPosition;
    return out;
}

fragment ShadedFragmentOut shaded_fragment(
    ShadedVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant BodyUniforms &bodyUniforms [[buffer(2)]],
    texture2d<float> matcapTexture [[texture(0)]],
    uint primitiveID [[primitive_id]]
) {
    float3 N = normalize(in.worldNormal);
    float3 V = normalize(uniforms.cameraPosition.xyz - in.worldPosition);

    float specularPower = uniforms.ambientSkyColor.w;
    float specularIntensity = uniforms.ambientGroundColor.w;
    float fresnelPower = uniforms.materialParams.x;
    float fresnelIntensity = uniforms.materialParams.y;
    float matcapBlend = uniforms.materialParams.z;

    float3 bodyColor = bodyUniforms.color.rgb;

    // Accumulate lighting from up to 3 lights
    float3 diffuseAccum = float3(0.0);
    float3 specularAccum = float3(0.0);

    for (int i = 0; i < 3; i++) {
        float enabled = uniforms.lights[i].colorAndEnabled.a;
        if (enabled < 0.5) continue;

        float3 lightDir = normalize(-uniforms.lights[i].directionAndIntensity.xyz);
        float intensity = uniforms.lights[i].directionAndIntensity.w;
        float3 lightColor = uniforms.lights[i].colorAndEnabled.rgb;

        // Diffuse
        float diff = max(dot(N, lightDir), 0.0);
        diffuseAccum += bodyColor * diff * intensity * lightColor;

        // Blinn-Phong specular
        float3 H = normalize(lightDir + V);
        float spec = pow(max(dot(N, H), 0.0), specularPower);
        specularAccum += spec * intensity * lightColor * specularIntensity;
    }

    // Hemisphere ambient: blend ground→sky based on normal Y
    float3 skyColor = uniforms.ambientSkyColor.rgb;
    float3 groundColor = uniforms.ambientGroundColor.rgb;
    float hemiBlend = N.y * 0.5 + 0.5;
    float3 ambient = mix(groundColor, skyColor, hemiBlend) * bodyColor;

    // Fresnel rim
    float fresnel = fresnelIntensity * pow(1.0 - saturate(dot(N, V)), fresnelPower);
    float3 rimColor = float3(fresnel);

    // Combine lighting
    float3 litColor = diffuseAccum + specularAccum + ambient + rimColor;

    // Matcap
    if (matcapBlend > 0.001) {
        float3 vn = normalize(in.viewNormal);
        float2 matcapUV = vn.xy * 0.5 + 0.5;
        constexpr sampler matcapSampler(filter::linear);
        float3 matcapColor = matcapTexture.sample(matcapSampler, matcapUV).rgb;
        litColor = mix(litColor, matcapColor * bodyColor, matcapBlend);
    }

    ShadedFragmentOut out;
    out.color = float4(litColor, bodyUniforms.color.a);
    out.pickID = bodyUniforms.objectIndex | (primitiveID << 16);
    return out;
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
    out.clipPositionCopy = out.clipPosition;
    return out;
}

struct WireframeFragmentOut {
    float4 color  [[color(0)]];
    uint   pickID [[color(1)]];
};

fragment WireframeFragmentOut wireframe_fragment(
    WireframeVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant BodyUniforms &bodyUniforms [[buffer(2)]]
) {
    // Contrast-adaptive edge color: light edges on dark bodies, dark edges on light bodies
    float3 bodyColor = bodyUniforms.color.rgb;
    float luminance = dot(bodyColor, float3(0.299, 0.587, 0.114));
    float3 darkEdge = bodyColor * 0.3;
    float3 lightEdge = bodyColor * 0.5 + 0.4;
    float3 edgeColor = mix(lightEdge, darkEdge, smoothstep(0.3, 0.6, luminance));

    // Depth-based edge alpha: near edges fully opaque, far edges fade
    float nearPlane = uniforms.cameraPosition.w;
    float farPlane = uniforms.materialParams.w;
    float clipZ = in.clipPositionCopy.z;
    float clipW = in.clipPositionCopy.w;
    float linearDepth = saturate((clipZ / clipW - nearPlane / farPlane) / (1.0 - nearPlane / farPlane));
    float edgeAlpha = mix(1.0, 0.3, linearDepth);

    WireframeFragmentOut out;
    out.color = float4(edgeColor, edgeAlpha);
    out.pickID = 0xFFFFFFFF; // sentinel — wireframe is not pickable
    return out;
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

struct GridFragmentOut {
    float4 color  [[color(0)]];
    uint   pickID [[color(1)]];
};

fragment GridFragmentOut grid_fragment(
    GridVertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]],
    constant GridUniforms &uniforms [[buffer(0)]]
) {
    // Circular dot via distance from center
    float dist = length(pointCoord - float2(0.5));
    if (dist > 0.5) discard_fragment();

    GridFragmentOut out;
    out.color = uniforms.dotColor;
    out.pickID = 0xFFFFFFFF; // sentinel — grid is not pickable
    return out;
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

struct AxisFragmentOut {
    float4 color  [[color(0)]];
    uint   pickID [[color(1)]];
};

fragment AxisFragmentOut axis_fragment(
    AxisVertexOut in [[stage_in]]
) {
    AxisFragmentOut out;
    out.color = in.color;
    out.pickID = 0xFFFFFFFF; // sentinel — axes are not pickable
    return out;
}
