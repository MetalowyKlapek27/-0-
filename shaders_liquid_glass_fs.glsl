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

uniform sampler2D texSampler;

in vec2 v_UV;
flat in vec4 v_TLColor;
flat in vec4 v_TRColor;
flat in vec4 v_BLColor;
flat in vec4 v_BRColor;
flat in int v_MetaId;
flat in int v_RenderMode;

uniform int u_ScissorCount;
uniform vec4 u_Scissor[32];
uniform vec2 screenSize;

uniform float cornerSmoothing;
uniform float scale;
uniform mat3 nodeToTileSpace;
uniform mat3 tileToNodeSpace;
uniform float refractionIntensity;
uniform float refractionDistance;
uniform float lightIntensity;
uniform float lightAngle;
uniform float bevelSize;
uniform float chromaticAberration;
uniform vec4 tintColor;

const float HALF_PI = 1.57079632679;
const int NUM_NEWTON_ITERATIONS = 2;
const int NUM_NEWTON_START_POINTS = 3;
const float NEWTON_DAMPING_FACTOR = 1.0;

float sdBox(vec2 p, vec2 halfSize) {
    vec2 d = abs(p) - halfSize;
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sdRoundBox(vec2 p, vec2 halfSize, float cornerRadius) {
    float rn = min(cornerRadius, min(halfSize.x, halfSize.y));
    return sdBox(p, halfSize - rn) - rn;
}

mat2 rot(float t) {
    float cosT = cos(t);
    float sinT = sin(t);
    return mat2(cosT, -sinT, sinT, cosT);
}

int solveCubic(float a, float b, float c, out vec3 roots) {
    float p = b - a * a / 3.0;
    float q = a * (2.0 * a * a - 9.0 * b) / 27.0 + c;
    float p3 = p * p * p;
    float discriminant = q * q + 4.0 * p3 / 27.0;
    float offset = -a / 3.0;
    if (discriminant >= 0.0) {
        float z = sqrt(discriminant);
        float u = (-q + z) / 2.0;
        float v = (-q - z) / 2.0;
        u = sign(u) * pow(abs(u), 1.0 / 3.0);
        v = sign(v) * pow(abs(v), 1.0 / 3.0);
        roots[0] = offset + u + v;
        float f = ((roots[0] + a) * roots[0] + b) * roots[0] + c;
        float f1 = (3. * roots[0] + 2. * a) * roots[0] + b;
        roots[0] -= f / f1;
        return 1;
    }
    float u = sqrt(-p / 3.0);
    float v = acos(-sqrt(-27.0 / p3) * q / 2.0) / 3.0;
    float m = cos(v), n = sin(v) * 1.732050808;
    roots[0] = offset + u * (m + m);
    roots[1] = offset - u * (n + m);
    roots[2] = offset + u * (n - m);
    vec3 f = ((roots + a) * roots + b) * roots + c;
    vec3 f1 = (3.0 * roots + 2.0 * a) * roots + b;
    roots -= f / f1;
    return 3;
}

float cubicBezierSign(vec2 uv, vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
    float cu = (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y);
    float qu = (3.0 * p0.y - 6.0 * p1.y + 3.0 * p2.y);
    float li = (-3.0 * p0.y + 3.0 * p1.y);
    float co = p0.y - uv.y;
    vec3 roots;
    int numRoots = solveCubic(qu / cu, li / cu, co / cu, roots);
    int numIntersections = 0;
    for (int i = 0; i < 3; i++) {
        if (i < numRoots) {
            if (roots[i] >= 0.0 && roots[i] <= 1.0) {
                float t = roots[i];
                float xPos = ((((-p0.x + 3. * p1.x - 3. * p2.x + p3.x) * t + (3. * p0.x - 6. * p1.x + 3. * p2.x)) * t) + (-3. * p0.x + 3. * p1.x)) * t + p0.x;
                if (xPos < uv.x) {
                    numIntersections++;
                }
            }
        }
    }
    vec2 tangStart = p0.xy - p1.xy;
    vec2 tangEnd = p2.xy - p3.xy;
    vec2 normStart = vec2(tangStart.y, -tangStart.x);
    vec2 normEnd = vec2(tangEnd.y, -tangEnd.x);
    if (p0.y < p1.y) {
        if ((uv.y <= p0.y) && (dot(uv - p0.xy, normStart) < 0.0)) {
            numIntersections++;
        }
    } else {
        if (!(uv.y <= p0.y) && !(dot(uv - p0.xy, normStart) < 0.0)) {
            numIntersections++;
        }
    }
    if (p2.y < p3.y) {
        if (!(uv.y <= p3.y) && dot(uv - p3.xy, normEnd) < 0.0) {
            numIntersections++;
        }
    } else {
        if ((uv.y <= p3.y) && !(dot(uv - p3.xy, normEnd) < 0.0)) {
            numIntersections++;
        }
    }
    if (numIntersections == 0 || numIntersections == 2 || numIntersections == 4) {
        return 1.0;
    } else {
        return -1.0;
    }
}

float cubicBezierNormalIteration(float t, vec2 a0, vec2 a1, vec2 a2, vec2 a3) {
    vec2 a_2 = a2 + t * a3;
    vec2 a_1 = a1 + t * a_2;
    vec2 b_2 = a_2 + t * a3;
    vec2 uvToP = a0 + t * a_1;
    vec2 tang = a_1 + t * b_2;
    float tanLenSq = dot(tang, tang);
    float projection = dot(tang, uvToP);
    return t - NEWTON_DAMPING_FACTOR * projection / tanLenSq;
}

float cubicBezierDistApproxSq(vec2 uv, vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
    vec2 a3 = (-p0 + 3.0 * p1 - 3.0 * p2 + p3);
    vec2 a2 = (3.0 * p0 - 6.0 * p1 + 3.0 * p2);
    vec2 a1 = (-3.0 * p0 + 3.0 * p1);
    vec2 a0 = p0 - uv;
    float d0 = 1.0e38;
    float t0 = 0.;
    float t;
    for (int i = 0; i < NUM_NEWTON_START_POINTS; i++) {
        t = t0;
        for (int j = 0; j < NUM_NEWTON_ITERATIONS; j++) {
            t = cubicBezierNormalIteration(t, a0, a1, a2, a3);
        }
        t = clamp(t, 0.0, 1.0);
        vec2 uvToP = ((a3 * t + a2) * t + a1) * t + a0;
        d0 = min(d0, dot(uvToP, uvToP));
        t0 += 1. / float(NUM_NEWTON_START_POINTS - 1);
    }
    return d0;
}

float cubicBezierDistApprox(vec2 uv, vec2 p0, vec2 p1, vec2 p2, vec2 p3) {
    return sqrt(cubicBezierDistApproxSq(uv, p0, p1, p2, p3));
}

float sdSmoothRoundCorner(vec2 uv, float radius, float smoothing) {
    float PI = 3.14159265359;
    float HALF_PI = PI * 0.5;
    float SQRT_2 = 1.41421356237;
    float bezAngle = 0.5 * HALF_PI * smoothing;
    float arcAngle = HALF_PI * (1.0 - smoothing);
    float requiredEdgeLength = (1.0 + smoothing) * radius;
    float dOverC = tan(bezAngle);
    float l = sin(arcAngle * 0.5) * radius * SQRT_2;
    float c = radius * tan(bezAngle * 0.5) * cos(bezAngle);
    float d = c * dOverC;
    float b = ((requiredEdgeLength - l) - (1.0 + dOverC) * c) / 3.0;
    float a = 2.0 * b;
    uv = rot(PI * -0.25) * uv;
    uv.x = -abs(uv.x);
    vec2 cp = uv + vec2(0.0, 1.414213) * radius;
    float angle = atan(cp.x, cp.y);
    uv = rot(PI * 0.25) * uv;
    vec2 p0 = vec2(-requiredEdgeLength, 0.0);
    vec2 p1 = p0 + vec2(a, 0.0);
    vec2 p2 = p1 + vec2(b, 0.0);
    vec2 p3 = p2 + vec2(c, -d);
    vec2 cornerCenter = uv + requiredEdgeLength;
    if (cornerCenter.x < 0.0) {
        return cornerCenter.y - requiredEdgeLength;
    } else if (abs(angle) < arcAngle * 0.5) {
        return length(cp) - radius;
    }
    float dis = cubicBezierDistApprox(uv, p0, p1, p2, p3);
    float sgn = -cubicBezierSign(uv, p0, p1, p2, p3);
    return dis * sgn;
}

float sdSmoothRoundBox(vec2 uv, vec2 halfSize, float radius, float smoothing) {
    if (radius == 0.0) {
        return sdBox(uv, halfSize);
    }
    vec2 p = abs(uv) - halfSize;
    float minHalfSize = min(halfSize.x, halfSize.y);
    float requiredLength = radius * (1.0 + smoothing);
    float overlap = max(0.0, requiredLength - minHalfSize) / radius;
    float finalSmoothing = max(0.0, smoothing - overlap);
    if (finalSmoothing == 0.0) {
        return sdRoundBox(uv, halfSize, radius);
    }
    float finalRadius = min(minHalfSize, radius);
    return sdSmoothRoundCorner(p, finalRadius, finalSmoothing);
}

float linearstep(float a, float b, float t) {
    return clamp((t - a) / max(0.00001, b - a), 0.0, 1.0);
}

vec2 nodeSpaceToExpandedTileSpacePosition(vec2 nodeSpacePosition) {
    vec2 tileSpacePosition = (nodeToTileSpace * vec3(nodeSpacePosition, 1.0)).xy;
    vec2 expandedRegionSourceSamplingPoint = ((((tileSpacePosition - 0.5) * 2.0) * scale) / 2.0) + 0.5;
    return expandedRegionSourceSamplingPoint;
}



float gaussian(float x, float sigma) {
    return exp(-0.5 * (x * x) / (sigma * sigma)) / (sigma * sqrt(6.28318530718));
}

vec4 gaussianBlur(sampler2D tex, ivec2 fragCoord, int dim, float sigma) {
    ivec2 texSize = textureSize(tex, 0);
    float half_dim = float(dim / 2);
    vec4 colorSum = vec4(0.0);
    float weightSum = 0.0;

    for (int j = 0; j < dim; ++j) {
        float y = float(j) - half_dim;
        for (int i = 0; i < dim; ++i) {
            float x = float(i) - half_dim;
            ivec2 samplePos = clamp(fragCoord + ivec2(int(x), int(y)), ivec2(0), texSize - ivec2(1));
            float w = gaussian(x, sigma) * gaussian(y, sigma);
            colorSum += texelFetch(tex, samplePos, 0) * w;
            weightSum += w;
        }
    }

    return colorSum / weightSum;
}


vec4 getRefractedTexture(vec2 refrOffset) {
    vec2 uv = gl_FragCoord.xy / screenSize;
    vec2 refractedUV = uv + refrOffset / screenSize;

    ivec2 coord = ivec2(int(refractedUV.x * screenSize.x), int(refractedUV.y * screenSize.y));
    return gaussianBlur(texSampler, coord, 41, 4.0f);
}


vec4 getRefractedTextureWithChromaticAberration(vec2 p, vec2 refrDir, float chromaAmt) {
    const int CHROMA_KERNEL_SIZE = 8;
    vec4 chromaBlurredColor = vec4(0.0, 0.0, 0.0, 0.0);
    float invKernelSize = 1.0 / float(CHROMA_KERNEL_SIZE - 1);
    float sum = 0.0;
    for (int i = 0; i < CHROMA_KERNEL_SIZE; i++) {
        float fi = float(i) * invKernelSize - 0.5;
        float window = 1.0 - abs(fi * 2.0);
        vec4 red = getRefractedTexture(refrDir + (fi + 0.5) * chromaAmt);
        vec4 green = getRefractedTexture(refrDir + fi * chromaAmt );
        vec4 blue = getRefractedTexture(refrDir + (fi - 0.5) * chromaAmt);
        float alpha = max(max(red.a, green.a), blue.a);
        chromaBlurredColor += vec4(red.r, green.g, blue.b, alpha) * window;
        sum += window;
    }
    return chromaBlurredColor / sum;
}

vec2 getGlassRectNormal(vec2 p, vec2 halfSize, float cornerRad) {
    float r = min(min(halfSize.x, halfSize.y), cornerRad);
    vec2 d = abs(p) - (halfSize - r);
    float isFlat = step(max(d.x, d.y), -bevelSize * step(cornerRad, bevelSize));
    return normalize(d + max(-min(d.x, d.y), 0.0)) * sign(p) * (1.0 - isFlat);
}

vec2 getGlassRectRefractionDir(vec2 p, vec2 halfSize, float cornerRad, float refractionDistance) {
    return getGlassRectNormal(p, halfSize, max(cornerRad, refractionDistance));
}

bool isInsideScissors() {
    //return true;
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
    vec4 vertexColor = mix(topColor, bottomColor, v_UV.y);

    vec4 v_Color = mix(bottomColor, topColor, v_UV.y);

    if (v_MetaId >= 0) {
        Metadata meta = metadatas[v_MetaId];

        vec2 nodeSpaceCenterPoint = 0.5 * meta.size;
        float cornerRadiusInPixelSpace = meta.rounding;

        vec2 nodeSpacePixelPoint = v_UV * meta.size;
        vec2 boundsSize = nodeSpaceCenterPoint * 2.0;
        vec2 halfBoundsSize = boundsSize * 0.5;
        float minHalfSize = min(halfBoundsSize.x, halfBoundsSize.y);
        vec2 boundsCenter = nodeSpaceCenterPoint;
        vec2 pBox = nodeSpacePixelPoint - nodeSpaceCenterPoint;

        float boxDist = sdSmoothRoundBox(pBox, halfBoundsSize, cornerRadiusInPixelSpace, cornerSmoothing);
        if(boxDist > 0.0) discard;
        float BEVEL_REFRACTION_MULT = 0.2;
        float REFRACTION_STRENGTH = refractionIntensity;
        float refractionDistance = min(minHalfSize, refractionDistance);
        float refrArea = linearstep(-refractionDistance - bevelSize, -bevelSize, boxDist);
        float refrMult = pow(refrArea, 3.5) * refractionDistance;
        float maxRefrOffset = 0.999 * refractionDistance;
        float dishRefrOffset = clamp(refrMult * REFRACTION_STRENGTH, -maxRefrOffset, maxRefrOffset);
        float bevelRefrOffset = REFRACTION_STRENGTH * BEVEL_REFRACTION_MULT * maxRefrOffset;
        float isBevel = linearstep(-bevelSize - 0.0001, -bevelSize * 0.3, boxDist);

        vec2 glassNormal = getGlassRectRefractionDir(pBox, halfBoundsSize, cornerRadiusInPixelSpace, refractionDistance);
        vec2 refrDir = -glassNormal * mix(dishRefrOffset, bevelRefrOffset, isBevel);
        vec2 p = nodeSpacePixelPoint;
        vec4 col = getRefractedTexture(refrDir);
        col = col * (1.0 - tintColor.a) + tintColor;

        float LIGHT_INTENSITY = lightIntensity;
        float SPECULAR_HARDNESS = 0.05;
        float halfSpecThk = bevelSize * 1;
        float rim = smoothstep(-bevelSize - 0.001, -bevelSize * SPECULAR_HARDNESS, boxDist);
        float frameRot = atan(nodeToTileSpace[1][0], nodeToTileSpace[0][0]);
        float SPECULAR_FALLOFF = 0.35;
        float BOTTOM_LIGHT_MULT = 0.6;
        float specularAngle = lightAngle + frameRot + HALF_PI;
        vec2 specularNormal = getGlassRectNormal(pBox, halfBoundsSize, cornerRadiusInPixelSpace);
        vec2 lightDir = vec2(cos(specularAngle), sin(specularAngle));
        col.xyz += smoothstep(SPECULAR_FALLOFF, 1.0, dot(specularNormal, -lightDir)) * rim * LIGHT_INTENSITY;
        col.xyz += smoothstep(SPECULAR_FALLOFF, 1.0, dot(specularNormal, lightDir)) * rim * LIGHT_INTENSITY * BOTTOM_LIGHT_MULT;

        float DISH_SHADE_STRENGTH = 0.05;
        float shadeSize = refractionDistance;
        float shadeMult = pow(linearstep(-shadeSize, -bevelSize + 0.0001, boxDist), 2.0);
        float shadeAmt = dot(glassNormal, lightDir);
        col.xyz += shadeAmt * shadeMult * DISH_SHADE_STRENGTH * LIGHT_INTENSITY;

        vec2 pixel = v_UV * meta.size;
        vec2 centre = 0.5 * meta.size;
        float distance = calc(centre - pixel, centre - meta.rounding - 1, meta.rounding);

        if(v_RenderMode == 0)
        {
            float sa = smoothstep(0.0, 1.0, distance);
            vec4 c = mix(vec4(col.rgb, 1), vec4(col.rgb, 0), sa);
            outColor = vec4(c.rgb, col.a * c.a * v_Color.a);
        } else if(v_RenderMode == 2) {
            float thickness = meta.thickness;
            float aa = fwidth(distance);

            float outer = 1.0 - smoothstep(0.0, aa, distance);
            float inner = smoothstep(-thickness - aa, -thickness + aa, distance);
            float alpha = outer * inner;

            outColor = vec4(col.rgb, col.a * alpha);
        }
    } else {
        discard;
    }
}