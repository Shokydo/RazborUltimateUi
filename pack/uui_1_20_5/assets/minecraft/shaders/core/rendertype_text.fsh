#version 150

#moj_import <fog.glsl>

uniform sampler2D Sampler0;

uniform vec4 ColorModulator;
uniform float FogStart;
uniform float FogEnd;
uniform vec4 FogColor;

in float vertexDistance;
in vec4 vertexColor;
in vec2 texCoord0;
in float uuiClipDistance;
in vec2 uuiMapUv;
flat in vec4 uuiMapState;
flat in vec4 uuiMapCenter;
flat in vec4 uuiMapShape;
flat in vec4 uuiMapMarker;
flat in vec4 uuiMapPaintA;
flat in vec4 uuiMapPaintB;

#moj_import <uui_screenmap_fragment.glsl>

out vec4 fragColor;

void main() {
    vec4 uuiMapColor;
    if (uui_smap_fragment(Sampler0, uuiMapColor)) {
        fragColor = uuiMapColor;
        return;
    }
    if (uuiClipDistance < 0.0) {
        discard;
    }
    vec4 color = texture(Sampler0, texCoord0) * vertexColor * ColorModulator;
    if (color.a < 0.1) {
        discard;
    }
    fragColor = linear_fog(color, vertexDistance, FogStart, FogEnd, FogColor);
}
