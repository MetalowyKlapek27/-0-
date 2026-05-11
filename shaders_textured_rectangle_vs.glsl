#version 430 core

layout (location = 0) in vec2 inPosition;
layout (location = 1) in vec2 inUV;
layout (location = 2) in vec4 inTLColor;
layout (location = 3) in vec4 inTRColor;
layout (location = 4) in vec4 inBLColor;
layout (location = 5) in vec4 inBRColor;
layout (location = 6) in int inMetaId;
layout (location = 7) in int inRenderMode;
layout (location = 8) in vec2 inLocalUV;

uniform mat4 u_Matrices;

out vec2 v_UV;
out vec2 v_LocalUV;
flat out int v_MetaId;

flat out vec4 v_TLColor;
flat out vec4 v_TRColor;
flat out vec4 v_BLColor;
flat out vec4 v_BRColor;
flat out int v_RenderMode;

void main()
{
    gl_Position = u_Matrices * vec4(inPosition, 0.0, 1.0);

    v_UV = vec2(inUV.x, 1.0 - inUV.y);
    v_LocalUV = vec2(inLocalUV.x, 1.0 - inLocalUV.y);
    v_MetaId = inMetaId;

    v_TLColor = inTLColor;
    v_TRColor = inTRColor;
    v_BLColor = inBLColor;
    v_BRColor = inBRColor;
    v_RenderMode = inRenderMode;
}