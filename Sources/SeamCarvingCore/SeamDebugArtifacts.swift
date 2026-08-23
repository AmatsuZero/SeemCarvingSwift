public enum SeamObservationKind: String, Sendable, Equatable, Codable {
    case remove
    case insert
}

/// A typed observation emitted at the point a seam is selected for an edit.
///
/// Coordinate contract:
/// - `imageBeforeEdit` is the exact current image immediately before this seam
///   is applied.
/// - Coordinates are top-left origin in that current image.
/// - For vertical seams, `coordinates[y]` is the x-coordinate in row `y`.
/// - For horizontal seams, `coordinates[x]` is the y-coordinate in column `x`.
public struct SeamObservation: Sendable, Equatable {
    public let index: Int
    public let totalCount: Int
    public let kind: SeamObservationKind
    public let seam: SeamPath
    public let imageBeforeEdit: RGBA8Image

    public init(
        index: Int,
        totalCount: Int,
        kind: SeamObservationKind,
        seam: SeamPath,
        imageBeforeEdit: RGBA8Image
    ) {
        self.index = index
        self.totalCount = totalCount
        self.kind = kind
        self.seam = seam
        self.imageBeforeEdit = imageBeforeEdit
    }
}
