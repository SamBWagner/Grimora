#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// Holographic foil sheen for card artwork — used by both grid thumbnails and the detail pane.
//
// Applied as a SwiftUI `.colorEffect` over a black `Rectangle` that is then composited with
// `.blendMode(.plusLighter)`, so the returned colour is *added* over the artwork beneath:
// black (the resting state) contributes nothing, the rainbow wash and the moving specular
// band brighten. The per-pixel work runs on the GPU so a whole grid of foil cards can animate
// without loading the main thread.
//
// `phase` is a continuously-advancing scalar supplied by the view (shared clock or device
// gyro, already multiplied by the card's per-card speed and offset by its per-card phase), so
// neighbouring cards are never in lockstep. `angle` is a small per-card rotation of the sheen
// axis; `intensity` lets grids render more restrained than the detail pane.

static inline half3 hsv2rgb(half h, half s, half v) {
    half3 p = abs(fract(half3(h) + half3(1.0h, 2.0h / 3.0h, 1.0h / 3.0h)) * 6.0h - 3.0h);
    return v * mix(half3(1.0h), clamp(p - 1.0h, 0.0h, 1.0h), s);
}

[[ stitchable ]]
half4 grimoraFoil(float2 position,
                  half4 color,
                  float2 size,
                  float phase,
                  float angle,
                  float intensity) {
    float2 uv = position / max(size, float2(1.0));

    // Sheen axis: the diagonal (45°), nudged per-card by `angle`.
    float theta = (M_PI_F / 4.0) + angle;
    float2 dir = float2(cos(theta), sin(theta));
    // Project onto the axis and normalise to roughly 0...1 across the card.
    float d = (dot(uv, dir) - dot(float2(0.0), dir)) / (abs(cos(theta)) + abs(sin(theta)));

    float p = fract(phase);

    // Rainbow wash whose hue rotates with phase and shifts across the card.
    half hue = half(fract(d + p));
    half3 rainbow = hsv2rgb(hue, 0.85h, 1.0h);

    // Specular band: a bright stripe centred at `p` sweeping along the axis. (smoothstep
    // needs edge0 < edge1 to be well-defined, so invert rather than swap the edges.)
    half band = half(1.0 - smoothstep(0.0, 0.18, abs(d - p)));

    half i = half(intensity);
    half3 sheen = rainbow * (0.22h * i) + half3(band) * (0.45h * i);

    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}
