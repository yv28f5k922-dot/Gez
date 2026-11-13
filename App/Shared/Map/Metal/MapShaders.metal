#include <metal_stdlib>
using namespace metal;

// The map is drawn as one full-screen pass. Every screen pixel works out
// which map pixel it shows, then combines:
//   terrain texture (baked: elevation shading, biomes, rivers, sea depth)
//   + map-mode tint for the province's owner/state/religion/...
//   + borders (province faint, state medium, country strong band)
//   + animated water, selection glow, paper grain and vignette.
//
// To go 3D later: draw a terrain mesh instead of the full-screen triangle
// and pass the map coordinate from the vertex stage; shadeMap() stays.

struct MapUniforms {
    float2 viewSize;      // drawable size in pixels
    float2 offset;        // map top-left in drawable pixels
    float  zoom;          // drawable pixels per map pixel
    float  time;          // seconds, for water animation
    float2 mapSize;       // map size in map pixels
    uint   selected;      // id-map value of the selected province (0 = none)
    float  tint;          // 0..1 strength of the map-mode colour
    uint   mode;          // 0 political, 1 states, 2 terrain, 3 religion, 4 culture, 5 development
    uint   selectedSea;   // sea map value of the selected sea zone (0 = none)
};

struct ProvinceStyle {
    float4 color;   // map-mode colour (rgb), a = 0 means "no tint"
    int    owner;   // country index, -1 unowned, -2 water, -3 wasteland
    int    state;   // state index or negative
    int    pad0;
    int    pad1;
};

struct VertexOut {
    float4 position [[position]];
};

vertex VertexOut map_vertex(uint vid [[vertex_id]]) {
    // One triangle that covers the whole screen.
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VertexOut out;
    out.position = float4(p[vid], 0, 1);
    return out;
}

static uint idAt(texture2d<uint, access::read> ids, float2 m, float2 size) {
    if (m.x < 0 || m.y < 0 || m.x >= size.x || m.y >= size.y) return 0;
    return ids.read(uint2(m)).r;
}

static float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash(i), b = hash(i + float2(1, 0)), c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
    float2 u = f * f * (3 - 2 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float luminance(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

fragment float4 map_fragment(VertexOut in [[stage_in]],
                             constant MapUniforms &u [[buffer(0)]],
                             constant ProvinceStyle *styles [[buffer(1)]],
                             texture2d<uint, access::read> ids [[texture(0)]],
                             texture2d<float> terrain [[texture(1)]],
                             texture2d<uint, access::read> seas [[texture(2)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
    float2 screen = in.position.xy;
    float2 m = (screen - u.offset) / u.zoom;               // map pixel coordinate
    float2 uv = m / u.mapSize;
    float pxPerScreen = 1.0 / u.zoom;                       // map pixels per screen pixel

    // Outside the map: deep sea.
    if (any(m < 0) || any(m >= u.mapSize)) {
        return float4(0.16, 0.25, 0.33, 1);
    }

    uint id = idAt(ids, m, u.mapSize);
    float3 base = terrain.sample(linearSampler, uv).rgb;
    ProvinceStyle s = styles[id];

    float3 color;
    if (id == 0) {
        // Water: baked depth colour plus gentle moving waves and coast foam.
        float t = u.time;
        float w = noise(m * 0.08 + float2(t * 0.15, t * 0.07)) * 0.6 + noise(m * 0.21 - float2(t * 0.1, 0)) * 0.4;
        color = base * (0.92 + 0.12 * w);
        float coast = 0;
        for (int k = 0; k < 8; k++) {
            float ang = float(k) * 0.785398;
            float2 dir = float2(cos(ang), sin(ang));
            if (idAt(ids, m + dir * max(2.5 * pxPerScreen, 1.2), u.mapSize) != 0) coast = 1;
        }
        color = mix(color, float3(0.82, 0.86, 0.80), coast * 0.35);
        // Faint dotted lines between sea zones.
        uint zone = idAt(seas, m, u.mapSize);
        if (zone != 0) {
            float r = 1.2 * pxPerScreen;
            uint e = idAt(seas, m + float2(r, 0), u.mapSize), s2 = idAt(seas, m + float2(0, r), u.mapSize);
            bool edge = (e != 0 && e != zone) || (s2 != 0 && s2 != zone);
            float dots = step(0.5, fract((screen.x + screen.y) * 0.18));
            if (edge) color = mix(color, float3(0.80, 0.88, 0.92), 0.35 * dots);
            if (zone == u.selectedSea) color = mix(color, float3(0.85, 0.95, 1.0), 0.15);
        }
    } else {
        // Land: terrain with the map-mode colour laid over it.
        color = base;
        if (s.color.a > 0) {
            float lum = luminance(base);
            float3 tinted = s.color.rgb * (0.55 + 0.75 * lum);
            color = mix(base, tinted, u.tint * s.color.a);
        }
        if (s.owner == -3) {
            // Wasteland: darker, faded, faint diagonal hatching.
            color = mix(color, float3(luminance(color)), 0.5) * 0.78;
            float hatch = step(0.85, fract((m.x + m.y) * 0.12));
            color *= 1.0 - hatch * 0.12;
        }

        // Borders. Distances are in screen pixels so lines stay the same
        // width at every zoom.
        float countryEdge = 0, stateEdge = 0, provinceEdge = 0;
        float bandRadii[4] = { 1.2, 2.5, 4.5, 7.0 };
        float bandWeight[4] = { 1.0, 0.65, 0.35, 0.15 };
        for (int r = 0; r < 4; r++) {
            float rad = bandRadii[r] * pxPerScreen;
            for (int k = 0; k < 8; k++) {
                float ang = float(k) * 0.785398;
                uint other = idAt(ids, m + float2(cos(ang), sin(ang)) * rad, u.mapSize);
                if (other == id) continue;
                ProvinceStyle o = styles[other];
                if (o.owner != s.owner) {
                    countryEdge = max(countryEdge, bandWeight[r]);
                } else if (r == 0) {
                    if (o.state != s.state) stateEdge = 1; else provinceEdge = 1;
                }
            }
        }
        bool showOwners = (u.mode == 0) && s.owner >= 0;
        float3 edgeColor = float3(0.12, 0.10, 0.08);
        if (showOwners) {
            // Coloured band just inside the country edge, and the edge line
            // itself in a deep shade of the country's own colour.
            float3 band = s.color.rgb * (0.55 + 0.5 * luminance(base));
            color = mix(color, band, smoothstep(0.1, 0.7, countryEdge) * 0.5);
            edgeColor = s.color.rgb * 0.35;
        }
        color = mix(color, edgeColor, step(0.99, countryEdge) * 0.8);
        color = mix(color, color * 0.62, stateEdge * 0.7);
        float provinceAlpha = clamp((u.zoom - 0.25) * 1.0, 0.0, 0.4);
        color = mix(color, color * 0.75, provinceEdge * provinceAlpha);

        if (id == u.selected && u.selected != 0) {
            float pulse = 0.5 + 0.5 * sin(u.time * 3.0);
            color = mix(color, float3(1.0, 0.97, 0.85), 0.18 + 0.08 * pulse);
            if (provinceEdge > 0 || stateEdge > 0 || countryEdge > 0.99) color = float3(1.0, 0.95, 0.7);
        }
    }

    // Paper grain and a soft vignette tie the look together.
    float grain = hash(floor(screen)) * 0.035 - 0.0175;
    color += grain;
    float2 q = screen / u.viewSize - 0.5;
    color *= 1.0 - dot(q, q) * 0.35;
    return float4(saturate(color), 1);
}
