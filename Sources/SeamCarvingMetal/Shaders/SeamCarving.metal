#include <metal_stdlib>
using namespace metal;

kernel void rgbaPassthrough(device const uchar4* input  [[buffer(0)]],
                            device uchar4* output        [[buffer(1)]],
                            constant uint2& size         [[buffer(2)]],
                            uint index                   [[thread_position_in_grid]]) {
    if (index >= size.x * size.y) { return; }
    output[index] = input[index];
}
