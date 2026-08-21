#include <metal_stdlib>
using namespace metal;

// MARK: - Color transfer helpers

inline float srgbToLinear(float c) {
    c = clamp(c, 0.0f, 1.0f);
    if (c <= 0.04045f) { return c / 12.92f; }
    return pow((c + 0.055f) / 1.055f, 2.4f);
}

inline float linearToSRGB(float c) {
    c = clamp(c, 0.0f, 1.0f);
    if (c <= 0.0031308f) { return 12.92f * c; }
    return 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
}

inline uchar encodeSRGB(float c) {
    return uchar(round(clamp(linearToSRGB(c), 0.0f, 1.0f) * 255.0f));
}

inline float sampleClamped(device const float* luma, uint width, uint height, int x, int y) {
    x = clamp(x, 0, int(width - 1));
    y = clamp(y, 0, int(height - 1));
    return luma[uint(y) * width + uint(x)];
}

// MARK: - Energy

kernel void rgbaPassthrough(device const uchar4* input  [[buffer(0)]],
                            device uchar4* output        [[buffer(1)]],
                            constant uint2& size         [[buffer(2)]],
                            uint index                   [[thread_position_in_grid]]) {
    if (index >= size.x * size.y) { return; }
    output[index] = input[index];
}

kernel void rgbaToLinearLuma(device const uchar4* input [[buffer(0)]],
                             device float* luma          [[buffer(1)]],
                             uint index                   [[thread_position_in_grid]]) {
    uchar4 px = input[index];
    float lr = srgbToLinear(float(px.r) / 255.0f);
    float lg = srgbToLinear(float(px.g) / 255.0f);
    float lb = srgbToLinear(float(px.b) / 255.0f);
    luma[index] = 0.2126f * lr + 0.7152f * lg + 0.0722f * lb;
}

kernel void sobelEnergy(device const float* luma  [[buffer(0)]],
                        device float* energy       [[buffer(1)]],
                        constant uint2& size       [[buffer(2)]],
                        uint2 gid                  [[thread_position_in_grid]]) {
    uint x = gid.x;
    uint y = gid.y;
    if (x >= size.x || y >= size.y) { return; }
    int ix = int(x);
    int iy = int(y);
    // Symmetric-difference form of the 3x3 Sobel.
    float gx = (sampleClamped(luma, size.x, size.y, ix + 1, iy - 1) - sampleClamped(luma, size.x, size.y, ix - 1, iy - 1))
             + 2.0f * (sampleClamped(luma, size.x, size.y, ix + 1, iy) - sampleClamped(luma, size.x, size.y, ix - 1, iy))
             + (sampleClamped(luma, size.x, size.y, ix + 1, iy + 1) - sampleClamped(luma, size.x, size.y, ix - 1, iy + 1));
    float gy = (sampleClamped(luma, size.x, size.y, ix - 1, iy + 1) - sampleClamped(luma, size.x, size.y, ix - 1, iy - 1))
             + 2.0f * (sampleClamped(luma, size.x, size.y, ix, iy + 1) - sampleClamped(luma, size.x, size.y, ix, iy - 1))
             + (sampleClamped(luma, size.x, size.y, ix + 1, iy + 1) - sampleClamped(luma, size.x, size.y, ix + 1, iy - 1));
    energy[y * size.x + x] = fabs(gx) + fabs(gy);
}

struct MaskParams {
    uint pixelCount;
    uint softCount;
    uint hardCount;
    uint hasRemoval;
    float removalWeight;
};

kernel void applyMasks(device const float* base        [[buffer(0)]],
                       device float* output            [[buffer(1)]],
                       device const float* softMasks   [[buffer(2)]],
                       device const float* softWeights [[buffer(3)]],
                       device const float* hardMasks   [[buffer(4)]],
                       device const float* removal     [[buffer(5)]],
                       constant MaskParams& params     [[buffer(6)]],
                       uint index                      [[thread_position_in_grid]]) {
    if (index >= params.pixelCount) { return; }
    float v = base[index];
    for (uint i = 0; i < params.softCount; i++) {
        v += softWeights[i] * softMasks[i * params.pixelCount + index];
    }
    for (uint i = 0; i < params.hardCount; i++) {
        if (hardMasks[i * params.pixelCount + index] > 0.0f) {
            v = INFINITY;
        }
    }
    if (params.hasRemoval != 0u && isfinite(v)) {
        v -= params.removalWeight * removal[index];
    }
    output[index] = v;
}

// MARK: - Seam editing

kernel void removeVerticalRGBA(device const uchar4* input [[buffer(0)]],
                               device uchar4* output      [[buffer(1)]],
                               device const uint* seam    [[buffer(2)]],
                               constant uint2& size       [[buffer(3)]],
                               uint2 gid                  [[thread_position_in_grid]]) {
    uint x = gid.x;
    uint y = gid.y;
    if (x >= size.x - 1 || y >= size.y) { return; }
    uint sx = (x >= seam[y]) ? (x + 1) : x;
    output[y * (size.x - 1) + x] = input[y * size.x + sx];
}

kernel void removeVerticalMask(device const float* input [[buffer(0)]],
                               device float* output      [[buffer(1)]],
                               device const uint* seam   [[buffer(2)]],
                               constant uint2& size      [[buffer(3)]],
                               uint2 gid                 [[thread_position_in_grid]]) {
    uint x = gid.x;
    uint y = gid.y;
    if (x >= size.x - 1 || y >= size.y) { return; }
    uint sx = (x >= seam[y]) ? (x + 1) : x;
    output[y * (size.x - 1) + x] = input[y * size.x + sx];
}

// Positions are pre-sorted per row: positions[y * count + k].
kernel void insertMappedVerticalRGBA(device const uchar4* input  [[buffer(0)]],
                                     device uchar4* output       [[buffer(1)]],
                                     device const uint* positions [[buffer(2)]],
                                     constant uint& count         [[buffer(3)]],
                                     constant uint2& size         [[buffer(4)]],
                                     uint y                       [[thread_position_in_grid]]) {
    if (y >= size.y) { return; }
    uint outX = 0;
    for (uint x = 0; x < size.x; x++) {
        output[y * (size.x + count) + outX++] = input[y * size.x + x];
        for (uint k = 0; k < count; k++) {
            if (positions[y * count + k] == x) {
                uint rx = min(x + 1, size.x - 1);
                uchar4 a = input[y * size.x + x];
                uchar4 b = input[y * size.x + rx];
                uchar r = encodeSRGB((srgbToLinear(float(a.r) / 255.0f) + srgbToLinear(float(b.r) / 255.0f)) / 2.0f);
                uchar g = encodeSRGB((srgbToLinear(float(a.g) / 255.0f) + srgbToLinear(float(b.g) / 255.0f)) / 2.0f);
                uchar bl = encodeSRGB((srgbToLinear(float(a.b) / 255.0f) + srgbToLinear(float(b.b) / 255.0f)) / 2.0f);
                uchar al = uchar((uint(a.a) + uint(b.a) + 1u) / 2u);
                output[y * (size.x + count) + outX++] = uchar4(r, g, bl, al);
            }
        }
    }
}

kernel void insertMappedVerticalMask(device const float* input  [[buffer(0)]],
                                     device float* output        [[buffer(1)]],
                                     device const uint* positions [[buffer(2)]],
                                     constant uint& count         [[buffer(3)]],
                                     constant uint2& size         [[buffer(4)]],
                                     uint y                       [[thread_position_in_grid]]) {
    if (y >= size.y) { return; }
    uint outX = 0;
    for (uint x = 0; x < size.x; x++) {
        output[y * (size.x + count) + outX++] = input[y * size.x + x];
        for (uint k = 0; k < count; k++) {
            if (positions[y * count + k] == x) {
                uint rx = min(x + 1, size.x - 1);
                float avg = (input[y * size.x + x] + input[y * size.x + rx]) / 2.0f;
                output[y * (size.x + count) + outX++] = avg;
            }
        }
    }
}

// MARK: - Transpose

kernel void transposeRGBA(device const uchar4* input [[buffer(0)]],
                          device uchar4* output      [[buffer(1)]],
                          constant uint2& size       [[buffer(2)]],
                          uint2 gid                  [[thread_position_in_grid]]) {
    uint i = gid.y;  // output row in [0, size.x)
    uint j = gid.x;  // output col in [0, size.y)
    if (i >= size.x || j >= size.y) { return; }
    output[i * size.y + j] = input[j * size.x + i];
}

kernel void transposeMask(device const float* input [[buffer(0)]],
                          device float* output      [[buffer(1)]],
                          constant uint2& size      [[buffer(2)]],
                          uint2 gid                 [[thread_position_in_grid]]) {
    uint i = gid.y;
    uint j = gid.x;
    if (i >= size.x || j >= size.y) { return; }
    output[i * size.y + j] = input[j * size.x + i];
}

kernel void transposeUInt32IndexMap(device const uint* input [[buffer(0)]],
                                    device uint* output      [[buffer(1)]],
                                    constant uint2& size     [[buffer(2)]],
                                    uint2 gid                [[thread_position_in_grid]]) {
    uint i = gid.y;
    uint j = gid.x;
    if (i >= size.x || j >= size.y) { return; }
    output[i * size.y + j] = input[j * size.x + i];
}
