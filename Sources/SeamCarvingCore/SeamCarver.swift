public struct SeamCarver: Sendable {
    private let backend: any SeamCarvingBackend

    public init() {
        self.backend = CPUBackend()
    }

    @_spi(Backend)
    public init(backend: any SeamCarvingBackend) {
        self.backend = backend
    }

    public func resize(
        _ image: RGBA8Image,
        to target: PixelSize,
        options: ResizeOptions = .init()
    ) async throws -> RGBA8Image {
        try await backend.resize(image, to: target, options: options)
    }
}
