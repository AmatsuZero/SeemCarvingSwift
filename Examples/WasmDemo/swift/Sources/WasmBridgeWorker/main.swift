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
private func postableSuccess(jobId: Int, response: ResizeRGBA8Response) -> JSValue {
    let result = JSObject.global.Object.function!.new()
    let output = uint8ArrayConstructor.new(response.pixels.count)
    for (index, byte) in response.pixels.enumerated() {
        output[index] = .number(Double(byte))
    }
    result["type"] = .string("success")
    result["backend"] = .string("wasm-cpu")
    result["jobId"] = .number(Double(jobId))
    result["width"] = .number(Double(response.width))
    result["height"] = .number(Double(response.height))
    result["pixels"] = output.buffer
    return .object(result)
}

@MainActor
private func request(from value: JSValue) -> (jobId: Int, request: ResizeRGBA8Request)? {
    guard let data = value.object,
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

let wasmResize = JSClosure { arguments in
    guard let value = arguments.first, let parsed = request(from: value) else {
        return JSPromise.reject(JSValue.string("Invalid resize request")).jsValue()
    }
    return JSPromise(resolver: { completion in
        Task { @MainActor in
            do {
                let response = try await resizeRGBA8(parsed.request)
                completion(.success(postableSuccess(jobId: parsed.jobId, response: response)))
            } catch {
                completion(.failure(.string(String(describing: error))))
            }
        }
    }).jsValue()
}
JSObject.global.__seamCarvingWasmResize = .object(wasmResize)

let readyMessage = JSObject.global.Object.function!.new()
readyMessage["type"] = .string("ready")
readyMessage["jobId"] = .number(0)
_ = JSObject.global.postMessage!(readyMessage)
