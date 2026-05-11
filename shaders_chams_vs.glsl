#version 150

in vec3 Position;
in vec2 TexCoord;
in vec4 Color;
in vec3 Normal;

uniform mat4 modelView;
uniform mat4 projection;

out vec4 vertexColor;
out vec2 texCoord;

void main() {
    gl_Position = projection * modelView * vec4(Position, 1.0);
    texCoord = TexCoord;
    vertexColor = Color;
}