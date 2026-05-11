#version 430 core

layout(location = 0) out vec4 outColor;

struct Metadata
{
    vec2 size;
    float rounding;
    float thickness; // outline thickness
};

layout(std430, binding = 0) buffer Metadatas {
    Metadata metadatas[];
};

uniform sampler2D texSampler;

in vec2 v_UV;
in vec2 v_LocalUV;
flat in int v_MetaId;

flat in vec4 v_TLColor;
flat in vec4 v_TRColor;
flat in vec4 v_BLColor;
flat in vec4 v_BRColor;
flat in int v_RenderMode;

float calc(vec2 p, vec2 b, float r) {
    return length(max(abs(p) - b, 0.0)) - r;
}

uniform int u_ScissorCount;
uniform vec4 u_Scissor[32];

bool isInsideScissors() {
    vec2 fragCoord = gl_FragCoord.xy;
    if (u_ScissorCount == 0) return true;

    for (int i = 0; i < u_ScissorCount; i++) {
        vec4 scissor = u_Scissor[i];

        if (!(fragCoord.x >= scissor.x && fragCoord.y >= scissor.y &&
        fragCoord.x < scissor.x + scissor.z && fragCoord.y < scissor.y + scissor.w)) {
            return false;
        }
    }

    return true;
}

void main()
{
    if(!isInsideScissors())
        {
              outColor = vec4(0,0,0,0);
              discard;
        }
    vec4 colorTop = mix(v_TLColor, v_TRColor, v_LocalUV.x);
    vec4 colorBottom = mix(v_BLColor, v_BRColor, v_LocalUV.x);
    vec4 v_Color = mix(colorBottom, colorTop, v_LocalUV.y);

    vec4 texColor = texture(texSampler, v_UV);
    vec4 in_Color = texColor * v_Color;

    if(v_MetaId >= 0)
    {
        Metadata meta = metadatas[v_MetaId];
        vec2 pixel = v_LocalUV * meta.size;
        vec2 centre = 0.5 * meta.size;
        float distance = calc(centre - pixel, centre - meta.rounding - 1, meta.rounding);

        if(v_RenderMode == 0)
        {
            float sa = smoothstep(0.0, 1.0, distance);
            vec4 c = mix(vec4(in_Color.rgb, 1), vec4(in_Color.rgb, 0), sa);
            outColor = vec4(c.rgb, in_Color.a * c.a);
        }
        else if(v_RenderMode == 1)
        {
            float thickness = meta.thickness;
            float alpha = smoothstep(-thickness, 0.0, distance) - smoothstep(0.0, thickness, distance);
            outColor = vec4(in_Color.rgb, in_Color.a * alpha);
        }
        else
        {
            outColor = in_Color;
        }
    }
    else
    {
        outColor = in_Color;
    }
}