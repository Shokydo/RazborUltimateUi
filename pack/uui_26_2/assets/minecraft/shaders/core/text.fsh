#version 330

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
#moj_import <minecraft:fog.glsl>
#endif

#moj_import <minecraft:dynamictransforms.glsl>

uniform sampler2D Sampler0;

#if !defined(IS_GUI) && !defined(IS_SEE_THROUGH)
in float sphericalVertexDistance;
in float cylindricalVertexDistance;
#endif

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

#moj_import <minecraft:uui_screenmap_fragment.glsl>

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
#ifdef IS_GRAYSCALE
    vec4 texColor = texture(Sampler0, texCoord0).rrrr;
#else
    vec4 texColor = texture(Sampler0, texCoord0);
#endif

#ifdef IS_SEE_THROUGH
    vec4 color = texColor * vertexColor;
#else
    vec4 color = texColor * vertexColor * ColorModulator;
#endif
    if (color.a < 0.1) {
        discard;
    }

#ifdef IS_SEE_THROUGH
    fragColor = color * ColorModulator;
#elif defined(IS_GUI)
    fragColor = color;
#else
    fragColor = apply_fog(color, sphericalVertexDistance, cylindricalVertexDistance, FogEnvironmentalStart, FogEnvironmentalEnd, FogRenderDistanceStart, FogRenderDistanceEnd, FogColor);
#endif
}
