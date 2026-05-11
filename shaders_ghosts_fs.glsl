#version 430 core

in vec2 texCoord;
in vec4 color;

out vec4 fragColor;

void main() {

    vec2 p = (texCoord - 0.5) * 2.0;

    float radius    = 0.005;
    float glowSize  = 1.5;
    float softness  = 0.005;

    float dist = length(p) - radius;

    float fillAlpha = 1.0 - smoothstep(-softness, softness, dist);

    float glow = pow(clamp(1.0 - dist / glowSize, 0.0, 1.0), 2.0);


    vec3 col = color.rgb * fillAlpha + color.rgb * 1.2 * glow;
    float alpha = max(fillAlpha, glow * 0.9);

    fragColor = vec4(col, alpha);
}