#version 430 core

in vec3 inPos;
in vec2 inUV;
in vec4 inColor;

uniform mat4 viewMatrix;
uniform mat4 projectionMatrix;

out vec2 texCoord;
out vec4 color;

void main() {
    gl_Position = projectionMatrix * viewMatrix * vec4(inPos, 1.0);
    texCoord = inUV;
    color = inColor;
}