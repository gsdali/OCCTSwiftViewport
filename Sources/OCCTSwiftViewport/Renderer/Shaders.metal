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
    float4x4 lightViewProjectionMatrix; // for shadow mapping
    float4   shadowParams;             // x = bias, y = intensity, z = enabled, w = unused
    float4   clipPlanes[4];            // xyz = normal, w = distance (dot(N,P)+w < 0 → clip)
    uint     clipPlaneCount;           // number of active clip planes (0–4)
    float3   _clipPad;                 // padding to 16-byte alignment
};

struct BodyUniforms {
    float4 color;
    uint   objectIndex;
    float  roughness;
    float  metallic;
    uint   isSelected;  // 1 = selected, 2 = hovered
};

// MARK: - Fragment Output (color-only for MSAA pass)

struct ShadedFragmentOut {
    float4 color [[color(0)]];
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
    float3 worldPosition;    // for clip plane testing
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

// MARK: - PBR Helpers

// GGX/Trowbridge-Reitz normal distribution function
inline float distributionGGX(float NdotH, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (M_PI_F * denom * denom + 1e-7);
}

// Schlick-GGX geometry function
inline float geometrySchlickGGX(float NdotV, float roughness) {
    float r = roughness + 1.0;
    float k = (r * r) / 8.0;
    return NdotV / (NdotV * (1.0 - k) + k);
}

// Smith's geometry function
inline float geometrySmith(float NdotV, float NdotL, float roughness) {
    return geometrySchlickGGX(NdotV, roughness) * geometrySchlickGGX(NdotL, roughness);
}

// Schlick Fresnel approximation
inline float3 fresnelSchlick(float cosTheta, float3 F0) {
    return F0 + (1.0 - F0) * pow(saturate(1.0 - cosTheta), 5.0);
}

// Procedural environment reflection: sky-ground gradient
inline float3 sampleEnvironment(float3 direction) {
    float t = direction.y * 0.5 + 0.5; // 0 = ground, 1 = sky
    float3 groundColor = float3(0.3, 0.28, 0.25);
    float3 horizonColor = float3(0.7, 0.72, 0.75);
    float3 skyColor = float3(0.85, 0.9, 1.0);
    // Two-segment blend: ground→horizon→sky
    if (t < 0.5) {
        return mix(groundColor, horizonColor, smoothstep(0.0, 0.5, t));
    } else {
        return mix(horizonColor, skyColor, smoothstep(0.5, 1.0, t));
    }
}

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

// PCF shadow sampling with 4 taps
inline float sampleShadow(float4 lightSpacePos, depth2d<float> shadowMap, float bias) {
    // Perspective divide
    float3 projCoords = lightSpacePos.xyz / lightSpacePos.w;
    // Transform from [-1,1] to [0,1] UV space
    float2 shadowUV = projCoords.xy * 0.5 + 0.5;
    shadowUV.y = 1.0 - shadowUV.y; // Metal texture origin is top-left
    float currentDepth = projCoords.z;

    // Outside shadow map bounds → no shadow
    if (shadowUV.x < 0.0 || shadowUV.x > 1.0 || shadowUV.y < 0.0 || shadowUV.y > 1.0) {
        return 1.0;
    }

    constexpr sampler shadowSampler(filter::linear, address::clamp_to_edge, compare_func::less);

    // 4-tap PCF
    float2 texelSize = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
    float shadow = 0.0;
    const float2 offsets[4] = {
        float2(-0.5, -0.5), float2( 0.5, -0.5),
        float2(-0.5,  0.5), float2( 0.5,  0.5)
    };
    for (int i = 0; i < 4; i++) {
        float2 uv = shadowUV + offsets[i] * texelSize;
        shadow += shadowMap.sample_compare(shadowSampler, uv, currentDepth - bias);
    }
    return shadow / 4.0;
}

fragment ShadedFragmentOut shaded_fragment(
    ShadedVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant BodyUniforms &bodyUniforms [[buffer(2)]],
    texture2d<float> matcapTexture [[texture(0)]],
    depth2d<float> shadowMap [[texture(1)]]
) {
    // Clip plane discard
    for (uint cp = 0; cp < uniforms.clipPlaneCount; cp++) {
        float4 plane = uniforms.clipPlanes[cp];
        if (dot(plane.xyz, in.worldPosition) + plane.w < 0.0) {
            discard_fragment();
        }
    }

    float3 N = normalize(in.worldNormal);
    float3 V = normalize(uniforms.cameraPosition.xyz - in.worldPosition);
    float NdotV = max(dot(N, V), 0.001);

    float fresnelPower = uniforms.materialParams.x;
    float fresnelIntensity = uniforms.materialParams.y;
    float matcapBlend = uniforms.materialParams.z;

    float roughness = clamp(bodyUniforms.roughness, 0.04, 1.0);
    float metallic = saturate(bodyUniforms.metallic);
    float3 bodyColor = bodyUniforms.color.rgb;

    // PBR base reflectance (dielectric = 0.04, metal = body color)
    float3 F0 = mix(float3(0.04), bodyColor, metallic);

    // Accumulate lighting from up to 3 lights
    float3 Lo = float3(0.0); // Outgoing radiance

    for (int i = 0; i < 3; i++) {
        float enabled = uniforms.lights[i].colorAndEnabled.a;
        if (enabled < 0.5) continue;

        float3 L = normalize(-uniforms.lights[i].directionAndIntensity.xyz);
        float intensity = uniforms.lights[i].directionAndIntensity.w;
        float3 lightColor = uniforms.lights[i].colorAndEnabled.rgb;
        float3 H = normalize(L + V);

        float NdotL = max(dot(N, L), 0.0);
        float NdotH = max(dot(N, H), 0.0);
        float HdotV = max(dot(H, V), 0.0);

        // Cook-Torrance BRDF
        float D = distributionGGX(NdotH, roughness);
        float G = geometrySmith(NdotV, NdotL, roughness);
        float3 F = fresnelSchlick(HdotV, F0);

        float3 numerator = D * G * F;
        float denominator = 4.0 * NdotV * NdotL + 0.0001;
        float3 specular = numerator / denominator;

        // Energy conservation: diffuse only for non-reflected light
        float3 kD = (1.0 - F) * (1.0 - metallic);
        float3 diffuse = kD * bodyColor / M_PI_F;

        Lo += (diffuse + specular) * lightColor * intensity * NdotL;
    }

    // Shadow mapping: darken key light contribution
    if (uniforms.shadowParams.z > 0.5) {
        float4 lightSpacePos = uniforms.lightViewProjectionMatrix * uniforms.modelMatrix * float4(in.worldPosition, 1.0);
        float shadowFactor = sampleShadow(lightSpacePos, shadowMap, uniforms.shadowParams.x);
        float shadowDarkness = uniforms.shadowParams.y;
        Lo *= mix(1.0 - shadowDarkness, 1.0, shadowFactor);
    }

    // Tri-axis ambient: vary ambient by normal in all 3 directions (not just Y)
    // This breaks up uniform color on faces at the same elevation but different azimuths
    float3 skyColor = uniforms.ambientSkyColor.rgb;
    float3 groundColor = uniforms.ambientGroundColor.rgb;
    float3 ambientY = mix(groundColor, skyColor, N.y * 0.5 + 0.5);
    // Side axis: warm on +X, cool on -X (simulates fill/key side difference)
    float3 ambientX = mix(float3(0.35, 0.30, 0.28), float3(0.28, 0.30, 0.35), N.x * 0.5 + 0.5);
    // Depth axis: slightly brighter facing camera, darker facing away
    float3 ambientZ = mix(float3(0.25, 0.25, 0.27), float3(0.32, 0.32, 0.30), N.z * 0.5 + 0.5);
    float3 ambient = ((ambientY * 0.6) + (ambientX * 0.2) + (ambientZ * 0.2)) * bodyColor * (1.0 - metallic * 0.5);

    // Environment reflection approximation
    float3 R = reflect(-V, N);
    float3 envColor = sampleEnvironment(R);
    float envFresnel = pow(1.0 - NdotV, 5.0);
    float envStrength = mix(0.04, 1.0, metallic) * mix(0.3, 1.0, envFresnel) * (1.0 - roughness * 0.7);
    float3 envContribution = envColor * mix(float3(0.04), bodyColor, metallic) * envStrength;

    // Fresnel rim (reduced for metallic surfaces)
    float fresnel = fresnelIntensity * (1.0 - metallic * 0.5) * pow(1.0 - NdotV, fresnelPower);
    float3 rimColor = float3(fresnel);

    // Combine lighting
    float3 litColor = Lo + ambient + envContribution + rimColor;

    // Screen-space curvature: brightens convex edges, darkens concave creases
    // Uses fragment derivatives of the world normal to detect surface curvature.
    // Suppressed at mesh boundaries where derivatives are discontinuous.
    {
        float3 dx = dfdx(N);
        float3 dy = dfdy(N);
        float derivMag = length(dx) + length(dy);
        // Only apply curvature where derivatives are smooth (not at triangle seams)
        if (derivMag < 1.5) {
            float3 xneg = N - dx;
            float3 xpos = N + dx;
            float3 yneg = N - dy;
            float3 ypos = N + dy;
            float depth = in.clipPositionCopy.w;
            float curvature = (cross(xneg, xpos).y - cross(yneg, ypos).x) * 4.0 / max(depth, 0.01);
            // Smooth falloff near the derivative threshold to avoid hard transitions
            float strength = 0.15 * smoothstep(1.5, 0.5, derivMag);
            curvature = clamp(curvature, -1.0, 1.0);
            litColor *= 1.0 + curvature * strength;
        }
    }

    // Matcap
    if (matcapBlend > 0.001) {
        float3 vn = normalize(in.viewNormal);
        float2 matcapUV = vn.xy * 0.5 + 0.5;
        constexpr sampler matcapSampler(filter::linear);
        float3 matcapColor = matcapTexture.sample(matcapSampler, matcapUV).rgb;
        litColor = mix(litColor, matcapColor * bodyColor, matcapBlend);
    }

    // Selection tint: subtle blue overlay for selected, lighter for hovered
    if (bodyUniforms.isSelected == 1) {
        litColor = mix(litColor, float3(0.3, 0.5, 1.0), 0.15);
    } else if (bodyUniforms.isSelected == 2) {
        litColor = mix(litColor, float3(0.4, 0.6, 1.0), 0.08);
    }

    ShadedFragmentOut out;
    out.color = float4(litColor, bodyUniforms.color.a);
    return out;
}

// MARK: - Pick-Only Pipeline (1x, no MSAA)

struct PickVertexOut {
    float4 clipPosition [[position]];
};

struct PickFragmentOut {
    uint pickID [[color(0)]];
};

vertex PickVertexOut pick_vertex(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    PickVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition = uniforms.viewProjectionMatrix * worldPos;
    return out;
}

fragment PickFragmentOut pick_fragment(
    PickVertexOut in [[stage_in]],
    constant BodyUniforms &bodyUniforms [[buffer(2)]],
    uint primitiveID [[primitive_id]]
) {
    PickFragmentOut out;
    out.pickID = bodyUniforms.objectIndex | (primitiveID << 16);
    return out;
}

// MARK: - Selection Outline Pipeline

struct SelectionOutlineParams {
    float4x4 viewProjectionMatrix;
    float4x4 modelMatrix;
    float3 outlineColor;
    float outlineScale;
};

struct SelectionOutlineVertexOut {
    float4 clipPosition [[position]];
};

// Renders geometry slightly scaled along normals for the outline effect
vertex SelectionOutlineVertexOut selection_outline_vertex(
    VertexIn in [[stage_in]],
    constant SelectionOutlineParams &params [[buffer(1)]]
) {
    // Scale vertex position along normal to create outline thickness
    float3 expandedPos = in.position + in.normal * params.outlineScale;
    float4 worldPos = params.modelMatrix * float4(expandedPos, 1.0);

    SelectionOutlineVertexOut out;
    out.clipPosition = params.viewProjectionMatrix * worldPos;
    return out;
}

struct SelectionOutlineFragmentOut {
    float4 color [[color(0)]];
};

fragment SelectionOutlineFragmentOut selection_outline_fragment(
    SelectionOutlineVertexOut in [[stage_in]],
    constant SelectionOutlineParams &params [[buffer(1)]]
) {
    SelectionOutlineFragmentOut out;
    out.color = float4(params.outlineColor, 1.0);
    return out;
}

// MARK: - Shadow Map Pipeline

struct ShadowUniforms {
    float4x4 lightViewProjectionMatrix;
    float4x4 modelMatrix;
};

struct ShadowVertexOut {
    float4 clipPosition [[position]];
};

vertex ShadowVertexOut shadow_vertex(
    VertexIn in [[stage_in]],
    constant ShadowUniforms &uniforms [[buffer(1)]]
) {
    ShadowVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition = uniforms.lightViewProjectionMatrix * worldPos;
    return out;
}

// MARK: - Depth-Only Pipeline (for SSAO depth pass)

vertex PickVertexOut depth_only_vertex(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    PickVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.clipPosition = uniforms.viewProjectionMatrix * worldPos;
    return out;
}

// Empty fragment — only depth is written
fragment void depth_only_fragment() {
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
    out.worldPosition = worldPos.xyz;
    return out;
}

struct WireframeFragmentOut {
    float4 color [[color(0)]];
};

fragment WireframeFragmentOut wireframe_fragment(
    WireframeVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant BodyUniforms &bodyUniforms [[buffer(2)]]
) {
    // Clip plane discard
    for (uint cp = 0; cp < uniforms.clipPlaneCount; cp++) {
        float4 plane = uniforms.clipPlanes[cp];
        if (dot(plane.xyz, in.worldPosition) + plane.w < 0.0) {
            discard_fragment();
        }
    }

    float3 bodyColor = bodyUniforms.color.rgb;
    float bodyAlpha = bodyUniforms.color.a;

    // Edge-only bodies (metallic == -1 sentinel): use body color directly
    if (bodyUniforms.metallic < 0.0) {
        WireframeFragmentOut out;
        out.color = float4(bodyColor, bodyAlpha);
        return out;
    }

    float edgeIntensity = max(uniforms.shadowParams.w, 0.0); // shadowParams.w = edge intensity

    // Contrast-adaptive edge color: light edges on dark bodies, dark edges on light bodies
    float luminance = dot(bodyColor, float3(0.299, 0.587, 0.114));
    // At intensity 1.0: darkEdge = bodyColor*0.4, lightEdge = bodyColor*0.5+0.5 (original)
    // At higher intensity: push edges darker/more contrasting
    float darkMul = mix(0.4, 0.15, saturate(edgeIntensity - 1.0));
    float3 darkEdge = max(bodyColor * darkMul, float3(0.1));
    float lightMul = mix(0.5, 0.3, saturate(edgeIntensity - 1.0));
    float3 lightEdge = bodyColor * lightMul + (1.0 - lightMul);
    float3 edgeColor = mix(lightEdge, darkEdge, smoothstep(0.3, 0.6, luminance));

    // Depth-based edge alpha: near edges fully opaque, far edges fade
    float nearPlane = uniforms.cameraPosition.w;
    float farPlane = uniforms.materialParams.w;
    float clipZ = in.clipPositionCopy.z;
    float clipW = in.clipPositionCopy.w;
    float linearDepth = saturate((clipZ / clipW - nearPlane / farPlane) / (1.0 - nearPlane / farPlane));
    // At intensity 1.0: alpha fades from 1.0 to 0.3 (original)
    // At higher intensity: minimum alpha stays higher
    float minAlpha = mix(0.3, 0.8, saturate(edgeIntensity - 1.0));
    float edgeAlpha = mix(1.0, minAlpha, linearDepth) * saturate(edgeIntensity);

    WireframeFragmentOut out;
    out.color = float4(edgeColor, edgeAlpha);
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
    float4 color [[color(0)]];
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
    float4 color [[color(0)]];
};

fragment AxisFragmentOut axis_fragment(
    AxisVertexOut in [[stage_in]]
) {
    AxisFragmentOut out;
    out.color = in.color;
    return out;
}

// MARK: - SSAO Post-Process

struct SSAOParams {
    float2 texelSize;    // 1.0 / textureSize
    float  radius;       // sample radius in UV space
    float  intensity;    // darkness multiplier
    float  nearPlane;
    float  farPlane;
    float  silhouetteThickness; // edge detection spread
    float  silhouetteIntensity; // edge darkness
};

struct FullscreenVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Fullscreen triangle (3 vertices cover entire screen, no vertex buffer needed)
vertex FullscreenVertexOut fullscreen_vertex(uint vertexID [[vertex_id]]) {
    FullscreenVertexOut out;
    // Generate a fullscreen triangle from vertex ID (0, 1, 2)
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
    out.texCoord = float2(uv.x, 1.0 - uv.y);
    return out;
}

// Linearize a reverse-Z depth value
inline float linearizeDepth(float depth, float near, float far) {
    return near * far / (far - depth * (far - near));
}

// SSAO-lite + Edge Silhouettes combined post-process
fragment float4 ssao_fragment(
    FullscreenVertexOut in [[stage_in]],
    texture2d<float> depthTexture [[texture(0)]],
    texture2d<float> colorTexture [[texture(1)]],
    constant SSAOParams &params [[buffer(0)]]
) {
    constexpr sampler texSampler(filter::linear, address::clamp_to_edge);
    constexpr sampler pointSampler(filter::nearest, address::clamp_to_edge);

    float4 sceneColor = colorTexture.sample(texSampler, in.texCoord);
    float depth = depthTexture.sample(pointSampler, in.texCoord).r;

    // Skip background (depth at or near 1.0)
    if (depth > 0.9999) {
        return sceneColor;
    }

    float linearDepth = linearizeDepth(depth, params.nearPlane, params.farPlane);
    float result_ao = 1.0;
    float result_edge = 0.0;

    // --- SSAO ---
    if (params.intensity > 0.001) {
        // Two-ring sample pattern: inner ring (tight creases) + outer ring (broader AO)
        const float2 offsets[16] = {
            // Inner ring (radius 1.0) — catches tight internal angles
            float2(-1.0,  0.0), float2( 1.0,  0.0),
            float2( 0.0, -1.0), float2( 0.0,  1.0),
            float2(-0.707, -0.707), float2( 0.707, -0.707),
            float2(-0.707,  0.707), float2( 0.707,  0.707),
            // Outer ring (radius 2.0) — broader ambient occlusion
            float2(-2.0,  0.0), float2( 2.0,  0.0),
            float2( 0.0, -2.0), float2( 0.0,  2.0),
            float2(-1.414, -1.414), float2( 1.414, -1.414),
            float2(-1.414,  1.414), float2( 1.414,  1.414)
        };

        float occlusion = 0.0;
        float scaledRadius = params.radius / max(linearDepth, 0.1);

        for (int i = 0; i < 16; i++) {
            float2 sampleUV = in.texCoord + offsets[i] * scaledRadius * params.texelSize * 4.0;
            float sampleDepth = depthTexture.sample(pointSampler, sampleUV).r;
            float sampleLinear = linearizeDepth(sampleDepth, params.nearPlane, params.farPlane);

            float diff = linearDepth - sampleLinear;
            float rangeCheck = smoothstep(0.0, 1.0, scaledRadius / (abs(diff) + 0.001));
            occlusion += step(0.0005, diff) * rangeCheck;
        }

        result_ao = 1.0 - (occlusion / 16.0) * params.intensity;
        result_ao = clamp(result_ao, 0.0, 1.0);
    }

    // --- Edge Silhouettes (Sobel on depth) ---
    if (params.silhouetteIntensity > 0.001) {
        float2 ts = params.texelSize * params.silhouetteThickness;

        // Sample 3x3 neighborhood depths
        float d00 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2(-ts.x, -ts.y)).r, params.nearPlane, params.farPlane);
        float d10 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2(  0.0, -ts.y)).r, params.nearPlane, params.farPlane);
        float d20 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2( ts.x, -ts.y)).r, params.nearPlane, params.farPlane);
        float d01 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2(-ts.x,   0.0)).r, params.nearPlane, params.farPlane);
        float d21 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2( ts.x,   0.0)).r, params.nearPlane, params.farPlane);
        float d02 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2(-ts.x,  ts.y)).r, params.nearPlane, params.farPlane);
        float d12 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2(  0.0,  ts.y)).r, params.nearPlane, params.farPlane);
        float d22 = linearizeDepth(depthTexture.sample(pointSampler, in.texCoord + float2( ts.x,  ts.y)).r, params.nearPlane, params.farPlane);

        // Sobel X and Y
        float sobelX = -d00 + d20 - 2.0*d01 + 2.0*d21 - d02 + d22;
        float sobelY = -d00 - 2.0*d10 - d20 + d02 + 2.0*d12 + d22;

        // Normalize by center depth to make edges depth-invariant
        float edgeMag = sqrt(sobelX * sobelX + sobelY * sobelY) / max(linearDepth, 0.01);

        // Threshold and scale
        result_edge = smoothstep(0.02, 0.15, edgeMag) * params.silhouetteIntensity;
    }

    // --- Depth Unsharp Masking ---
    // Computes average depth in a neighborhood and boosts contrast where depth
    // deviates from the local average, enhancing perception of depth separation
    // between adjacent faces. Only uses samples at similar depths to avoid
    // silhouette halo artifacts.
    float depthContrast = 1.0;
    if (params.intensity > 0.001) {
        float blurredDepth = 0.0;
        float validSamples = 0.0;
        const float2 unsharpOffsets[8] = {
            float2(-3.0,  0.0), float2( 3.0,  0.0),
            float2( 0.0, -3.0), float2( 0.0,  3.0),
            float2(-2.12, -2.12), float2( 2.12, -2.12),
            float2(-2.12,  2.12), float2( 2.12,  2.12)
        };
        for (int i = 0; i < 8; i++) {
            float2 sampleUV = in.texCoord + unsharpOffsets[i] * params.texelSize * 3.0;
            float rawDepth = depthTexture.sample(pointSampler, sampleUV).r;
            // Skip background samples to avoid silhouette halos
            if (rawDepth > 0.9999) continue;
            float sd = linearizeDepth(rawDepth, params.nearPlane, params.farPlane);
            // Skip samples at very different depths (silhouette boundary)
            if (abs(sd - linearDepth) / max(linearDepth, 0.01) > 0.3) continue;
            blurredDepth += sd;
            validSamples += 1.0;
        }

        if (validSamples > 2.0) {
            blurredDepth /= validSamples;
            float spatialImportance = (linearDepth - blurredDepth) / max(linearDepth, 0.01);
            depthContrast = 1.0 + spatialImportance * 0.2;
            depthContrast = clamp(depthContrast, 0.85, 1.15);
        }
    }

    // Combine: darken by AO, edge silhouettes, and depth contrast
    float3 finalColor = sceneColor.rgb * result_ao * depthContrast;
    finalColor = mix(finalColor, float3(0.1, 0.1, 0.12), result_edge);

    // --- ACES Filmic Tone Mapping ---
    // Compresses dynamic range so highlights don't clip and shadows retain detail.
    // Uses the Narkowicz ACES approximation (industry standard).
    {
        float exposure = 1.1;
        float3 x = finalColor * exposure;
        float a = 2.51;
        float b = 0.03;
        float c = 2.43;
        float d = 0.59;
        float e = 0.14;
        finalColor = saturate((x * (a * x + b)) / (x * (c * x + d) + e));
    }

    return float4(finalColor, sceneColor.a);
}
