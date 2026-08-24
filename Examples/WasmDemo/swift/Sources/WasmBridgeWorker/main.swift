import JavaScriptEventLoop
import JavaScriptKit
import WasmBridgeCore

JavaScriptEventLoop.installGlobalExecutor()

private let uint8ArrayConstructor = JSObject.global.Uint8Array.function!

private func validInteger(_ value: JSValue) -> Int? {
    guard let number = value.number,
          number.isFinite,
          number.rounded(.towardZero) == number,
          number >= 0,
          number <= Double(Int.max) else {
        return nil
    }
    return Int(number)
}

@MainActor
private func postFailure(jobId: Int, message: String) {
    let result = JSObject.global.Object.function!.new()
    result["type"] = .string("failure")
    result["jobId"] = .number(Double(jobId))
    result["message"] = .string(message)
    _ = JSObject.global.postMessage!(result)
}

@MainActor
private func postSuccess(jobId: Int, response: ResizeRGBA8Response) {
    let result = JSObject.global.Object.function!.new()
    let output = uint8ArrayConstructor.new(response.pixels.count)
    for (index, byte) in response.pixels.enumerated() {
        output[index] = .number(Double(byte))
    }
    result["type"] = .string("success")
    result["jobId"] = .number(Double(jobId))
    result["width"] = .number(Double(response.width))
    result["height"] = .number(Double(response.height))
    result["pixels"] = output.buffer
    _ = JSObject.global.postMessage!(result)
}

@MainActor
private func request(from event: JSValue) -> (jobId: Int, request: ResizeRGBA8Request)? {
    guard let data = event.object?.data.object,
          data.type.string == "resize",
          let jobId = validInteger(data.jobId),
          let sourceWidth = validInteger(data.sourceWidth),
          let sourceHeight = validInteger(data.sourceHeight),
          let targetWidth = validInteger(data.targetWidth),
          let targetHeight = validInteger(data.targetHeight),
          let inputBuffer = data.pixels.object else {
        return nil
    }

    let input = uint8ArrayConstructor.new(inputBuffer)
    guard let count = validInteger(input.length) else { return nil }
    var pixels = [UInt8]()
    pixels.reserveCapacity(count)
    for index in 0..<count {
        guard let value = input[index].number, value >= 0, value <= 255 else { return nil }
        pixels.append(UInt8(value))
    }

    return (jobId, ResizeRGBA8Request(
        pixels: pixels,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        targetWidth: targetWidth,
        targetHeight: targetHeight
    ))
}

let messageHandler = JSClosure { arguments in
    guard let event = arguments.first, let parsed = request(from: event) else {
        return .undefined
    }
    Task { @MainActor in
        do {
            let response = try await resizeRGBA8(parsed.request)
            postSuccess(jobId: parsed.jobId, response: response)
        } catch {
            postFailure(jobId: parsed.jobId, message: String(describing: error))
        }
    }
    return .undefined
}
JSObject.global.onmessage = .object(messageHandler)

let readyMessage = JSObject.global.Object.function!.new()
readyMessage["type"] = .string("ready")
readyMessage["jobId"] = .number(0)
_ = JSObject.global.postMessage!(readyMessage)
