/** WGSL compute stages for one backward-Sobel vertical seam removal. */
const header = /* wgsl */ `
struct Parameters {
  width: u32,
  height: u32,
  row: u32,
  _padding: u32,
};

@group(0) @binding(2) var<uniform> parameters: Parameters;
`;

/** Converts packed RGBA8 pixels to the Core backend's linear BT.709 luma. */
export const rgbaToLumaWGSL = /* wgsl */ `
${header}
@group(0) @binding(0) var<storage, read> inputPixels: array<u32>;
@group(0) @binding(1) var<storage, read_write> luma: array<f32>;

fn srgbToLinear(component: f32) -> f32 {
  if (component <= 0.04045) { return component / 12.92; }
  return pow((component + 0.055) / 1.055, 2.4);
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) invocation: vec3<u32>) {
  let index = invocation.x;
  if (index >= parameters.width * parameters.height) { return; }
  let pixel = inputPixels[index];
  let r = srgbToLinear(f32(pixel & 0xffu) / 255.0);
  let g = srgbToLinear(f32((pixel >> 8u) & 0xffu) / 255.0);
  let b = srgbToLinear(f32((pixel >> 16u) & 0xffu) / 255.0);
  luma[index] = 0.2126 * r + 0.7152 * g + 0.0722 * b;
}`;

/** Clamp-to-edge, symmetric-difference Sobel energy, matching BackwardEnergy. */
export const sobelWGSL = /* wgsl */ `
${header}
@group(0) @binding(0) var<storage, read> luma: array<f32>;
@group(0) @binding(1) var<storage, read_write> energy: array<f32>;

fn sampleClamped(x: i32, y: i32) -> f32 {
  let sx = u32(clamp(x, 0, i32(parameters.width) - 1));
  let sy = u32(clamp(y, 0, i32(parameters.height) - 1));
  return luma[sy * parameters.width + sx];
}

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) invocation: vec3<u32>) {
  let index = invocation.x;
  if (index >= parameters.width * parameters.height) { return; }
  let x = i32(index % parameters.width);
  let y = i32(index / parameters.width);
  let gx = (sampleClamped(x + 1, y - 1) - sampleClamped(x - 1, y - 1))
    + 2.0 * (sampleClamped(x + 1, y) - sampleClamped(x - 1, y))
    + (sampleClamped(x + 1, y + 1) - sampleClamped(x - 1, y + 1));
  let gy = (sampleClamped(x - 1, y + 1) - sampleClamped(x - 1, y - 1))
    + 2.0 * (sampleClamped(x, y + 1) - sampleClamped(x, y - 1))
    + (sampleClamped(x + 1, y + 1) - sampleClamped(x + 1, y - 1));
  energy[index] = abs(gx) + abs(gy);
}`;

/** Seeds the two-row dynamic-programming state with Sobel's first row. */
export const initializeDPWGSL = /* wgsl */ `
${header}
@group(0) @binding(0) var<storage, read> energy: array<f32>;
@group(0) @binding(1) var<storage, read_write> row: array<f32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) invocation: vec3<u32>) {
  let x = invocation.x;
  if (x >= parameters.width) { return; }
  row[x] = energy[x];
}`;

/** Accumulates exactly one row, retaining left-center-right tie order. */
export const accumulateDPWGSL = /* wgsl */ `
${header}
@group(0) @binding(0) var<storage, read> previous: array<f32>;
@group(0) @binding(1) var<storage, read_write> current: array<f32>;
@group(0) @binding(2) var<storage, read_write> parents: array<i32>;
@group(0) @binding(3) var<storage, read> energy: array<f32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) invocation: vec3<u32>) {
  let x = invocation.x;
  if (x >= parameters.width) { return; }
  let leftX = select(x - 1u, 0u, x == 0u);
  let rightX = select(x + 1u, parameters.width - 1u, x + 1u >= parameters.width);
  var best = previous[leftX];
  var predecessor = leftX;
  if (previous[x] < best) {
    best = previous[x];
    predecessor = x;
  }
  if (previous[rightX] < best) {
    best = previous[rightX];
    predecessor = rightX;
  }
  current[x] = energy[parameters.row * parameters.width + x] + best;
  parents[parameters.row * parameters.width + x] = i32(predecessor) - i32(x);
}`;

/** Serial final-row argmin: the first equal minimum wins. */
export const reduceWGSL = /* wgsl */ `
${header}
@group(0) @binding(0) var<storage, read> row: array<f32>;
@group(0) @binding(1) var<storage, read_write> argmin: array<u32>;

@compute @workgroup_size(1)
fn main() {
  var best = bitcast<f32>(0x7f800000u);
  var bestX = 0u;
  for (var x = 0u; x < parameters.width; x = x + 1u) {
    if (row[x] < best) {
      best = row[x];
      bestX = x;
    }
  }
  argmin[0] = bestX;
}`;

/** Walks the signed parent deltas from the final row to form the seam. */
export const backtrackWGSL = /* wgsl */ `
${header}
@group(0) @binding(0) var<storage, read> parents: array<i32>;
@group(0) @binding(1) var<storage, read_write> seam: array<u32>;
@group(0) @binding(2) var<storage, read> argmin: array<u32>;

@compute @workgroup_size(1)
fn main() {
  var x = argmin[0];
  seam[parameters.height - 1u] = x;
  for (var y = parameters.height - 1u; y > 0u; y = y - 1u) {
    x = u32(i32(x) + parents[y * parameters.width + x]);
    seam[y - 1u] = x;
  }
}`;

/** Gathers every packed RGBA8 pixel except the selected vertical seam. */
export const removeVerticalWGSL = /* wgsl */ `
${header}
@group(0) @binding(0) var<storage, read> inputPixels: array<u32>;
@group(0) @binding(1) var<storage, read_write> outputPixels: array<u32>;
@group(0) @binding(2) var<storage, read> seam: array<u32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) invocation: vec3<u32>) {
  let index = invocation.x;
  let outputWidth = parameters.width - 1u;
  if (index >= outputWidth * parameters.height) { return; }
  let x = index % outputWidth;
  let y = index / outputWidth;
  let sourceX = select(x, x + 1u, x >= seam[y]);
  outputPixels[index] = inputPixels[y * parameters.width + sourceX];
}`;
