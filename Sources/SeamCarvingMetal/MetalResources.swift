import Foundation
@preconcurrency import Metal

enum MetalResources {
    /// Creates a buffer from a byte array.
    static func makeBuffer(_ device: any MTLDevice, bytes: [UInt8]) -> any MTLBuffer {
        device.makeBuffer(bytes: bytes, length: bytes.count)!
    }
}
