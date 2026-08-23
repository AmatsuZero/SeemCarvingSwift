import Foundation
import UIKit

/// UIKit adapters kept separate from the shared editor. PhotosPicker and
/// UIDocumentPicker presentation remain owned by the eventual iOS shell.
enum IOSPlatformServices {
    static func imageSource(from image: UIImage) -> ImageSource {
        .uiImage(image)
    }

    static func exportData(_ data: Data) -> Data {
        // The shell can pass this value to a UIActivityViewController or a
        // UIDocumentPicker without making the shared model UIKit-dependent.
        data
    }
}
