// Derived and substantially adapted for SwiftUI/Metal from Paper Shaders.
// Upstream: https://github.com/paper-design/shaders/tree/d9540abccaf21e107aa32079cddb0111c8c3c05b
// Copyright Lost Coast Labs, Inc. Licensed under Apache License 2.0.
// Changes: native Metal signatures, bounded presets, procedural noise, and reduced sampling cost.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

static float2 leafyUV(float2 position, float4 bounds) {
    float2 size = max(bounds.zw, float2(1.0));
    return (position - bounds.xy) / size;
}

static float leafyHash21(float2 value) {
    value = fract(value * float2(123.34, 456.21));
    value += dot(value, value + 45.32);
    return fract(value.x * value.y);
}

static float leafyValueNoise(float2 value) {
    float2 index = floor(value);
    float2 fraction = fract(value);
    float2 curve = fraction * fraction * (3.0 - 2.0 * fraction);
    float bottom = mix(leafyHash21(index), leafyHash21(index + float2(1.0, 0.0)), curve.x);
    float top = mix(leafyHash21(index + float2(0.0, 1.0)), leafyHash21(index + 1.0), curve.x);
    return mix(bottom, top, curve.y);
}

static half4 leafyWeightedGradient(
    float2 uv,
    float2 p0,
    float2 p1,
    float2 p2,
    float2 p3,
    half4 c0,
    half4 c1,
    half4 c2,
    half4 c3
) {
    float weights[4] = {
        1.0 / (pow(length(uv - p0), 2.2) + 0.015),
        1.0 / (pow(length(uv - p1), 2.2) + 0.015),
        1.0 / (pow(length(uv - p2), 2.2) + 0.015),
        1.0 / (pow(length(uv - p3), 2.2) + 0.015)
    };
    float total = weights[0] + weights[1] + weights[2] + weights[3];
    half3 color = (
        c0.rgb * half(weights[0])
        + c1.rgb * half(weights[1])
        + c2.rgb * half(weights[2])
        + c3.rgb * half(weights[3])
    ) / half(total);
    return half4(color, 1.0h);
}

[[ stitchable ]] half4 leafyStaticMeshGradient(
    float2 position,
    float4 bounds,
    half4 c0,
    half4 c1,
    half4 c2,
    half4 c3
) {
    float2 uv = leafyUV(position, bounds);
    uv += float2(
        0.05 * sin(uv.y * 8.0),
        0.04 * cos(uv.x * 7.0)
    );
    return leafyWeightedGradient(
        uv,
        float2(0.08, 0.15),
        float2(0.82, 0.12),
        float2(0.28, 0.88),
        float2(0.92, 0.78),
        c0, c1, c2, c3
    );
}

[[ stitchable ]] half4 leafyWaves(
    float2 position,
    float4 bounds,
    half4 backgroundColor,
    half4 foregroundColor
) {
    float2 uv = leafyUV(position, bounds);
    float wave = sin(uv.x * 20.0 + sin(uv.x * 5.0) * 1.5);
    float stripes = 0.5 + 0.5 * sin((uv.y + wave * 0.035) * 42.0);
    stripes = smoothstep(0.28, 0.72, stripes);
    half3 color = mix(backgroundColor.rgb, foregroundColor.rgb, half(stripes));
    return half4(color, 1.0h);
}

[[ stitchable ]] half4 leafyMeshGradient(
    float2 position,
    float4 bounds,
    float time,
    half4 c0,
    half4 c1,
    half4 c2,
    half4 c3
) {
    float2 uv = leafyUV(position, bounds);
    float t = time * 0.16;
    float2 p0 = 0.5 + 0.46 * float2(sin(t), cos(t * 0.83));
    float2 p1 = 0.5 + 0.44 * float2(cos(t * 0.71 + 1.4), sin(t * 0.92 + 0.8));
    float2 p2 = 0.5 + 0.42 * float2(sin(t * 0.64 + 2.8), cos(t * 0.76 + 2.1));
    float2 p3 = 0.5 + 0.40 * float2(cos(t * 0.88 + 4.2), sin(t * 0.68 + 3.5));
    float distortion = leafyValueNoise(uv * 4.0 + t * 0.1) - 0.5;
    uv += distortion * 0.035;
    return leafyWeightedGradient(uv, p0, p1, p2, p3, c0, c1, c2, c3);
}

[[ stitchable ]] half4 leafyPaperTexture(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds
) {
    half4 source = layer.sample(position);
    float2 uv = leafyUV(position, bounds);
    float fine = leafyHash21(position * 0.73) - 0.5;
    float fiber = sin((uv.x * 1.7 + uv.y) * 180.0 + leafyValueNoise(uv * 25.0) * 5.0);
    float crumple = leafyValueNoise(uv * 8.0) - 0.5;
    float texture = fine * 0.045 + fiber * 0.018 + crumple * 0.065;
    return half4(clamp(source.rgb + half(texture), 0.0h, 1.0h), source.a);
}

[[ stitchable ]] half4 leafyFlutedGlass(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds
) {
    float2 uv = leafyUV(position, bounds);
    float stripe = sin(uv.x * 82.0);
    float lens = stripe * stripe * stripe;
    float offset = lens * 13.0;
    half4 source = layer.sample(position + float2(offset, 0.0));
    float edge = 0.5 + 0.5 * cos(uv.x * 82.0);
    source.rgb = clamp(source.rgb + half((edge - 0.5) * 0.10), 0.0h, 1.0h);
    return source;
}

[[ stitchable ]] half4 leafyWater(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    float time
) {
    float2 uv = leafyUV(position, bounds);
    float t = time * 0.45;
    float waveA = sin(uv.y * 24.0 + t) + cos(uv.x * 19.0 - t * 0.8);
    float waveB = sin((uv.x + uv.y) * 31.0 - t * 1.2);
    float2 offset = float2(waveA + waveB, waveB - waveA) * 2.8;
    half4 source = layer.sample(position + offset);
    float highlight = smoothstep(1.55, 2.7, waveA + waveB) * 0.11;
    source.rgb = clamp(source.rgb + half(highlight), 0.0h, 1.0h);
    return source;
}

[[ stitchable ]] half4 leafyImageDithering(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    half4 backgroundColor,
    half4 foregroundColor,
    half4 highlightColor
) {
    (void) bounds;
    const float pixelSize = 5.0;
    float2 cell = floor(position / pixelSize);
    float2 samplePosition = (cell + 0.5) * pixelSize;
    half4 source = layer.sample(samplePosition);
    float luminance = dot(float3(source.rgb), float3(0.2126, 0.7152, 0.0722));
    float threshold = leafyHash21(cell) * 0.34 - 0.17;
    float level = clamp(luminance + threshold, 0.0, 1.0);
    half3 color = level < 0.42
        ? backgroundColor.rgb
        : (level < 0.72 ? foregroundColor.rgb : highlightColor.rgb);
    return half4(color, source.a);
}

[[ stitchable ]] half4 leafyHalftoneDots(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds,
    half4 backgroundColor,
    half4 foregroundColor
) {
    (void) bounds;
    const float cellSize = 13.0;
    float2 cell = floor(position / cellSize);
    float2 center = (cell + 0.5) * cellSize;
    half4 source = layer.sample(center);
    float luminance = dot(float3(source.rgb), float3(0.2126, 0.7152, 0.0722));
    float radius = sqrt(clamp(1.0 - luminance, 0.0, 1.0)) * cellSize * 0.56;
    float distanceFromCenter = length(position - center);
    float dotMask = 1.0 - smoothstep(radius - 0.9, radius + 0.9, distanceFromCenter);
    half3 color = mix(backgroundColor.rgb, foregroundColor.rgb, half(dotMask));
    return half4(color, source.a);
}

static float leafyHalftoneScreen(float2 position, float angle, float amount) {
    float sine = sin(angle);
    float cosine = cos(angle);
    float2 rotated = float2(
        position.x * cosine - position.y * sine,
        position.x * sine + position.y * cosine
    );
    const float cellSize = 8.0;
    float2 local = fract(rotated / cellSize) - 0.5;
    float radius = sqrt(clamp(amount, 0.0, 1.0)) * 0.68;
    float distanceFromCenter = length(local);
    return 1.0 - smoothstep(radius - 0.055, radius + 0.055, distanceFromCenter);
}

[[ stitchable ]] half4 leafyHalftoneCMYK(
    float2 position,
    SwiftUI::Layer layer,
    float4 bounds
) {
    (void) bounds;
    half4 source = layer.sample(position);
    float3 rgb = clamp(float3(source.rgb), 0.0, 1.0);
    float key = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
    float denominator = max(1.0 - key, 0.001);
    float cyan = (1.0 - rgb.r - key) / denominator;
    float magenta = (1.0 - rgb.g - key) / denominator;
    float yellow = (1.0 - rgb.b - key) / denominator;

    float c = leafyHalftoneScreen(position, 0.261799, cyan);
    float m = leafyHalftoneScreen(position, 1.308997, magenta);
    float y = leafyHalftoneScreen(position, 0.0, yellow);
    float k = leafyHalftoneScreen(position, 0.785398, key);

    float3 paper = float3(0.985, 0.975, 0.94);
    float3 color = paper;
    color *= mix(float3(1.0), float3(0.05, 0.72, 0.90), c * 0.82);
    color *= mix(float3(1.0), float3(0.93, 0.12, 0.52), m * 0.82);
    color *= mix(float3(1.0), float3(1.00, 0.82, 0.05), y * 0.76);
    color *= mix(float3(1.0), float3(0.08, 0.07, 0.08), k * 0.88);
    return half4(half3(clamp(color, 0.0, 1.0)), source.a);
}
