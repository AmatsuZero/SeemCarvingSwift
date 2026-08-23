#if !os(macOS)
import Foundation

@main
enum UnsupportedCLIPlatform {
    static func main() async {
        FileHandle.standardError.write(
            Data("seamcarve-cli is available only on macOS\n".utf8)
        )
    }
}
#endif
