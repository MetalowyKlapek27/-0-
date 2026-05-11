#version 450

layout(local_size_x = 128, local_size_y = 1, local_size_z = 1) in;

layout(binding = 0, rgba8) uniform readonly image2D inputImage;
layout(binding = 1, rgba8) uniform writeonly image2D outputImage;
layout(binding = 2, rgba8) uniform readonly image2D maskImage;

#define BLUR_RADIUS 8
            #define TILE_SIZE 128
            #define CACHE_SIZE (TILE_SIZE + 2 * BLUR_RADIUS)

shared vec4 sharedCache[CACHE_SIZE];
shared float maskCache[CACHE_SIZE];

const float weights[9] = float[](
0.0545, 0.0540, 0.0525, 0.0498, 0.0462, 0.0418, 0.0367, 0.0312, 0.0257
);

void main() {
    ivec2 imageSize = imageSize(inputImage);
    int y = int(gl_GlobalInvocationID.y);
    int localX = int(gl_LocalInvocationID.x);
    int globalX = int(gl_WorkGroupID.x * TILE_SIZE + localX);

    if (y >= imageSize.y || globalX >= imageSize.x) return;

    int baseX = int(gl_WorkGroupID.x) * TILE_SIZE;
    int loadX = baseX + localX;
    int clampedLoadX = clamp(loadX, 0, imageSize.x - 1);

    sharedCache[BLUR_RADIUS + localX] = imageLoad(inputImage, ivec2(clampedLoadX, y));
    maskCache[BLUR_RADIUS + localX] = imageLoad(maskImage, ivec2(clampedLoadX, y)).a;

    if (localX < BLUR_RADIUS) {
        int haloX = baseX - BLUR_RADIUS + localX;
        int clampedHaloX = clamp(haloX, 0, imageSize.x - 1);
        sharedCache[localX] = imageLoad(inputImage, ivec2(clampedHaloX, y));
        maskCache[localX] = imageLoad(maskImage, ivec2(clampedHaloX, y)).a;

        haloX = baseX + TILE_SIZE + localX;
        clampedHaloX = clamp(haloX, 0, imageSize.x - 1);
        sharedCache[BLUR_RADIUS + TILE_SIZE + localX] = imageLoad(inputImage, ivec2(clampedHaloX, y));
        maskCache[BLUR_RADIUS + TILE_SIZE + localX] = imageLoad(maskImage, ivec2(clampedHaloX, y)).a;
    }

    barrier();

    vec4 original = sharedCache[BLUR_RADIUS + localX];
    float mask = maskCache[BLUR_RADIUS + localX];

    vec4 result = original;
    if (mask > 0.0) {
        float weightSum = 0.0;
        result = vec4(0.0);

        for (int i = -BLUR_RADIUS; i <= BLUR_RADIUS; i++) {
            int idx = BLUR_RADIUS + localX + i;
            float neighborMask = maskCache[idx];
            float w = weights[abs(i)] * neighborMask;
            result += sharedCache[idx] * w;
            weightSum += w;
        }

        if (weightSum > 0.0) {
            result /= weightSum;
            result = mix(original, result, mask);
        }
    }

    imageStore(outputImage, ivec2(globalX, y), result);
}