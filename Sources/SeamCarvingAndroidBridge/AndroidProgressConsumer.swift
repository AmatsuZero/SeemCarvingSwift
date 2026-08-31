import SwiftJava

// swift-java 0.2.0 emits an escaping-closure upcall that refers to this
// projection but does not synthesize the projection itself. Keep this private
// shim beside the bridge until the pinned generator supplies it.
enum JavaAndroidResizeOperation {
    enum resize {
        @JavaInterface("io.github.seamcarving.AndroidResizeOperation$resize$progress")
        struct progress {
            @JavaMethod
            func apply(_ completed: Int32, _ total: Int32, _ width: Int32, _ height: Int32) -> Bool
        }
    }
}
