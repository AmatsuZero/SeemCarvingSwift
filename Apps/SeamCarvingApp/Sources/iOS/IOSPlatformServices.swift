import Foundation
import UIKit

/// UIKit adapters shared by iPhone, iPad, and Mac Catalyst.
enum ApplePlatformServices {
    static func imageSource(from image: UIImage) -> ImageSource {
        .uiImage(image)
    }

}
