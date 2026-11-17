#define UUI_BB_SIZED_BASE 4194304.0
#define UUI_BB_SIZED_STRIDE 4096.0
#define UUI_BB_SIZED_MIN 3145728.0
#define UUI_BB_RANGE_MAX 8388608.0
#define UUI_BB_COVER_RAW_MAX -524288.0
#define UUI_BB_POS_SPAN 2048.0
#define UUI_BB_POS_X_BIAS 128.0
#define UUI_BB_POS_Y_BIAS 512.0
#define UUI_BB_POS_AREA 4194304.0
#define UUI_BB_RECT_X_BIAS_CENTER 1088.0
#define UUI_BB_RECT_X_BIAS_LEFT 128.0
#define UUI_BB_RECT_X_BIAS_RIGHT 2176.0
#define UUI_BB_TEXT_CODE_BASE 8388608.0
#define UUI_BB_TEXT_CODE_MIN 8387584.0
#define UUI_BB_TEXT_Y_LIMIT 1048576.0
#define UUI_BB_TEXT_X_SPAN 4096.0
#define UUI_BB_TEXT_X_BIAS 1024.0
#define UUI_BB_TEXT_Y_BIAS 512.0
#define UUI_BB_OPACITY_MAX 5.0
#define UUI_BB_REF_W 1920.0
#define UUI_BB_REF_H 1080.0
#define UUI_BB_EYE_GAP 0.178
#define UUI_BB_GUI_SCALE_FIELD 3
#define UUI_BB_GUI_SCALE_SPRITE_MARKER 3
#define UUI_BB_AUTO_MIN_W 320.0
#define UUI_BB_AUTO_MIN_H 240.0
#define UUI_BB_AUTO_SCALE_MAX 64

float uui_bb_gui_factor() {
    float guiWidth = max(1.0, floor((2.0 / ProjMat[0][0]) + 0.5));
    float actual = max(1.0, floor((ScreenSize.x / guiWidth) + 0.5));
    float autoScale = 1.0;
    for (int iteration = 1; iteration < UUI_BB_AUTO_SCALE_MAX; iteration++) {
        float next = autoScale + 1.0;
        if (autoScale >= ScreenSize.x || autoScale >= ScreenSize.y
            || floor(ScreenSize.x / next) < UUI_BB_AUTO_MIN_W || floor(ScreenSize.y / next) < UUI_BB_AUTO_MIN_H) {
            break;
        }
        autoScale = next;
    }
    return actual / autoScale;
}

vec4 uui_bb_project(float canvasX, float canvasY, int anchor, bool guiScaled, vec4 base) {
    float aspect = (ScreenSize.y / 9.0 * 16.0) / ScreenSize.x;
    float offset = 0.0;
    float pivotX = 0.0;
    if (anchor == 1) {
        offset = aspect - 1.0;
        pivotX = -1.0;
    } else if (anchor == 2) {
        offset = 1.0 - aspect;
        pivotX = 1.0;
    }
    float ndcX = (aspect * ((canvasX - (UUI_BB_REF_W * 0.5)) / (UUI_BB_REF_W * 0.5))) + offset;
    float ndcY = ((UUI_BB_REF_H * 0.5) - canvasY - UUI_BB_EYE_GAP) / (UUI_BB_REF_H * 0.5);
    if (guiScaled) {
        float factor = uui_bb_gui_factor();
        ndcX = pivotX + ((ndcX - pivotX) * factor);
        ndcY = ndcY * factor;
    }
    return vec4(ndcX, ndcY, base.z, base.w);
}

bool uui_bb() {
    if (ProjMat[3].x != -1.0) {
        return false;
    }

    float glyphY = Position.y;
    if (glyphY >= UUI_BB_RANGE_MAX) {
        return false;
    }

    float guiWidth = floor((2.0 / ProjMat[0][0]) + 0.5);
    float penStart = floor(guiWidth * 0.5);
    float raw = Position.x - penStart;
    if (raw < UUI_BB_COVER_RAW_MAX) {
        uuiBbCorner = vec3(-1.0, -1.0, -1.0);
        vertexColor = vec4(0.0, 0.0, 0.0, 0.0);
        texCoord0 = UV0;
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        return true;
    }
    bool sized = glyphY > UUI_BB_SIZED_MIN;
    if (!sized && (raw < UUI_BB_TEXT_CODE_MIN || abs(glyphY) >= UUI_BB_TEXT_Y_LIMIT)) {
        return false;
    }

    int vertexCorner = UUI_BB_VERTEX_ID & 3;
    vec4 base = ProjMat * ModelViewMat * vec4(Position, 1.0);
    int red = int(Color.r * 255.0 + 0.5);
    int green = int(Color.g * 255.0 + 0.5);
    int blue = int(Color.b * 255.0 + 0.5);

    if (sized) {
        int band = int(floor((glyphY - UUI_BB_SIZED_BASE) / UUI_BB_SIZED_STRIDE));
        if (band < 0) {
            band = 0;
        }
        int kind = band & 3;
        int anchor = band >> 2;
        bool guiScaled = false;
        if (kind != 2 && anchor >= UUI_BB_GUI_SCALE_FIELD) {
            guiScaled = true;
            anchor -= UUI_BB_GUI_SCALE_FIELD;
        }
        anchor = anchor & 3;
        if (kind == 3) {
            uuiBbCorner = vec3(-1.0, -1.0, -1.0);
            vertexColor = vec4(0.0, 0.0, 0.0, 0.0);
            texCoord0 = UV0;
            gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
            return true;
        }

        int data = (red << 16) | (green << 8) | blue;
        if (((data >> 23) & 1) == 0) {
            return false;
        }

        if (vertexCorner == 2 || vertexCorner == 3) {
            raw -= 1.0;
        }
        float code = floor(raw + 0.0625);
        if (code < 0.0 || code >= 16777216.0) {
            return false;
        }

        float opacityHigh = floor(code / UUI_BB_POS_AREA);
        float low = code - (opacityHigh * UUI_BB_POS_AREA);
        float yCell = floor(low / UUI_BB_POS_SPAN);
        float xCell = low - (yCell * UUI_BB_POS_SPAN);
        float left = xCell - UUI_BB_POS_X_BIAS;
        float top = yCell - UUI_BB_POS_Y_BIAS;

        int rotation = 0;
        float boxWidth;
        float boxHeight;
        int opacityLow = (data >> 22) & 1;
        uuiBbCorner = vec3(-1.0, -1.0, -1.0);
        if (kind == 0) {
            boxWidth = float(data & 2047) + 1.0;
            boxHeight = float((data >> 11) & 1023) + 1.0;
            float rectBias = UUI_BB_RECT_X_BIAS_CENTER;
            if (anchor == 1) {
                rectBias = UUI_BB_RECT_X_BIAS_LEFT;
            } else if (anchor == 2) {
                rectBias = UUI_BB_RECT_X_BIAS_RIGHT;
            }
            left = xCell + (float((data >> 21) & 1) * UUI_BB_POS_SPAN) - rectBias;
        } else if (kind == 1) {
            boxWidth = float(data & 255) + 1.0;
            boxHeight = float((data >> 8) & 255) + 1.0;
            rotation = (data >> 16) & 3;
            int maskSet = (data >> 18) & 15;
            float maskU = (vertexCorner == 0 || vertexCorner == 1) ? 0.0 : 1.0;
            float maskV = (vertexCorner == 0 || vertexCorner == 3) ? 0.0 : 1.0;
            uuiBbCorner = vec3(maskU, maskV, float(maskSet));
        } else {
            float spriteScale = float(1 << anchor);
            int spriteAnchor = (data >> 20) & 3;
            if (spriteAnchor == UUI_BB_GUI_SCALE_SPRITE_MARKER) {
                guiScaled = true;
                boxWidth = (float(data & 511) + 1.0) * spriteScale;
                boxHeight = (float((data >> 10) & 511) + 1.0) * spriteScale;
                anchor = ((data >> 9) & 1) | (((data >> 19) & 1) << 1);
            } else {
                boxWidth = (float(data & 1023) + 1.0) * spriteScale;
                boxHeight = (float((data >> 10) & 1023) + 1.0) * spriteScale;
                anchor = spriteAnchor;
            }
        }

        int slot = (vertexCorner + 4 - rotation) & 3;
        float alpha = ((opacityHigh * 2.0) + float(opacityLow)) / UUI_BB_OPACITY_MAX;
        float vertexX = (slot == 0 || slot == 1) ? left : (left + boxWidth);
        float vertexY = (slot == 0 || slot == 3) ? top : (top + boxHeight);

        vertexColor = vec4(1.0, 1.0, 1.0, alpha);
        texCoord0 = UV0;
        gl_Position = uui_bb_project(vertexX, vertexY, anchor, guiScaled, base);
        return true;
    }

    float code = raw - UUI_BB_TEXT_CODE_BASE;
    float yCell = floor(code / UUI_BB_TEXT_X_SPAN);
    float lowField = code - (yCell * UUI_BB_TEXT_X_SPAN);
    float canvasX = lowField - UUI_BB_TEXT_X_BIAS;
    float canvasY = (yCell - UUI_BB_TEXT_Y_BIAS) + glyphY;

    int opacity = ((red & 3) << 1) | (green & 1);
    int textAnchor = blue & 3;
    bool textGuiScaled = ((green >> 1) & 1) == 1;
    int redBase = red & 252;
    int greenBase = green & 252;
    int blueBase = blue & 252;
    float redOut = float(redBase | (redBase >> 6)) / 255.0;
    float greenOut = float(greenBase | (greenBase >> 6)) / 255.0;
    float blueOut = float(blueBase | (blueBase >> 6)) / 255.0;

    uuiBbCorner = vec3(-1.0, -1.0, -1.0);
    vertexColor = vec4(redOut, greenOut, blueOut, float(opacity) / UUI_BB_OPACITY_MAX);
    texCoord0 = UV0;
    gl_Position = uui_bb_project(canvasX, canvasY, textAnchor, textGuiScaled, base);
    return true;
}
