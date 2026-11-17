#define UUI_SMAP_TEXTURE_SIZE 128
#define UUI_SMAP_HEADER_FIELD 6
#define UUI_SMAP_WIDE_BIAS 32768
#define UUI_SMAP_ARROW_HEIGHT 0.186
#define UUI_SMAP_CORE 112.0
#define UUI_SMAP_MARGIN 8.0

int uui_smap_digit_at(sampler2D source, int column, int row) {
    ivec3 c = ivec3(texelFetch(source, ivec2(column, row), 0).rgb * 255.0 + 0.5);
    if (c == ivec3(125, 53, 152)) return 0;
    if (c == ivec3(153, 65, 186)) return 1;
    if (c == ivec3(178, 76, 216)) return 2;
    if (c == ivec3(94, 40, 114)) return 3;
    return -1;
}

int uui_smap_digit(sampler2D source, int column) {
    return uui_smap_digit_at(source, column, 0);
}

int uui_smap_read(sampler2D source, int start, int row) {
    int value = 0;
    for (int i = 3; i >= 0; i--) {
        int digit = uui_smap_digit_at(source, start + i, row);
        if (digit < 0) {
            return -1;
        }
        value = value * 4 + digit;
    }
    return value;
}

int uui_smap_field(sampler2D source, int index) {
    return uui_smap_read(source, UUI_SMAP_HEADER_FIELD + index * 4, 0);
}

int uui_smap_extra(sampler2D source, int index) {
    return uui_smap_read(source, index * 4, 1);
}

int uui_smap_wide(sampler2D source, int index) {
    int low = uui_smap_field(source, index);
    int high = uui_smap_field(source, index + 1);
    if (low < 0 || high < 0) {
        return -1;
    }
    return low + high * 256;
}

int uui_smap_extra_wide(sampler2D source, int index) {
    int low = uui_smap_extra(source, index);
    int high = uui_smap_extra(source, index + 1);
    if (low < 0 || high < 0) {
        return -1;
    }
    return low + high * 256;
}

float uui_smap_unwide(int value, float scale) {
    return float(value - UUI_SMAP_WIDE_BIAS) / scale;
}

float uui_smap_motion(float current, float stepNow, float stepBefore, float t) {
    return t >= 1.0 ? current - stepNow * (2.0 - t) : current - stepNow - stepBefore * (1.0 - t);
}

vec2 uui_smap_motion(vec2 current, vec2 stepNow, vec2 stepBefore, float t) {
    return t >= 1.0 ? current - stepNow * (2.0 - t) : current - stepNow - stepBefore * (1.0 - t);
}

vec3 uui_smap_extra_color(sampler2D source, int index) {
    return vec3(
        float(max(uui_smap_extra(source, index), 0)),
        float(max(uui_smap_extra(source, index + 1), 0)),
        float(max(uui_smap_extra(source, index + 2), 0))) / 255.0;
}

bool uui_smap_signed(sampler2D source) {
    return uui_smap_digit(source, 0) == 1
        && uui_smap_digit(source, 1) == 3
        && uui_smap_digit(source, 2) == 0
        && uui_smap_digit(source, 3) == 2
        && uui_smap_digit(source, 4) == 3
        && uui_smap_digit(source, 5) == 1;
}

vec2 uui_smap_heading(mat3 viewToWorld) {
    vec3 forward = viewToWorld * vec3(0.0, 0.0, -1.0);
    vec3 up = viewToWorld * vec3(0.0, 1.0, 0.0);
    vec2 heading = forward.xz * up.y - up.xz * forward.y;
    if (dot(heading, heading) < 1.0e-8) {
        return vec2(0.0, -1.0);
    }
    return normalize(heading);
}

float uui_smap_depth(float layer, int depthMode) {
    float rawZ = -layer * 100.0;
    if (depthMode == 1) {
        return clamp(0.95 - rawZ / 19999999.0, 0.0, 0.99999);
    }
    return clamp(rawZ / 1000000.0, -0.99999, 0.99999);
}

vec4 uui_smap_world_clip(mat4 projection, mat4 modelView, vec3 position, vec3 axisA, vec3 axisB, vec2 screenSize,
                         int depthMode) {
    vec4 clip = projection * modelView * vec4(position, 1.0);
    vec4 clipA = projection * modelView * vec4(position + axisA, 1.0);
    vec4 clipB = projection * modelView * vec4(position + axisB, 1.0);
    if (min(clip.w, min(clipA.w, clipB.w)) <= 1.0e-4) {
        return clip;
    }
    vec3 ndc = clip.xyz / clip.w;
    vec3 ndcA = clipA.xyz / clipA.w;
    vec3 ndcB = clipB.xyz / clipB.w;
    float zScale = depthMode == 1 ? 1.0 : 0.5;
    vec2 pixels = screenSize * 0.5;
    vec2 stepA = (ndcA.xy - ndc.xy) * pixels;
    vec2 stepB = (ndcB.xy - ndc.xy) * pixels;
    float depthA = (ndcA.z - ndc.z) * zScale;
    float depthB = (ndcB.z - ndc.z) * zScale;
    float det = stepA.x * stepB.y - stepA.y * stepB.x;
    float slope = 0.0;
    if (abs(det) > 1.0e-6) {
        vec2 gradient = vec2(depthA * stepB.y - depthB * stepA.y, stepA.x * depthB - stepB.x * depthA) / det;
        slope = max(abs(gradient.x), abs(gradient.y));
    }
    float windowDepth = depthMode == 1 ? ndc.z : ndc.z * 0.5 + 0.5;
    float unit = depthMode == 1 ? max(windowDepth, 1.0e-9) * 1.1920929e-7 : 5.9604645e-8;
    float bias = slope + 10.0 * unit;
    clip.z += (depthMode == 1 ? bias : -2.0 * bias) * clip.w;
    return clip;
}

bool uui_smap_world(sampler2D source, vec2 corner, mat3 positionToWorld, mat3 viewToWorld, mat4 projection,
                    mat4 modelView, vec2 screenSize, int depthMode, vec3 position, out vec4 clip) {
    clip = vec4(0.0);
    if (textureSize(source, 0) != ivec2(UUI_SMAP_TEXTURE_SIZE) || !uui_smap_signed(source)) {
        return false;
    }
    int placement = uui_smap_field(source, 7);
    if (placement < 7 || placement > 9) {
        return false;
    }
    int flags = uui_smap_field(source, 4);
    int grid = uui_smap_field(source, 24);
    int cell = uui_smap_field(source, 25);
    int contentX = uui_smap_wide(source, 19);
    int contentY = uui_smap_wide(source, 21);
    int opacity = uui_smap_extra(source, 11);
    if (min(min(flags, grid), min(cell, min(contentX, contentY))) < 0) {
        return false;
    }
    float values[9];
    for (int i = 0; i < 9; i++) {
        int raw = uui_smap_extra_wide(source, 13 + i * 2);
        if (raw < 0) {
            return false;
        }
        values[i] = float(raw - UUI_SMAP_WIDE_BIAS);
    }
    vec3 delta = vec3(values[0], values[1], values[2]) / 512.0;
    float yaw = radians(values[3] / 64.0);
    float left = values[4] / 512.0;
    float top = values[5] / 512.0;
    float width = values[6] / 512.0;
    float height = values[7] / 512.0;
    float depth = values[8] / 16384.0;
    vec2 content = max(vec2(float(contentX - UUI_SMAP_WIDE_BIAS), float(contentY - UUI_SMAP_WIDE_BIAS)) / 16.0, vec2(1.0));

    vec3 anchor = positionToWorld * position - vec3(corner.x, 0.0, corner.y) + delta;
    vec3 right = vec3(-cos(yaw), 0.0, -sin(yaw));
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 back = vec3(sin(yaw), 0.0, -cos(yaw));
    if (placement == 8) {
        vec3 cameraRight = viewToWorld * vec3(1.0, 0.0, 0.0);
        right = normalize(vec3(cameraRight.x, 0.0, cameraRight.z) + vec3(1.0e-6, 0.0, 0.0));
        back = cross(right, up);
    } else if (placement == 9) {
        right = normalize(viewToWorld * vec3(1.0, 0.0, 0.0));
        up = normalize(viewToWorld * vec3(0.0, 1.0, 0.0));
        back = normalize(viewToWorld * vec3(0.0, 0.0, 1.0));
    }

    vec2 origin = vec2(float(cell & 15) * 128.0, float(cell >> 4) * 124.0);
    vec2 limit = min(origin + vec2(128.0, 124.0), content);
    vec2 fraction = mix(origin, limit, corner) / content;
    vec3 target = anchor + right * (left + fraction.x * width) + up * (top - fraction.y * height) + back * depth;
    mat3 worldToPosition = transpose(positionToWorld);
    clip = uui_smap_world_clip(projection, modelView, worldToPosition * target, worldToPosition * (right * 0.1),
        worldToPosition * (up * 0.1), screenSize, depthMode);

    uuiMapUv = vec2(fraction.x * 2.0 - 1.0, 1.0 - fraction.y * 2.0);
    uuiMapState = vec4(1.0, min(content.x, content.y) * 0.5, float(flags), 0.0);
    uuiMapCenter = vec4(origin, content);
    uuiMapShape = vec4(1.0, 1.0, 0.0, 10000.0);
    uuiMapMarker = vec4(0.0);
    uuiMapPaintA = vec4(0.0);
    uuiMapPaintB = vec4(0.0, 0.0, 0.0, opacity < 0 ? 1.0 : float(opacity) / 255.0);
    return true;
}

bool uui_smap_vertex(sampler2D source, vec2 corner, mat3 viewToWorld, vec2 screenSize, int depthMode, float gameTime) {
    uuiMapUv = vec2(0.0);
    uuiMapState = vec4(0.0);
    uuiMapCenter = vec4(0.0);
    uuiMapShape = vec4(1.0, 1.0, 0.0, 1.0);
    uuiMapMarker = vec4(0.0);
    uuiMapPaintA = vec4(0.0);
    uuiMapPaintB = vec4(0.0);

    if (textureSize(source, 0) != ivec2(UUI_SMAP_TEXTURE_SIZE) || !uui_smap_signed(source)) {
        return false;
    }

    int offsetX = uui_smap_field(source, 0);
    int offsetZ = uui_smap_field(source, 1);
    int fractionX = uui_smap_field(source, 2);
    int fractionZ = uui_smap_field(source, 3);
    int flags = uui_smap_field(source, 4);
    int panel = uui_smap_field(source, 5);
    int placement = uui_smap_field(source, 7);
    int centerX = uui_smap_wide(source, 8);
    int centerY = uui_smap_wide(source, 10);
    int size = uui_smap_wide(source, 12);
    int layer = uui_smap_wide(source, 14);
    int height = uui_smap_wide(source, 16);
    int cornerRadius = uui_smap_field(source, 18);
    int playerX = uui_smap_wide(source, 19);
    int playerZ = uui_smap_wide(source, 21);
    int arrowSize = uui_smap_field(source, 23);
    int grid = uui_smap_field(source, 24);
    int cell = uui_smap_field(source, 25);
    int radiusWide = uui_smap_wide(source, 26);
    if (min(min(min(offsetX, offsetZ), min(fractionX, fractionZ)), min(flags, panel)) < 0) {
        return false;
    }
    if (min(min(min(placement, centerX), min(min(centerY, size), layer)), min(height, cornerRadius)) < 0) {
        return false;
    }
    if (min(min(min(playerX, playerZ), arrowSize), min(min(grid, cell), radiusWide)) < 0) {
        return false;
    }

    float motionTime = 2.0;
    vec2 viewNow = vec2(0.0);
    vec2 viewBefore = vec2(0.0);
    float radiusNow = 0.0;
    float radiusBefore = 0.0;
    vec2 playerNow = vec2(0.0);
    vec2 playerBefore = vec2(0.0);
    int motionFlags = uui_smap_extra(source, 12);
    if (motionFlags >= 4) {
        int moveX = uui_smap_extra_wide(source, 13);
        int moveZ = uui_smap_extra_wide(source, 15);
        int moveRadius = uui_smap_extra_wide(source, 17);
        int movePlayerX = uui_smap_extra_wide(source, 19);
        int movePlayerZ = uui_smap_extra_wide(source, 21);
        int lastX = uui_smap_extra_wide(source, 23);
        int lastZ = uui_smap_extra_wide(source, 25);
        int lastRadius = uui_smap_extra_wide(source, 27);
        int lastPlayerX = uui_smap_extra_wide(source, 29);
        int lastPlayerZ = uui_smap_wide(source, 28);
        int lowest = min(min(min(moveX, moveZ), min(moveRadius, movePlayerX)), min(min(movePlayerZ, lastX), min(lastZ, lastRadius)));
        if (min(lowest, min(lastPlayerX, lastPlayerZ)) >= 0) {
            viewNow = vec2(uui_smap_unwide(moveX, 256.0), uui_smap_unwide(moveZ, 256.0));
            viewBefore = vec2(uui_smap_unwide(lastX, 256.0), uui_smap_unwide(lastZ, 256.0));
            radiusNow = uui_smap_unwide(moveRadius, 64.0);
            radiusBefore = uui_smap_unwide(lastRadius, 64.0);
            playerNow = vec2(uui_smap_unwide(movePlayerX, 16.0), uui_smap_unwide(movePlayerZ, 16.0));
            playerBefore = vec2(uui_smap_unwide(lastPlayerX, 16.0), uui_smap_unwide(lastPlayerZ, 16.0));
            float clock = gameTime * 24000.0;
            motionTime = clamp(mod(clock - float(motionFlags & 3) + 2.0, 4.0) - 2.0, 0.0, 2.0);
        }
    }

    int columns = (grid & 15) + 1;
    int rows = (grid >> 4) + 1;
    int column = cell & 15;
    int row = cell >> 4;
    float radius = max(uui_smap_motion(float(radiusWide - UUI_SMAP_WIDE_BIAS) / 16.0, radiusNow, radiusBefore, motionTime), 0.5);
    float inner = (flags & 16) != 0 ? 1.0 : 0.9;

    vec2 facing = uui_smap_heading(viewToWorld);
    vec2 heading = (flags & 1) != 0 ? facing : vec2(0.0, -1.0);
    vec2 right = vec2(-heading.y, heading.x);
    vec2 arrow = vec2(dot(facing, right), dot(facing, heading));

    bool media = (flags & 64) != 0;
    vec2 content = max(vec2(float(playerX - UUI_SMAP_WIDE_BIAS), float(playerZ - UUI_SMAP_WIDE_BIAS)) / 16.0, vec2(1.0));

    vec2 center = vec2(0.0);
    vec2 halfSize;
    vec2 extent = vec2(1.0);
    float unitPixels;
    float halfCanvas;
    if (placement == 0) {
        float halfHeight = max(float(panel) / 255.0, 0.02);
        float aspect = screenSize.x / max(screenSize.y, 1.0);
        halfSize = vec2(halfHeight / max(aspect, 0.01), halfHeight);
        unitPixels = halfHeight * screenSize.y * 0.5;
        halfCanvas = halfHeight * 540.0;
    } else if (placement >= 4) {
        float contentAspect = content.x / content.y;
        float screenAspect = screenSize.x / max(screenSize.y, 1.0);
        extent = contentAspect >= 1.0 ? vec2(contentAspect, 1.0) : vec2(1.0, 1.0 / contentAspect);
        halfSize = vec2(1.0);
        if (placement != 4) {
            halfSize = screenAspect > contentAspect ? vec2(contentAspect / screenAspect, 1.0) : vec2(1.0, screenAspect / contentAspect);
            if (placement == 6) {
                halfSize /= min(halfSize.x, halfSize.y);
            }
        }
        unitPixels = min(halfSize.x * screenSize.x / extent.x, halfSize.y * screenSize.y / extent.y) * 0.5;
        halfCanvas = 540.0;
    } else {
        float wide = (screenSize.y / 9.0 * 16.0) / max(screenSize.x, 1.0);
        float offset = placement == 1 ? wide - 1.0 : (placement == 3 ? 1.0 - wide : 0.0);
        vec2 canvas = vec2(float(centerX - UUI_SMAP_WIDE_BIAS), float(centerY - UUI_SMAP_WIDE_BIAS)) / 4.0;
        center = vec2((canvas.x - 960.0) / 960.0 * wide + offset, (540.0 - canvas.y) / 540.0);
        vec2 sides = max(vec2(float(size - UUI_SMAP_WIDE_BIAS), float(height - UUI_SMAP_WIDE_BIAS)) / 4.0, vec2(1.0));
        float shortSide = min(sides.x, sides.y);
        extent = sides / shortSide;
        halfSize = vec2(sides.x / 1920.0 * wide, sides.y / 1080.0);
        unitPixels = shortSide * 0.5 * screenSize.y / 1080.0;
        halfCanvas = shortSide * 0.5;
    }

    vec2 view = vec2(
        float(offsetX - 128) + float(fractionX) / 256.0,
        float(offsetZ - 128) + float(fractionZ) / 256.0);
    view = uui_smap_motion(view, viewNow, viewBefore, motionTime);

    vec2 window = vec2(float(columns), float(rows)) * UUI_SMAP_CORE;
    vec2 panelUv;
    vec2 local;
    if (media) {
        vec2 origin = vec2(float(column) * 128.0, float(row) * 124.0);
        vec2 limit = min(origin + vec2(128.0, 124.0), content);
        vec2 spot = mix(origin, limit, corner);
        panelUv = vec2(spot.x / content.x * 2.0 - 1.0, 1.0 - spot.y / content.y * 2.0) * extent;
        local = origin;
    } else if ((flags & 32) != 0) {
        vec2 tileOrigin = vec2(float(grid - 128), float(cell - 128)) * UUI_SMAP_CORE;
        vec2 cellMin = tileOrigin - view;
        vec2 cellMax = cellMin + UUI_SMAP_CORE;
        vec2 uv = vec2(mix(cellMin.x, cellMax.x, corner.x), -mix(cellMin.y, cellMax.y, corner.y)) * (inner / radius);
        panelUv = clamp(uv, -extent, extent);
        local = vec2(UUI_SMAP_MARGIN) - tileOrigin;
    } else if (columns == 1 && rows == 1) {
        panelUv = vec2(corner.x * 2.0 - 1.0, 1.0 - corner.y * 2.0) * extent;
        local = window * 0.5 + UUI_SMAP_MARGIN;
    } else {
        float k = inner / radius;
        vec2 cellMin = vec2(float(column), float(row)) * UUI_SMAP_CORE - window * 0.5;
        vec2 cellMax = cellMin + UUI_SMAP_CORE;
        vec2 uv = vec2(mix(cellMin.x, cellMax.x, corner.x), -mix(cellMin.y, cellMax.y, corner.y)) * k;
        panelUv = clamp(uv, -extent, extent);
        local = window * 0.5 - vec2(float(column), float(row)) * UUI_SMAP_CORE + UUI_SMAP_MARGIN;
    }

    float depth = uui_smap_depth(float(layer - UUI_SMAP_WIDE_BIAS) / 2.0, depthMode);
    gl_Position = vec4(center + panelUv / extent * halfSize, depth, 1.0);

    uuiMapUv = panelUv;
    uuiMapState = vec4(1.0, radius, float(flags), atan(arrow.x, arrow.y));
    uuiMapShape = vec4(extent, float(cornerRadius) / 255.0, max(unitPixels, 1.0));
    uuiMapCenter = media ? vec4(local, content) : vec4(local + view, heading);

    vec2 player = vec2(float(playerX - UUI_SMAP_WIDE_BIAS), float(playerZ - UUI_SMAP_WIDE_BIAS)) / 16.0;
    player = uui_smap_motion(player, playerNow, playerBefore, motionTime);
    vec2 playerUv = vec2(dot(player, right), dot(player, heading)) * inner / radius;
    int unexploredStyle = uui_smap_extra(source, 9);
    vec3 unexplored = uui_smap_extra_color(source, 6) * 255.0;
    float unexploredPacked = unexploredStyle == 1 ? unexplored.r * 65536.0 + unexplored.g * 256.0 + unexplored.b
        : (unexploredStyle == 2 ? -2.0 : -1.0);
    uuiMapMarker = vec4(playerUv, clamp(float(arrowSize) / UUI_SMAP_ARROW_HEIGHT / max(halfCanvas, 1.0), 0.02, 4.0), unexploredPacked);

    int outline = uui_smap_extra(source, 10);
    int opacity = uui_smap_extra(source, 11);
    uuiMapPaintA = vec4(uui_smap_extra_color(source, 0), outline < 0 ? 0.09 : float(outline) / 100.0);
    uuiMapPaintB = vec4(uui_smap_extra_color(source, 3), opacity < 0 ? 1.0 : float(opacity) / 255.0);
    return true;
}
