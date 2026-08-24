import JavaScriptEventLoop
import JavaScriptKit

JavaScriptEventLoop.installGlobalExecutor()

let messageHandler = JSClosure { _ in
    .undefined
}
JSObject.global.onmessage = .object(messageHandler)

let readyMessage = JSObject.global.Object.object!.new()
readyMessage["type"] = "ready"
_ = JSObject.global["postMessage"]!(readyMessage)
