#version 150
#moj_import <fog.glsl>
#moj_import <hud.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV2;

uniform sampler2D Sampler2;
uniform mat4 ModelViewMat;
uniform mat4 ProjMat;
uniform int FogShape;
uniform vec2 ScreenSize;
uniform float GameTime;

out float vertexDistance;
out vec4 vertexColor;
out vec2 texCoord0;
out float uuiClipDistance;
out vec2 uuiMapUv;
flat out vec4 uuiMapState;
flat out vec4 uuiMapCenter;
flat out vec4 uuiMapShape;
flat out vec4 uuiMapMarker;
flat out vec4 uuiMapPaintA;
flat out vec4 uuiMapPaintB;

uniform sampler2D Sampler0;

#moj_import <uui_screenmap_vertex.glsl>

#moj_import <uui_mask.glsl>

void main() {
    uuiClipDistance = 1.0;
    vec4 uuiWorldClip;
    if (uui_smap_world(Sampler0, UV0, mat3(1.0), transpose(mat3(ModelViewMat)), ProjMat, ModelViewMat, ScreenSize, 0, Position, uuiWorldClip)) {
        gl_Position = uuiWorldClip;
        vertexDistance = -1.0e6;
        vertexColor = vec4(1.0);
        texCoord0 = UV0;
        return;
    }
    if (uui_smap_vertex(Sampler0, UV0, transpose(mat3(ModelViewMat)), ScreenSize, 0, GameTime)) {
        vertexDistance = -1.0e6;
        vertexColor = vec4(1.0);
        texCoord0 = UV0;
        return;
    }
    gl_Position = ProjMat * ModelViewMat * vec4(Position, 1.0);
    if (uui_mask_inside(uui_mask_window(ProjMat, GameTime), (ModelViewMat * vec4(Position, 1.0)).xy)) {
        gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
        vertexColor = vec4(0.0);
        texCoord0 = vec2(0.0);
        return;
    }
    vertexDistance = fog_distance(Position, FogShape);
    vertexColor = Color * texelFetch(Sampler2, UV2 / 16, 0);
    texCoord0 = UV0;

    if (make_hud(Position, ScreenSize, ModelViewMat)) {
        uuiClipDistance = uui_clip_distance(UV2, Color);
        vertexColor = Color;
        vertexDistance = -1.0e6;
    }
}