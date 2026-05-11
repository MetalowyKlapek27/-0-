#version 430 core

in vec2 texCoord;
in vec4 color;

out vec4 fragColor;

void main() {
    vec2 uv = texCoord - 0.5;

    float dist = length(uv);
    float radius = 0.3;
    float thickness = 0.03;
    float blurSize = 0.05;

    float d = abs(dist - radius);

    float outline = 1.0 - smoothstep(thickness - blurSize,
                                     thickness + blurSize,
                                     d);

    vec3 outlineColor = color.rgb;
    fragColor = vec4(outlineColor * outline, outline);
}