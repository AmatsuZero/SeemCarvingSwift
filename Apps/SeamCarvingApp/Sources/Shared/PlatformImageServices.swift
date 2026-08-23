import Foundation

#if os(iOS)
import UIKit

/// UIKit image conversion shared by iPhone, iPad, and Mac Catalyst.
///
/// Presentation remains in SwiftUI (`PhotosPicker`, `fileImporter`, and
/// `ShareLink`); this adapter keeps UIKit image types out of the model/view
/// boundary and gives all three Apple UI surfaces the same conversion path.
enum PlatformImageServices {
    static func imageSource(from image: UIImage) -> ImageSource {
        .uiImage(image)
    }
}
#endif
