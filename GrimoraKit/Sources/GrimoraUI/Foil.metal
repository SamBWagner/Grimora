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

// 2D value hash → 0...1, stable per input. Scatters galaxy-foil sparkle position, size,
// brightness, twinkle phase, and colour. Matches the canvas prototype's hash exactly.
static inline float galaxyHash(float2 p) {
    float px = fract(p.x * 123.34);
    float py = fract(p.y * 456.21);
    float dv = px * (px + 45.32) + py * (py + 45.32);
    px += dv;
    py += dv;
    return fract(px * py);
}

// 1D hash → 0...1, used to scatter the neon-ink streak path points (matches the canvas prototype).
static inline float neonHash(float x) {
    return fract(sin(x * 127.1) * 43758.5453);
}

// The shared sheen axis used by several treatments: the diagonal (45°) nudged per-card by
// `angle`, with the projection normalised to roughly 0...1 across the card.
static inline float foilAxisCoordinate(float2 uv, float angle) {
    float theta = (M_PI_F / 4.0) + angle;
    float2 dir = float2(cos(theta), sin(theta));
    return dot(uv, dir) / (abs(cos(theta)) + abs(sin(theta)));
}

// Layered domain-warped sine turbulence (three octaves) — the organic warp shared by surge
// (bends bands into flickering flame tongues) and halo (marbles the radial rings). Tuned
// interactively; do not "simplify" the magic numbers, they are the look.
static inline float foilTurbulence(float x, float y, float t) {
    float n = sin(x * 3.0 + t * 0.9 + sin(y * 2.0 - t * 0.6)) * 0.55;
    n += sin(x * 6.3 - t * 1.2 + y * 1.3) * 0.30;
    n += sin(x * 12.0 + y * 5.0 + t * 0.7) * 0.15;
    return n;
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

// Etched foil: a restrained, low-chroma pewter sheen with fine engraved lines and a soft moving
// highlight. Deliberately muted — etched reads as matte metal, not rainbow.
[[ stitchable ]]
half4 grimoraFoilEtched(float2 position,
                        half4 color,
                        float2 size,
                        float phase,
                        float angle,
                        float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d = foilAxisCoordinate(uv, angle);
    float p = fract(phase);

    // Fine engraved lines + a soft, slow specular band.
    half lines = half(0.5 + 0.5 * sin((uv.x + uv.y) * 130.0));
    half band = half(1.0 - smoothstep(0.0, 0.30, abs(d - p)));

    half i = half(intensity);
    half3 silver = half3(0.74h, 0.78h, 0.84h);
    half3 sheen = silver * (0.09h * i) + silver * lines * (0.05h * i) + half3(band) * (0.30h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Surge foil: wide rainbow bands warped by layered turbulence into flickering "foil fire" — the
// bands bend into sharp, pointed flame tongues that vary in brightness. Tuned interactively in a
// canvas prototype; the constants below are the locked-in values (band density 5, flow 0.28,
// pointiness 1.0 -> exponent 4.5, surge strength 0.65, drift 0.9) — not arbitrary, don't round.
[[ stitchable ]]
half4 grimoraFoilSurge(float2 position,
                       half4 color,
                       float2 size,
                       float phase,
                       float angle,
                       float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float theta = (M_PI_F / 4.0) + angle;
    float ct = cos(theta), st = sin(theta);
    float along = uv.x * ct + uv.y * st;
    float perp = -uv.x * st + uv.y * ct;

    // Turbulent warp bends the bands; reused to flicker each tongue's brightness.
    float warp = foilTurbulence(perp, along, phase);
    float dd = along + 0.28 * warp;

    float hue = fract(dd * 5.0 + phase * 0.9);
    half3 rainbow = hsv2rgb(half(hue), 0.74h, 1.0h);

    // Sharp band ridges (pointiness): thin bright tips at each band centre.
    float bandv = 0.5 + 0.5 * cos(2.0 * M_PI_F * dd * 5.0);
    float ridge = pow(bandv, 4.5);
    float flame = 0.45 + 0.55 * (0.5 + 0.5 * sin(warp * 2.0 + phase * 0.5));

    half k = half(0.65 * intensity * flame);
    half3 sheen = rainbow * (0.26h * k) + half3(half(ridge)) * (0.13h * k);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Halo foil: a soft, saturated rainbow that blooms radially from the card and is heavily marbled
// by turbulence into an oil-on-water / aurora flow — not crisp concentric rings. Tuned
// interactively; locked values: ring spacing 1.0, marble 0.22, softness 0.05 -> exponent 2.88,
// strength 0.60, drift 0.15. Centre sits over the art (0.5, 0.42).
[[ stitchable ]]
half4 grimoraFoilHalo(float2 position,
                      half4 color,
                      float2 size,
                      float phase,
                      float angle,
                      float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float dx = uv.x - 0.5;
    float dy = uv.y - 0.42;
    float r = length(float2(dx, dy)) * 1.7;
    float ang = atan2(dy, dx) + angle;

    // Marble the radius so the rings flow like aurora rather than forming clean circles.
    float warp = foilTurbulence(ang * 1.5, r * 2.5, phase * 0.5) * 0.22;
    float rrad = r + warp;

    float hue = fract(rrad - phase * 0.15);
    half3 rainbow = hsv2rgb(half(hue), 0.76h, 1.0h);

    float ringv = 0.5 + 0.5 * cos(2.0 * M_PI_F * rrad);
    float ridge = pow(ringv, 2.88);
    float bloom = exp(-r * r * 2.5);

    half k = half(0.60 * intensity);
    half3 sheen = rainbow * (0.30h * k) + half3(half(ridge)) * (0.09h * k) + half3(half(bloom)) * (0.10h * k);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Galaxy foil: a dense field of round, flatly-lit sparkles spanning a wide size range (cubic
// spread — mostly fine dust, a rare few big bright glints) that slowly drift and twinkle, with a
// fraction catching an iridescent colour. Each pixel samples its 3x3 cell neighbourhood so large
// drifting sparkles never clip at cell edges. Tuned interactively; locked values: density 18,
// base size 0.13, size variation 0.70, movement 0.35, iridescence 0.45, twinkle 0.60, strength
// 0.40. A per-card seed (from `angle`) shifts the field so neighbours never share a layout.
[[ stitchable ]]
half4 grimoraFoilGalaxy(float2 position,
                        half4 color,
                        float2 size,
                        float phase,
                        float angle,
                        float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float TAU = 6.2831853;
    float2 g = float2(uv.x * 18.0, uv.y * 18.0 * 1.4);
    float2 cell = floor(g);
    float2 f = g - cell;
    float2 seed = float2(angle * 41.0, -angle * 23.0);

    half3 accum = half3(0.0h);
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            float2 base = cell + float2(float(ox), float(oy)) + seed;
            float r3 = galaxyHash(base + float2(3.3, 9.1));
            if (r3 >= 0.62) { continue; }
            float r1 = galaxyHash(base);
            float r2 = galaxyHash(base + float2(13.1, 7.7));
            float r4 = galaxyHash(base + float2(21.7, 4.2));

            float sx = 0.2 + 0.6 * r1 + 0.35 * sin(phase * (0.5 + 0.8 * r4) + r1 * TAU);
            float sy = 0.2 + 0.6 * r2 + 0.35 * cos(phase * (0.4 + 0.8 * r2) + r3 * TAU);
            float2 starPos = float2(float(ox), float(oy)) + float2(sx, sy);
            float dist = length(f - starPos);

            float spread = 0.18 + 3.4 * r4 * r4 * r4;
            float starR = 0.13 * (1.0 + 0.70 * (spread - 1.0));
            float discR = max(0.02, starR * 1.5);
            float disc = 1.0 - smoothstep(0.86 * discR, discR, dist);
            if (disc <= 0.0) { continue; }

            float bright = 0.35 + 0.65 * min(1.0, spread * 0.5);
            float tw = 0.25 + 0.75 * (0.5 + 0.5 * sin(phase * 3.6 + r1 * TAU));
            float a = min(1.0, bright * tw * 0.40) * disc;

            half3 col = half3(1.0h);
            if (r1 < 0.45) {
                float hue = fract(r2 + phase * 0.05);
                col = half3(0.45h) + 0.55h * hsv2rgb(half(hue), 0.6h, 1.0h);
            }
            accum += col * half(a);
        }
    }

    half3 sheen = accum * half(intensity);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Oil slick (raised) foil: a near-black card with thin-film iridescence that pools in soft,
// drifting reflective patches — petrol-on-water. Most of the card stays dark; the rainbow only
// blooms where the turbulent sheen mask is high. Tuned interactively; locked values: band scale
// 1.5, flow 0.16, coverage 0.10 (mask threshold ~0.90), strength 0.40, drift 0.20. `angle` seeds
// per-card variation so neighbours don't share a pattern.
[[ stitchable ]]
half4 grimoraFoilOilSlick(float2 position,
                          half4 color,
                          float2 size,
                          float phase,
                          float angle,
                          float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float ct = cos(M_PI_F / 4.0), st = sin(M_PI_F / 4.0);
    float along = uv.x * ct + uv.y * st;
    float perp = -uv.x * st + uv.y * ct;

    float warp = foilTurbulence(perp + angle * 3.0, along, phase);
    float coord = along + 0.16 * warp;
    float hue = fract(coord * 1.5 + phase * 0.20 + angle);
    half3 rainbow = hsv2rgb(half(hue), 0.85h, 1.0h);

    // Reflective sheen mask — only its high patches catch the iridescence; the rest stays dark.
    float m = 0.5 + 0.5 * foilTurbulence(perp * 1.3 + 3.7 + angle * 5.0, along * 1.1 - 2.0, phase * 0.5);
    float mask = smoothstep(0.68, 1.12, m);

    float amt = (0.10 + 0.72 * mask) * 0.40 * intensity;
    half3 sheen = rainbow * half(amt);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Confetti foil: a dense scatter of small, vivid, rotated rectangular flecks of varied shape that
// drift and slowly spin — every piece its own saturated colour. Each pixel tests its 3x3 cell
// neighbourhood against each cell's rotated-rect fleck (so pieces never clip at cell edges).
// Tuned interactively; locked values: density 48, fleck size 0.24, coverage 0.70, movement 0.40,
// shimmer 0.75, strength 0.80. `angle` seeds the per-card layout.
[[ stitchable ]]
half4 grimoraFoilConfetti(float2 position,
                          half4 color,
                          float2 size,
                          float phase,
                          float angle,
                          float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float TAU = 6.2831853;
    float dens = 48.0;
    float fsize = 0.24;
    float mv = 0.40;
    float2 g = float2(uv.x * dens, uv.y * dens * 1.4);
    float2 cell = floor(g);
    float2 f = g - cell;
    float2 seed = float2(angle * 41.0, -angle * 23.0);

    half3 accum = half3(0.0h);
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            float2 b = cell + float2(float(ox), float(oy)) + seed;
            float r3 = galaxyHash(b + float2(3.3, 9.1));
            if (r3 >= 0.70) { continue; }
            float r1 = galaxyHash(b);
            float r2 = galaxyHash(b + float2(13.1, 7.7));
            float r4 = galaxyHash(b + float2(21.7, 4.2));
            float r5 = galaxyHash(b + float2(5.9, 2.3));

            float sx = 0.2 + 0.6 * r1 + mv * sin(phase * (0.4 + 0.7 * r4) + r1 * TAU);
            float sy = 0.2 + 0.6 * r2 + mv * cos(phase * (0.4 + 0.7 * r2) + r3 * TAU);
            float2 delta = f - (float2(float(ox), float(oy)) + float2(sx, sy));

            float ang = r2 * TAU + phase * mv * 1.8 * (r4 - 0.5);
            float ca = cos(ang), sa = sin(ang);
            float2 local = float2(ca * delta.x + sa * delta.y, -sa * delta.x + ca * delta.y);

            float hw = fsize * (0.45 + r4) * 0.5;
            float hh = fsize * (0.45 + r5) * 0.5;
            float aa = 0.02;
            float cov = (1.0 - smoothstep(hw - aa, hw + aa, abs(local.x))) *
                        (1.0 - smoothstep(hh - aa, hh + aa, abs(local.y)));
            if (cov <= 0.0) { continue; }

            float tw = 0.55 + 0.45 * (0.5 + 0.5 * sin(phase * 3.75 + r1 * TAU));
            float a = min(1.0, tw * 0.80) * cov;
            float hue = fract(r2 * 1.7 + r4);
            accum += hsv2rgb(half(hue), 0.85h, 1.0h) * half(a);
        }
    }

    half3 sheen = accum * half(intensity);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Ripple foil: scattered, overlapping concentric rainbow ring-bursts (like raindrop ripples)
// expanding outward from many hashed centres, sampled over a 3x3 neighbourhood. Tuned
// interactively; locked values: ring spacing 2.5, ripple count 2.0, sharpness 1.0 -> exponent 6,
// strength 0.35, drift 0.10. `angle` seeds the per-card ripple centres.
[[ stitchable ]]
half4 grimoraFoilRipple(float2 position,
                        half4 color,
                        float2 size,
                        float phase,
                        float angle,
                        float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float TAU = 6.2831853;
    float dens = 2.0;
    float freq = 2.5;
    float drift = phase * 0.10;
    float2 g = float2(uv.x * dens, uv.y * dens * 1.4);
    float2 cell = floor(g);
    float2 f = g - cell;
    float2 seed = float2(angle * 41.0, -angle * 23.0);

    half3 accum = half3(0.0h);
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            float2 b = cell + float2(float(ox), float(oy)) + seed;
            float r1 = galaxyHash(b);
            float r2 = galaxyHash(b + float2(13.1, 7.7));
            float r3 = galaxyHash(b + float2(3.3, 9.1));
            float r4 = galaxyHash(b + float2(21.7, 4.2));
            float dx = f.x - (float(ox) + 0.15 + 0.7 * r1);
            float dy = f.y - (float(oy) + 0.15 + 0.7 * r2);
            float dist = length(float2(dx, dy));
            float maxR = 0.5 + 0.7 * r3;
            if (dist >= maxR) { continue; }
            float rp = dist * freq - drift + r4 * 3.0;
            float ridge = pow(0.5 + 0.5 * cos(TAU * rp), 6.0);
            float hue = fract(dist * freq * 0.5 - drift + r4);
            float fn = max(0.0, 1.0 - dist / maxR);
            float fall = fn * fn * (3.0 - 2.0 * fn);
            float w = (0.16 + ridge * 0.5) * fall;
            accum += hsv2rgb(half(hue), 0.78h, 1.0h) * half(w);
        }
    }

    half3 sheen = accum * half(0.35 * intensity);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Fracture foil: separated, jagged glass shards (domain-warped Voronoi) that drift and morph on
// their own orbits, each shard mostly metallic-silver with a fraction tinted and an internal
// transparent->colour gradient running in a per-shard direction. Denser at the card border,
// scattered in the centre. Tuned interactively; locked values: shard density 18, jaggedness 0.60
// (warp 0.078), facet colour 0.30, edge bias 0.70, strength 0.65, drift 0.50. `angle` seeds layout.
[[ stitchable ]]
half4 grimoraFoilFracture(float2 position,
                          half4 color,
                          float2 size,
                          float phase,
                          float angle,
                          float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float TAU = 6.2831853;
    float dens = 18.0;
    float ja = 0.078;
    float mph = phase * 1.4;
    float amp = 0.12;
    float drift = phase * 0.5;
    float gx = uv.x * dens, gy = uv.y * dens * 1.4;
    float2 cellf = floor(float2(gx, gy));
    float fx = gx - cellf.x, fy = gy - cellf.y;
    float2 seed = float2(angle * 41.0, -angle * 23.0);

    float wx = ja * (sin(gx * 4.1 + gy * 2.3 + phase * 0.6) + 0.6 * sin(gy * 8.0 - phase * 0.4));
    float wy = ja * (cos(gy * 4.3 - gx * 2.1 + phase * 0.6) + 0.6 * sin(gx * 7.0 + phase * 0.5));
    float fxw = fx + wx, fyw = fy + wy;

    float F1 = 9.0, id1 = 0.0, pcx = 0.0, pcy = 0.0;
    for (int oy = -1; oy <= 1; oy++) {
        for (int ox = -1; ox <= 1; ox++) {
            float2 b = cellf + float2(float(ox), float(oy)) + seed;
            float r1 = galaxyHash(b);
            float r2 = galaxyHash(b + float2(19.3, 11.1));
            float r3 = galaxyHash(b + float2(7.7, 3.3));
            float ptx = float(ox) + 0.15 + 0.7 * r1 + amp * sin(mph + r1 * TAU);
            float pty = float(oy) + 0.15 + 0.7 * r2 + amp * cos(mph * 0.9 + r2 * TAU);
            float dx = fxw - ptx, dy = fyw - pty;
            float dd = sqrt(dx * dx + dy * dy);
            if (dd < F1) { F1 = dd; id1 = r3; pcx = ptx; pcy = pty; }
        }
    }

    float bH = fract(id1 * 91.7);
    float colH = fract(id1 * 57.3 + 0.31);
    float visH = fract(id1 * 13.7 + 0.66);
    float gH = fract(id1 * 39.1 + 0.5);
    float aH = fract(id1 * 71.3 + 0.2);

    float gth = gH * TAU;
    float proj = (fxw - pcx) * cos(gth) + (fyw - pcy) * sin(gth);
    float tg = clamp(0.5 + proj / 0.85, 0.0, 1.0);
    float gradAlpha = smoothstep(0.05 + 0.5 * aH, 0.05 + 0.5 * aH + 0.28 + 0.5 * gH, tg);
    float sep = 1.0 - smoothstep(0.42, 0.82, F1);
    float shardAlpha = gradAlpha * sep;

    float sat = (colH < (0.12 + 0.45 * 0.30)) ? (0.20 + 0.40 * 0.30) : 0.07;
    float bright = 0.4 + 0.6 * bH;
    half3 c = hsv2rgb(half(fract(id1 * 3.0 + drift * 0.4)), half(sat), 1.0h);

    float ex = abs(uv.x - 0.5) * 2.0, ey = abs(uv.y - 0.5) * 2.0;
    float ef = pow(max(ex, ey), 1.3);
    float centerScatter = (visH < 0.5) ? 1.0 : 0.22;
    float ew = min(1.0, ef + (1.0 - ef) * centerScatter);
    float vis = 0.30 + 0.70 * ew;

    float amt = bright * shardAlpha * vis * 0.65 * intensity;
    half3 sheen = c * half(amt);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Mana foil base: a light, pale vertical iridescent gradient with a slow horizontal shine sweep.
// The defining stamped mana symbols are drawn as a separate SwiftUI layer (ManaFoilStampOverlay)
// over this, since they need the app's SF Symbol glyphs. Locked: foil lightness 0.30, drift 0.30.
[[ stitchable ]]
half4 grimoraFoilManaGradient(float2 position,
                              half4 color,
                              float2 size,
                              float phase,
                              float angle,
                              float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float h = fract(uv.y * 0.7 + phase * 0.30 + angle);
    half3 grad = hsv2rgb(half(h), 0.30h, 1.0h);
    float bx = fract(phase * 0.12 + angle * 0.5);
    float band = 1.0 - smoothstep(0.0, 0.18, abs(uv.x - bx));
    half3 sheen = grad * 0.14h + half3(half(band)) * 0.20h;
    return half4(clamp(sheen, 0.0h, 1.0h) * half(intensity), 1.0h);
}

// Neon ink: glowing neon light-streaks darting along bent paths over the (dark) card — an
// abstraction of the UV line-art look (the real linework can't be mapped). Six streaks, each a
// 3-segment bent polyline with a faint tube glow plus a bright head that shoots along it.
// Additive. Tuned: hue 0.45, 6 lines, glow 0.6, speed 0.4, multicolor 0.30. `angle` seeds paths.
[[ stitchable ]]
half4 grimoraFoilNeonInk(float2 position,
                         half4 color,
                         float2 size,
                         float phase,
                         float angle,
                         float intensity) {
    float aspect = size.y / max(size.x, 1.0);
    float2 p = float2(position.x / max(size.x, 1.0), position.y / max(size.y, 1.0) * aspect);
    float core = 0.008;
    float glowR = 0.05;
    half3 accum = half3(0.0h);
    for (int s = 0; s < 11; s++) {
        float fs = float(s) + angle * 3.0;
        float2 pts[4];
        for (int k = 0; k < 4; k++) {
            float fk = float(k);
            // Points spread beyond [0,1] so streaks run off all four edges, not just the centre.
            float bx = -0.25 + 1.5 * neonHash(fs * 7.3 + fk * 3.1) + 0.06 * sin(phase * 0.4 + fs + fk * 1.3);
            float by = -0.25 + 1.5 * neonHash(fs * 5.7 + fk * 4.7) + 0.06 * cos(phase * 0.35 + fs * 1.3 + fk);
            pts[k] = float2(bx, by * aspect);
        }
        float total = 0.0;
        float segL[3];
        for (int i = 0; i < 3; i++) { segL[i] = length(pts[i + 1] - pts[i]); total += segL[i]; }
        float best = 1e9, bestArc = 0.0, cum = 0.0;
        for (int i = 0; i < 3; i++) {
            float2 a = pts[i], b = pts[i + 1];
            float2 ab = b - a, ap = p - a;
            float h = clamp(dot(ap, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
            float dd = length(ap - ab * h);
            if (dd < best) { best = dd; bestArc = cum + h * segL[i]; }
            cum += segL[i];
        }
        float u = fract(phase * 0.45 * (0.5 + 0.7 * neonHash(fs * 3.3)) + neonHash(fs * 2.1));
        float headLen = total * 0.22;
        float headMask = 1.0 - smoothstep(0.0, headLen, abs(bestArc - u * total));
        float lineAmt = exp(-best / glowR) * 0.22 + exp(-best / core) * (0.25 + headMask);
        float hue = fract(0.65 + (neonHash(fs * 9.1) - 0.5) * 0.56);
        accum += hsv2rgb(half(hue), 0.85h, 1.0h) * half(lineAmt);
    }
    half3 sheen = min(accum, half3(1.8h)) * half(0.8 * intensity);
    return half4(min(sheen, half3(1.0h)), 1.0h);
}

// Step-and-compleat foil: an oily dark-green iridescent sheen pooling under a tiled, embossed
// Phyrexian "compleat" glyph (a circle ring with a vertical bar through it), drawn as an SDF so
// no texture is needed. Locked: pattern scale 5, symbol size 0.65, symbol strength 0.25, oil
// sheen 0.15, drift 0.0. `angle` seeds the oil. Additive over the (dark) card.
[[ stitchable ]]
half4 grimoraFoilStepCompleat(float2 position,
                              half4 color,
                              float2 size,
                              float phase,
                              float angle,
                              float intensity) {
    float aspect = size.y / max(size.x, 1.0);
    float2 uv = position / max(size, float2(1.0));
    float ct = cos(M_PI_F / 4.0), st = sin(M_PI_F / 4.0);
    float along = uv.x * ct + uv.y * st, perp = -uv.x * st + uv.y * ct;

    // Oily iridescent base (green→purple), pooled by a turbulent mask.
    float warp = foilTurbulence(perp, along, phase);
    float hue = 0.30 + 0.45 * fract((along + 0.16 * warp) * 1.8 + angle);
    half3 oilCol = hsv2rgb(half(hue), 0.72h, 1.0h);
    float m = 0.5 + 0.5 * foilTurbulence(perp * 1.3 + 3.7 + angle * 4.0, along * 1.1 - 2.0, phase * 0.5);
    float oilAmt = (0.08 + 0.5 * smoothstep(0.4, 0.85, m)) * 0.15;

    // Tiled circular-Phi glyph (offset rows), drawn as a ring + vertical bar SDF.
    float scale = 5.0;
    float gy = uv.y * aspect * scale;
    float row = floor(gy);
    float gx = uv.x * scale + (fmod(row, 2.0) < 1.0 ? 0.0 : 0.5);
    float2 f = float2(gx - floor(gx), gy - row);
    float2 ls = (f - 0.5) / 0.325;
    float ring = smoothstep(0.10, 0.02, abs(length(ls) - 0.42));
    float bar = smoothstep(0.10, 0.04, abs(ls.x)) * smoothstep(0.82, 0.74, abs(ls.y));
    float glyph = clamp(max(ring, bar), 0.0, 1.0);
    half3 symCol = half3(0.62h, 0.86h, 0.66h);

    half3 sheen = oilCol * half(oilAmt) + symCol * half(glyph * 0.25);
    return half4(clamp(sheen, 0.0h, 1.0h) * half(intensity), 1.0h);
}

// --- Tint & texture variants (batched) ---------------------------------------------------------

// Rainbow foil: a full, saturated holographic rainbow sweep — the standard sheen dialled up.
[[ stitchable ]]
half4 grimoraFoilRainbow(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d = foilAxisCoordinate(uv, angle);
    float p = fract(phase);
    half3 rainbow = hsv2rgb(half(fract(d * 2.0 + p)), 0.95h, 1.0h);
    half spec = half(1.0 - smoothstep(0.0, 0.20, abs(d - p)));
    half i = half(intensity);
    half3 sheen = rainbow * (0.30h * i) + half3(spec) * (0.40h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Double rainbow: two overlapping rainbow gradients on different axes — extra chromatic and busy.
[[ stitchable ]]
half4 grimoraFoilDoubleRainbow(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d1 = foilAxisCoordinate(uv, angle);
    float d2 = foilAxisCoordinate(uv, angle + 1.2);
    float p = fract(phase);
    half3 r1 = hsv2rgb(half(fract(d1 * 2.0 + p)), 0.95h, 1.0h);
    half3 r2 = hsv2rgb(half(fract(d2 * 2.5 - p * 1.3 + 0.33)), 0.95h, 1.0h);
    half spec = half(1.0 - smoothstep(0.0, 0.18, abs(d1 - p)));
    half i = half(intensity);
    half3 sheen = r1 * (0.24h * i) + r2 * (0.24h * i) + half3(spec) * (0.35h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Silver foil: cool brushed-silver metallic — low chroma, fine brush lines, bright specular sweep.
[[ stitchable ]]
half4 grimoraFoilSilver(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d = foilAxisCoordinate(uv, angle);
    float p = fract(phase);
    half lines = half(0.5 + 0.5 * sin((uv.x + uv.y) * 160.0));
    half band = half(1.0 - smoothstep(0.0, 0.24, abs(d - p)));
    half3 silver = half3(0.80h, 0.84h, 0.90h);
    half i = half(intensity);
    half3 sheen = silver * (0.14h * i) + silver * lines * (0.06h * i) + half3(band) * (0.40h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Glossy: a soft, broad, even gloss sweep with barely any colour — the subtlest treatment.
[[ stitchable ]]
half4 grimoraFoilGlossy(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d = foilAxisCoordinate(uv, angle);
    float p = fract(phase);
    half band = half(1.0 - smoothstep(0.0, 0.5, abs(d - p)));
    half3 tint = hsv2rgb(half(fract(d * 0.5 + p)), 0.25h, 1.0h);
    half i = half(intensity);
    half3 sheen = tint * (0.08h * i) + half3(band) * (0.30h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Gilded: warm gold metallic — gold-hued sheen with a fine gilt texture and a warm highlight band.
[[ stitchable ]]
half4 grimoraFoilGilded(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d = foilAxisCoordinate(uv, angle);
    float p = fract(phase);
    half band = half(1.0 - smoothstep(0.0, 0.22, abs(d - p)));
    half3 gold = hsv2rgb(half(0.11 + 0.04 * fract(d + p)), 0.75h, 1.0h);
    half lines = half(0.5 + 0.5 * sin((uv.x - uv.y) * 90.0));
    half i = half(intensity);
    half3 sheen = gold * (0.22h * i) + gold * lines * (0.05h * i) + half3(0.95h, 0.85h, 0.60h) * band * (0.35h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Textured: a dense cross-hatch of fine facets catching a rainbow — a faceted, sparkly sheen.
[[ stitchable ]]
half4 grimoraFoilTextured(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d = foilAxisCoordinate(uv, angle);
    float p = fract(phase);
    half h1 = half(0.5 + 0.5 * sin((uv.x + uv.y) * 120.0));
    half h2 = half(0.5 + 0.5 * sin((uv.x - uv.y) * 120.0));
    half facet = h1 * h2;
    half3 rainbow = hsv2rgb(half(fract(d * 3.0 + p)), 0.80h, 1.0h);
    half i = half(intensity);
    half3 sheen = rainbow * (0.18h * i) + rainbow * facet * (0.40h * i) + half3(facet) * (0.12h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Embossed: a low-chroma raised-relief sheen — a turbulent height field lit on one slope.
[[ stitchable ]]
half4 grimoraFoilEmbossed(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float hgt = foilTurbulence(uv.x * 6.0, uv.y * 6.0, phase * 0.2);
    float slope = foilTurbulence(uv.x * 6.0 + 0.05, uv.y * 6.0, phase * 0.2) - hgt;
    half band = half(clamp(0.5 + slope * 6.0, 0.0, 1.0));
    half3 tone = half3(0.82h, 0.84h, 0.86h);
    half3 tint = hsv2rgb(half(fract(hgt * 0.2 + phase * 0.1)), 0.20h, 1.0h);
    half i = half(intensity);
    half3 sheen = tone * band * (0.32h * i) + tint * (0.06h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}

// Raised: a subtle glossy sheen with a coarse raised-bump highlight — gentler than textured.
[[ stitchable ]]
half4 grimoraFoilRaised(float2 position, half4 color, float2 size, float phase, float angle, float intensity) {
    float2 uv = position / max(size, float2(1.0));
    float d = foilAxisCoordinate(uv, angle);
    float p = fract(phase);
    half band = half(1.0 - smoothstep(0.0, 0.35, abs(d - p)));
    half bumps = half(0.5 + 0.5 * sin(uv.x * 40.0) * sin(uv.y * 40.0));
    half3 tint = hsv2rgb(half(fract(d * 0.8 + p)), 0.30h, 1.0h);
    half i = half(intensity);
    half3 sheen = tint * (0.10h * i) + half3(band) * (0.30h * i) + half3(bumps) * (0.06h * i);
    return half4(clamp(sheen, 0.0h, 1.0h), 1.0h);
}
