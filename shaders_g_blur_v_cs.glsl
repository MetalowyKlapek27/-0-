#version 450

layout(local_size_x = 16, local_size_y = 8, local_size_z = 1) in;

layout(binding = 0, rgba8) uniform readonly image2D inputImage;
layout(binding = 1, rgba8) uniform writeonly image2D outputImage;
layout(binding = 2, rgba8) uniform readonly image2D maskImage;

#define BLUR_RADIUS 8
            #define TILE_SIZE 8
            #define CACHE_SIZE (TILE_SIZE + 2 * BLUR_RADIUS)

shared vec4 sharedCache[CACHE_SIZE][16];
shared float maskCache[CACHE_SIZE][16];

const float weights[9] = float[](
0.0545, 0.0540, 0.0525, 0.0498, 0.0462, 0.0418, 0.0367, 0.0312, 0.0257
);

void main() {
    ivec2 imageSize = imageSize(inputImage);
    ivec2 globalID = ivec2(gl_GlobalInvocationID.xy);
    ivec2 localID = ivec2(gl_LocalInvocationID.xy);
    ivec2 workGroupID = ivec2(gl_WorkGroupID.xy);

    int x = globalID.x;
    int localY = localID.y;
    int globalY = workGroupID.y * TILE_SIZE + localY;

    if (x >= imageSize.x || globalY >= imageSize.y) return;

    int baseY = workGroupID.y * TILE_SIZE;
    int loadY = baseY + localY;
    int clampedLoadY = clamp(loadY, 0, imageSize.y - 1);

    sharedCache[BLUR_RADIUS + localY][localID.x] = imageLoad(inputImage, ivec2(x, clampedLoadY));
    maskCache[BLUR_RADIUS + localY][localID.x] = imageLoad(maskImage, ivec2(x, clampedLoadY)).a;

    if (localY < BLUR_RADIUS) {
        int haloY = baseY - BLUR_RADIUS + localY;
        int clampedHaloY = clamp(haloY, 0, imageSize.y - 1);
        sharedCache[localY][localID.x] = imageLoad(inputImage, ivec2(x, clampedHaloY));
        maskCache[localY][localID.x] = imageLoad(maskImage, ivec2(x, clampedHaloY)).a;

        haloY = baseY + TILE_SIZE + localY;
        clampedHaloY = clamp(haloY, 0, imageSize.y - 1);
        sharedCache[BLUR_RADIUS + TILE_SIZE + localY][localID.x] = imageLoad(inputImage, ivec2(x, clampedHaloY));
        maskCache[BLUR_RADIUS + TILE_SIZE + localY][localID.x] = imageLoad(maskImage, ivec2(x, clampedHaloY)).a;
    }

    barrier();

    vec4 original = sharedCache[BLUR_RADIUS + localY][localID.x];
    float mask = maskCache[BLUR_RADIUS + localY][localID.x];

    vec4 result = original;
    if (mask > 0.0) {
        float weightSum = 0.0;
        result = vec4(0.0);

        for (int i = -BLUR_RADIUS; i <= BLUR_RADIUS; i++) {
            int idx = BLUR_RADIUS + localY + i;
            float neighborMask = maskCache[idx][localID.x];
            float w = weights[abs(i)] * neighborMask;
            result += sharedCache[idx][localID.x] * w;
            weightSum += w;
        }

        if (weightSum > 0.0) {
            result /= weightSum;
            result = mix(original, result, mask);
        }
    }

    imageStore(outputImage, ivec2(x, globalY), result);
}