#version 450

layout(local_size_x = 16, local_size_y = 16) in;

layout(binding = 0, rgba8) uniform readonly image2D inputImage;
layout(binding = 1, rgba8) uniform writeonly image2D outputImage;
layout(binding = 2, rgba8) uniform readonly image2D maskImage;

uniform int u_useMask;
uniform int u_offset;
uniform vec2 u_resolution;

void main() {
    ivec2 texelCoord = ivec2(gl_GlobalInvocationID.xy);

    if (texelCoord.x >= int(u_resolution.x) || texelCoord.y >= int(u_resolution.y)) {
        return;
    }

    float maskAlpha = imageLoad(maskImage, texelCoord).a;

    if(u_useMask == 1)
    {
        if (maskAlpha <= 0.0) {
            imageStore(outputImage, texelCoord, imageLoad(inputImage, texelCoord));
            return;
        }
    } else {
        imageStore(outputImage, texelCoord, imageLoad(inputImage, texelCoord));
    }

    vec4 color = vec4(0.0);
    int count = 0;

    ivec2 offsets[4] = ivec2[4](
    ivec2( u_offset,  u_offset),
    ivec2(-u_offset,  u_offset),
    ivec2( u_offset, -u_offset),
    ivec2(-u_offset, -u_offset)
    );

    for (int i = 0; i < 4; i++) {
        ivec2 coord = texelCoord + offsets[i];
        coord = clamp(coord, ivec2(0), ivec2(u_resolution) - ivec2(1));
        color += imageLoad(inputImage, coord);
        count++;
    }

    color /= float(count);
    imageStore(outputImage, texelCoord, color);
}