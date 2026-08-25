# @seemcarving/wasm

WebAssembly package for [SeamCarvingSwift](https://github.com/samzhangjy/SeamCarvingSwift).

```ts
import { createSeamCarver } from "@seemcarving/wasm";

const carver = await createSeamCarver();
const result = await carver.resize({ pixels, width, height, targetWidth, targetHeight });
carver.terminate();
```

`resize` runs in an isolated module Worker and currently uses the Swift/WASM CPU
backend (`"wasm-cpu"`). A request transfers a copy of its RGBA buffer, so the
caller retains ownership of its input. Only one request may be active per
carver; call `terminate()` to reject the active request and release its Worker.

## License

UNLICENSED. This package does not grant reuse rights until the repository publishes a license.
