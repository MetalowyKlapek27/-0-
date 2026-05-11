#version 430 core

uniform sampler2D textureSampler;

in vec2 texCoord;
in vec4 color;

uniform float glowIntensity;

out vec4 fragColor;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

void main() {
    vec3 msdf = texture(textureSampler, texCoord).rgb;
    float sd = median(msdf.r, msdf.g, msdf.b) - 0.5;

    float pxDist = 16.0 * sd;

    float alpha = clamp(pxDist + 0.5, 0.0, 1.0);

    float glowRadius = 8.0;
    float glowAlpha = smoothstep(glowRadius, 0.0, abs(pxDist));

    vec3 glowColor = color.rgb * glowIntensity;

    vec3 finalColor = mix(glowColor, color.rgb, alpha);
    float finalAlpha = max(alpha, glowAlpha * 0.5);

    fragColor = vec4(finalColor, finalAlpha * color.a);
}