#define UUI_MASK_STATE_MIN 3100.0
#define UUI_MASK_STATE_MAX 6000.0
#define UUI_MASK_DAY_TICKS 24000.0
#define UUI_MASK_STATE_STEP 4.0
#define UUI_MASK_WINDOW vec2(176.0, 166.0)
#define UUI_MASK_BACKDROP_RGB (16.0 / 255.0)
#define UUI_MASK_BACKDROP_TOLERANCE (0.75 / 255.0)
#define UUI_MASK_BACKDROP_ALPHA_MIN 0.74
#define UUI_MASK_BACKDROP_ALPHA_MAX 0.83

bool uui_mask_active(float clock) {
    float state = -clock * UUI_MASK_DAY_TICKS / UUI_MASK_STATE_STEP;
    return state > UUI_MASK_STATE_MIN && state < UUI_MASK_STATE_MAX;
}

bool uui_mask_gui_projection(mat4 proj) {
    return abs(proj[2][3]) < 1.0e-6 && abs(proj[3][3] - 1.0) < 1.0e-4 && proj[0][0] > 0.0 && proj[1][1] < 0.0;
}

vec4 uui_mask_window(mat4 proj, float clock) {
    if (!uui_mask_active(clock) || !uui_mask_gui_projection(proj)) {
        return vec4(0.0);
    }
    vec2 gui = floor(vec2(2.0 / proj[0][0], -2.0 / proj[1][1]) + 0.5);
    vec2 origin = floor((gui - UUI_MASK_WINDOW) * 0.5 + 1.0e-3);
    return vec4(origin, origin + UUI_MASK_WINDOW);
}

bool uui_mask_inside(vec4 window, vec2 guiPos) {
    return window.z > window.x
        && guiPos.x >= window.x && guiPos.y >= window.y
        && guiPos.x <= window.z && guiPos.y <= window.w;
}

bool uui_mask_backdrop(vec4 color) {
    return all(lessThan(abs(color.rgb - vec3(UUI_MASK_BACKDROP_RGB)), vec3(UUI_MASK_BACKDROP_TOLERANCE)))
        && color.a > UUI_MASK_BACKDROP_ALPHA_MIN && color.a < UUI_MASK_BACKDROP_ALPHA_MAX;
}

#define UUI_HUD_HIDE_STATE_MIN 0.5
#define UUI_HUD_CORNER 1.0
#define UUI_HUD_NOT_CORNER -1.0e4
#define UUI_HUD_CORNER_TOLERANCE 0.01
#define UUI_HUD_GUI_SIZE_TOLERANCE 1.0e-3
#define UUI_HUD_CROSSHAIR_SIZE 15.0
#define UUI_HUD_ATTACK_LEFT 8.0
#define UUI_HUD_ATTACK_TOP 9.0
#define UUI_HUD_ATTACK_WIDTH 16.0
#define UUI_HUD_ATTACK_BAR_HEIGHT 4.0
#define UUI_HUD_ATTACK_FULL_HEIGHT 16.0
#define UUI_HUD_EXPERIENCE_WIDTH 182.0
#define UUI_HUD_EXPERIENCE_HEIGHT 5.0
#define UUI_HUD_EXPERIENCE_TOP 29.0

bool uui_hud_on(float value, float edge) {
    return abs(value - edge) < UUI_HUD_CORNER_TOLERANCE;
}

bool uui_hud_within(float value, float start, float width) {
    return value > start - UUI_HUD_CORNER_TOLERANCE
        && value < start + width + UUI_HUD_CORNER_TOLERANCE
        && uui_hud_on(value, floor(value + 0.5));
}

float uui_hud_corner(mat4 proj, float clock, vec2 guiPos) {
    float state = -clock * UUI_MASK_DAY_TICKS / UUI_MASK_STATE_STEP;
    if (state < UUI_HUD_HIDE_STATE_MIN || state >= UUI_MASK_STATE_MAX || !uui_mask_gui_projection(proj)) {
        return UUI_HUD_NOT_CORNER;
    }
    vec2 gui = ceil(vec2(2.0 / proj[0][0], -2.0 / proj[1][1]) - UUI_HUD_GUI_SIZE_TOLERANCE);
    vec2 centre = floor(gui * 0.5);
    vec2 crosshair = floor((gui - UUI_HUD_CROSSHAIR_SIZE) * 0.5);
    bool crosshairCorner = (uui_hud_on(guiPos.x, crosshair.x) || uui_hud_on(guiPos.x, crosshair.x + UUI_HUD_CROSSHAIR_SIZE))
        && (uui_hud_on(guiPos.y, crosshair.y) || uui_hud_on(guiPos.y, crosshair.y + UUI_HUD_CROSSHAIR_SIZE));
    float attackTop = centre.y + UUI_HUD_ATTACK_TOP;
    bool attackCorner = uui_hud_within(guiPos.x, centre.x - UUI_HUD_ATTACK_LEFT, UUI_HUD_ATTACK_WIDTH)
        && (uui_hud_on(guiPos.y, attackTop)
            || uui_hud_on(guiPos.y, attackTop + UUI_HUD_ATTACK_BAR_HEIGHT)
            || uui_hud_on(guiPos.y, attackTop + UUI_HUD_ATTACK_FULL_HEIGHT));
    float experienceTop = gui.y - UUI_HUD_EXPERIENCE_TOP;
    bool experienceCorner = uui_hud_within(guiPos.x, floor((gui.x - UUI_HUD_EXPERIENCE_WIDTH) * 0.5), UUI_HUD_EXPERIENCE_WIDTH)
        && (uui_hud_on(guiPos.y, experienceTop) || uui_hud_on(guiPos.y, experienceTop + UUI_HUD_EXPERIENCE_HEIGHT));
    return crosshairCorner || attackCorner || experienceCorner ? UUI_HUD_CORNER : UUI_HUD_NOT_CORNER;
}

bool uui_hud_hidden(float corner) {
    return corner > UUI_HUD_CORNER * 0.5;
}

#define UUI_MASK_DIM_MAX_RGB 0.3
#define UUI_MASK_EDGE_TOLERANCE 0.5

bool uui_mask_screen_dim(vec4 window, mat4 proj, vec2 guiPos, vec4 color) {
    if (window.z <= window.x) {
        return false;
    }
    vec2 gui = floor(vec2(2.0 / proj[0][0], -2.0 / proj[1][1]) + 0.5);
    bool edgeX = abs(guiPos.x) < UUI_MASK_EDGE_TOLERANCE || abs(guiPos.x - gui.x) < UUI_MASK_EDGE_TOLERANCE;
    bool edgeY = abs(guiPos.y) < UUI_MASK_EDGE_TOLERANCE || abs(guiPos.y - gui.y) < UUI_MASK_EDGE_TOLERANCE;
    return edgeX && edgeY
        && max(max(color.r, color.g), color.b) < UUI_MASK_DIM_MAX_RGB
        && color.a > 0.0 && color.a < 1.0;
}
