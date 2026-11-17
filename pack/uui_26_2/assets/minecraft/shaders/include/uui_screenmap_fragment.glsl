#define UUI_SMAP_FRAME_WIDTH 0.1
#define UUI_SMAP_ARROW_ROUND 0.012
#define UUI_SMAP_ARROW_NOTCH_ROUND 0.02
#define UUI_SMAP_ARROW_HEIGHT_UNITS 0.186

float uui_smap_triangle(vec2 p, vec2 p0, vec2 p1, vec2 p2) {
    vec2 e0 = p1 - p0;
    vec2 e1 = p2 - p1;
    vec2 e2 = p0 - p2;
    vec2 v0 = p - p0;
    vec2 v1 = p - p1;
    vec2 v2 = p - p2;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

float uui_smap_smooth_min(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float uui_smap_arrow(vec2 p) {
    vec2 tip = vec2(0.0, 0.074);
    vec2 left = vec2(-0.05, -0.054);
    vec2 right = vec2(0.05, -0.054);
    vec2 notch = vec2(0.0, -0.022);
    float leftHalf = uui_smap_triangle(p, tip, left, notch);
    float rightHalf = uui_smap_triangle(p, tip, notch, right);
    float blend = UUI_SMAP_ARROW_NOTCH_ROUND * (1.0 - smoothstep(-0.03, 0.0, p.y));
    float body = blend > 1.0e-4 ? uui_smap_smooth_min(leftHalf, rightHalf, blend) : min(leftHalf, rightHalf);
    return body - UUI_SMAP_ARROW_ROUND;
}

float uui_smap_box(vec2 p, vec2 extent, float radius) {
    vec2 q = abs(p) - extent + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

float uui_smap_coverage(float distanceToEdge, float pixel) {
    return 1.0 - smoothstep(-pixel * 0.5, pixel * 0.5, distanceToEdge);
}

vec4 uui_smap_unknown(vec2 p) {
    if (uuiMapMarker.w < -1.5) {
        return vec4(0.0);
    }
    if (uuiMapMarker.w >= 0.0) {
        int rgb24 = int(uuiMapMarker.w + 0.5);
        return vec4(vec3(float((rgb24 >> 16) & 255), float((rgb24 >> 8) & 255), float(rgb24 & 255)) / 255.0, 1.0);
    }
    float stripe = step(0.5, fract((p.x + p.y) * 9.0));
    return vec4(mix(vec3(0.075, 0.080, 0.095), vec3(0.095, 0.100, 0.118), stripe), 1.0);
}

vec4 uui_smap_texel(sampler2D source, ivec2 cell, vec2 p) {
    if (cell.x < 0 || cell.y < 2 || cell.x >= 128 || cell.y >= 128) {
        return uui_smap_unknown(p);
    }
    vec4 fetched = texelFetch(source, cell, 0);
    return fetched.a < 0.5 ? uui_smap_unknown(p) : vec4(fetched.rgb, 1.0);
}

vec4 uui_smap_sample(sampler2D source, vec2 texel, float texelsPerPixel, vec2 p) {
    vec2 shifted = texel - 0.5;
    vec2 base = floor(shifted);
    vec2 f = shifted - base;
    vec2 w = clamp((f - 0.5) / max(texelsPerPixel, 1.0e-4) + 0.5, 0.0, 1.0);
    ivec2 cell = ivec2(base);
    vec4 c00 = uui_smap_texel(source, cell, p);
    vec4 c10 = uui_smap_texel(source, cell + ivec2(1, 0), p);
    vec4 c01 = uui_smap_texel(source, cell + ivec2(0, 1), p);
    vec4 c11 = uui_smap_texel(source, cell + ivec2(1, 1), p);
    c00.rgb *= c00.a;
    c10.rgb *= c10.a;
    c01.rgb *= c01.a;
    c11.rgb *= c11.a;
    vec4 mixed = mix(mix(c00, c10, w.x), mix(c01, c11, w.x), w.y);
    return vec4(mixed.rgb / max(mixed.a, 1.0e-4), mixed.a);
}

int uui_smap_symbol(sampler2D source, ivec2 texel) {
    ivec3 c = ivec3(texelFetch(source, texel, 0).rgb * 255.0 + 0.5);
    return (c.r + c.g + 9 * c.b) & 63;
}

vec3 uui_smap_rgb555(uint value) {
    uvec3 c = uvec3((value >> 10u) & 31u, (value >> 5u) & 31u, value & 31u);
    return vec3((c << 3u) | (c >> 2u)) / 255.0;
}

struct UuiMediaBlock {
    int symbols[16];
    vec3 colors[4];
    bool gradient;
    bool alpha;
};

UuiMediaBlock uui_smap_load(sampler2D source, ivec2 origin) {
    UuiMediaBlock block;
    for (int i = 0; i < 16; i++) {
        block.symbols[i] = uui_smap_symbol(source, origin + ivec2(i & 3, i >> 2));
    }
    block.gradient = (block.symbols[0] & 32) == 0;
    block.alpha = false;
    if (block.gradient) {
        uint word = 0u;
        for (int i = 0; i < 16; i++) {
            word = (word << 2u) | uint((block.symbols[i] >> 4) & 3);
        }
        block.colors[0] = uui_smap_rgb555((word >> 15u) & 32767u);
        block.colors[1] = uui_smap_rgb555(word & 32767u);
        block.colors[2] = block.colors[0];
        block.colors[3] = block.colors[1];
        return block;
    }
    uint upper = 0u;
    uint lower = 0u;
    for (int i = 0; i < 8; i++) {
        upper = (upper << 4u) | uint((block.symbols[i] >> 2) & 15);
        lower = (lower << 4u) | uint((block.symbols[i + 8] >> 2) & 15);
    }
    block.alpha = ((upper >> 30u) & 1u) == 1u;
    block.colors[0] = uui_smap_rgb555((upper >> 13u) & 32767u);
    block.colors[1] = uui_smap_rgb555(((upper & 8191u) << 2u) | (lower >> 30u));
    block.colors[2] = uui_smap_rgb555((lower >> 15u) & 32767u);
    block.colors[3] = uui_smap_rgb555(lower & 32767u);
    return block;
}

vec4 uui_smap_pick(UuiMediaBlock block, ivec2 texel) {
    int own = (texel.y & 3) * 4 + (texel.x & 3);
    if (block.gradient) {
        return vec4(mix(block.colors[0], block.colors[1], float(block.symbols[own] & 15) / 15.0), 1.0);
    }
    int slot = block.symbols[own] & 3;
    if (slot == 3 && block.alpha) {
        return vec4(0.0);
    }
    return vec4(block.colors[slot], 1.0);
}

ivec2 uui_smap_media_texel(vec2 spot, vec2 content, vec2 origin) {
    ivec2 texel = ivec2(clamp(spot, vec2(0.0), content - 1.0) - origin) + ivec2(0, 4);
    return clamp(texel, ivec2(0, 4), ivec2(127));
}

vec4 uui_smap_media(sampler2D source, vec2 spot, vec2 content, vec2 origin, bool filtered) {
    if (!filtered) {
        ivec2 texel = uui_smap_media_texel(floor(spot), content, origin);
        return uui_smap_pick(uui_smap_load(source, texel - (texel & ivec2(3))), texel);
    }
    vec2 base = floor(spot - 0.5);
    vec2 f = spot - 0.5 - base;
    ivec2 lowTexel = uui_smap_media_texel(base, content, origin);
    ivec2 highTexel = uui_smap_media_texel(base + 1.0, content, origin);
    ivec2 lowBlock = lowTexel - (lowTexel & ivec2(3));
    ivec2 highBlock = highTexel - (highTexel & ivec2(3));
    UuiMediaBlock first = uui_smap_load(source, lowBlock);
    UuiMediaBlock across = first;
    UuiMediaBlock below = first;
    UuiMediaBlock diagonal = first;
    if (highBlock.x != lowBlock.x) {
        across = uui_smap_load(source, ivec2(highBlock.x, lowBlock.y));
    }
    if (highBlock.y != lowBlock.y) {
        below = uui_smap_load(source, ivec2(lowBlock.x, highBlock.y));
        diagonal = below;
        if (highBlock.x != lowBlock.x) {
            diagonal = uui_smap_load(source, highBlock);
        }
    } else {
        diagonal = across;
    }
    vec4 c00 = uui_smap_pick(first, lowTexel);
    vec4 c10 = uui_smap_pick(across, ivec2(highTexel.x, lowTexel.y));
    vec4 c01 = uui_smap_pick(below, ivec2(lowTexel.x, highTexel.y));
    vec4 c11 = uui_smap_pick(diagonal, highTexel);
    c00.rgb *= c00.a;
    c10.rgb *= c10.a;
    c01.rgb *= c01.a;
    c11.rgb *= c11.a;
    vec4 mixed = mix(mix(c00, c10, f.x), mix(c01, c11, f.x), f.y);
    return vec4(mixed.rgb / max(mixed.a, 1.0e-4), mixed.a);
}

vec3 uui_smap_frame(float t, float lit, float aa) {
    vec3 dark = vec3(0.035, 0.037, 0.045);
    vec3 base = vec3(0.235, 0.245, 0.285) * (0.78 + 0.42 * (lit * 0.5 + 0.5));
    float groove = 1.0 - 0.18 * (smoothstep(0.45 - aa, 0.45 + aa, t) - smoothstep(0.55 - aa, 0.55 + aa, t));
    float body = smoothstep(0.14 - aa, 0.14 + aa, t) * (1.0 - smoothstep(0.86 - aa, 0.86 + aa, t));
    return mix(dark, base * groove, body);
}

bool uui_smap_fragment(sampler2D source, out vec4 result) {
    result = vec4(0.0);
    if (uuiMapState.x < 0.5) {
        return false;
    }

    int flags = int(uuiMapState.z + 0.5);
    bool roundShape = (flags & 2) != 0;
    bool framed = (flags & 16) == 0;
    vec2 extent = max(uuiMapShape.xy, vec2(1.0));
    float pixel = 1.0 / max(uuiMapShape.w, 1.0);
    vec2 p = uuiMapUv;
    float border = roundShape ? length(p) - 1.0 : uui_smap_box(p, extent, clamp(uuiMapShape.z, 0.0, 1.0));
    float coverage = 1.0 - smoothstep(-pixel, 0.0, border);
    if (coverage <= 0.001) {
        discard;
    }

    if ((flags & 64) != 0) {
        vec2 content = max(uuiMapCenter.zw, vec2(1.0));
        vec2 spot = vec2((p.x / extent.x + 1.0) * 0.5 * content.x, (1.0 - p.y / extent.y) * 0.5 * content.y);
        vec4 decoded = uui_smap_media(source, spot, content, uuiMapCenter.xy, (flags & 128) != 0);
        if (decoded.a <= 0.001) {
            discard;
        }
        float mediaOpacity = clamp(coverage * uuiMapPaintB.a * decoded.a, 0.0, 1.0);
        result = vec4(decoded.rgb, 1.0 - sqrt(max(1.0 - mediaOpacity, 0.0)));
        return true;
    }

    vec2 heading = uuiMapCenter.zw;
    vec2 right = vec2(-heading.y, heading.x);
    float frameWidth = framed ? UUI_SMAP_FRAME_WIDTH : 0.0;
    float inner = 1.0 - frameWidth;

    vec2 offset = p / inner * uuiMapState.y;
    vec2 texel = uuiMapCenter.xy + offset.x * right + offset.y * heading;
    vec4 painted = uui_smap_sample(source, texel, uuiMapState.y / inner * pixel, p);
    if (painted.a <= 0.001) {
        discard;
    }
    vec3 color = painted.rgb;

    if (framed) {
        color *= mix(1.0, 0.7, smoothstep(-0.34, -frameWidth, border));
        float lit = roundShape ? p.y / max(length(p), 1.0e-4) : p.y / extent.y;
        float t = clamp((border + frameWidth) / frameWidth, 0.0, 1.0);
        vec3 frame = uui_smap_frame(t, lit, pixel / frameWidth);
        color = mix(color, frame, smoothstep(-frameWidth - pixel * 0.5, -frameWidth + pixel * 0.5, border));
    }

    if ((flags & 4) != 0) {
        float scale = max(uuiMapMarker.z, 0.02);
        float angle = uuiMapState.w;
        float s = sin(angle);
        float c = cos(angle);
        vec2 local = p - uuiMapMarker.xy;
        vec2 a = vec2(local.x * c - local.y * s, local.x * s + local.y * c);
        float arrow = uui_smap_arrow(a / scale) * scale;
        float outline = uuiMapPaintA.w * UUI_SMAP_ARROW_HEIGHT_UNITS * scale;
        float inside = 1.0 - smoothstep(-frameWidth - pixel * 0.5, -frameWidth + pixel * 0.5, border);
        color = mix(color, uuiMapPaintB.rgb, inside * uui_smap_coverage(arrow - outline, pixel));
        color = mix(color, uuiMapPaintA.rgb, inside * uui_smap_coverage(arrow, pixel));
    }

    if ((flags & 8) != 0) {
        vec2 north = vec2(-heading.x, -heading.y);
        vec2 reach = roundShape ? vec2(1.0) : extent;
        reach -= framed ? frameWidth * 0.5 : 0.1;
        float along = roundShape ? reach.x : min(reach.x / max(abs(north.x), 1.0e-4), reach.y / max(abs(north.y), 1.0e-4));
        float k = length(p - north * along);
        color = mix(color, vec3(0.05, 0.05, 0.06), uui_smap_coverage(k - 0.075, pixel));
        color = mix(color, vec3(0.86, 0.19, 0.17), uui_smap_coverage(k - 0.058, pixel));
        color = mix(color, vec3(0.98, 0.95, 0.92), uui_smap_coverage(k - 0.032, pixel));
    }

    float opacity = clamp(coverage * uuiMapPaintB.a * painted.a, 0.0, 1.0);
    result = vec4(color, 1.0 - sqrt(max(1.0 - opacity, 0.0)));
    return true;
}
