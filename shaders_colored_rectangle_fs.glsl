#version 430 core

layout(location = 0) out vec4 outColor;

struct Metadata {
    vec2 size;
    float rounding;
    float thickness;
};

layout(std430, binding = 0) buffer Metadatas {
    Metadata metadatas[];
};

in vec2 v_UV;
flat in vec4 v_TLColor;
flat in vec4 v_TRColor;
flat in vec4 v_BLColor;
flat in vec4 v_BRColor;
flat in int v_MetaId;
flat in int v_RenderMode;

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

float calc(vec2 p, vec2 b, float r) {
    return length(max(abs(p) - b, 0.0)) - r;
}

void main() {
    if(!isInsideScissors())
        {
              outColor = vec4(0,0,0,0);
              discard;
        }
    vec4 topColor = mix(v_TLColor, v_TRColor, v_UV.x);
    vec4 bottomColor = mix(v_BLColor, v_BRColor, v_UV.x);
    vec4 v_Color = mix(bottomColor, topColor, v_UV.y);

    //add testing soon

    if (v_MetaId >= 0) {
        Metadata meta = metadatas[v_MetaId];
        vec2 pixel = v_UV * meta.size;
        vec2 centre = 0.5 * meta.size;
        float distance = calc(centre - pixel, centre - meta.rounding - 1, meta.rounding);

        if (v_RenderMode == 0) {
            float sa = smoothstep(0.0, 1.0, distance);
            vec4 c = mix(vec4(v_Color.rgb, 1), vec4(v_Color.rgb, 0), sa);
            outColor = vec4(c.rgb, v_Color.a * c.a);
        } else if (v_RenderMode == 1) {
            float thickness = meta.thickness;
            float alpha = smoothstep(-thickness, 0.0, distance) - smoothstep(0.0, thickness, distance);
            outColor = vec4(v_Color.rgb, v_Color.a * alpha);
        }else if (v_RenderMode == 2) {
            float thickness = meta.thickness;
            float aa = fwidth(distance);

            float outer = 1.0 - smoothstep(0.0, aa, distance);

            float inner = smoothstep(-thickness - aa, -thickness + aa, distance);

            float alpha = outer * inner;

            outColor = vec4(v_Color.rgb, v_Color.a * alpha);
        } else if(v_RenderMode == 3) {
            float sa = smoothstep(-2.5f, 2.5f, distance);
            vec4 c = mix(vec4(v_Color.rgb, 1), vec4(v_Color.rgb, 0), sa);
            outColor = vec4(c.rgb, v_Color.a * c.a);
        }


        else {
            outColor = v_Color;
        }
    } else {
        outColor = v_Color;
    }
}