#version 430 core

layout(location = 0) out vec4 outColor;

struct Metadata {
    float fontSize;
    vec3 pad0;
};

layout(std430, binding = 0) buffer Metadatas {
    Metadata metadatas[];
};

uniform sampler2D texSampler;

in vec2 v_UV;
flat in vec4 v_TLColor;
flat in vec4 v_TRColor;
flat in vec4 v_BLColor;
flat in vec4 v_BRColor;
flat in int v_MetaId;

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


float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

float screenPxRange(vec2 uv, float fontSize) {
    vec2 unitRange = vec2(16.0) / vec2(textureSize(texSampler, 0));
    vec2 screenTexSize = vec2(1.0) / fwidth(uv);
    return max(0.5 * dot(unitRange, screenTexSize), 1.0);
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

    Metadata metadata = metadatas[v_MetaId];
    vec3 msd = texture(texSampler, v_UV).rgb;
    float sd = median(msd.r, msd.g, msd.b);
    float screenPxDistance = screenPxRange(v_UV, metadata.fontSize) * (sd - 0.5);
    float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);

    if(opacity == 0.0)
    discard;

    outColor = vec4(v_Color.rgb, v_Color.a * opacity);
}