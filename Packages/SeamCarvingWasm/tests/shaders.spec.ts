import { describe, expect, it } from "vitest";
import {
  accumulateDPWGSL,
  backtrackWGSL,
  initializeDPWGSL,
  reduceWGSL,
  removeVerticalWGSL,
  rgbaToLumaWGSL,
  sobelWGSL,
} from "../src/shaders.js";

describe("one-seam WGSL bindings", () => {
  it("places each parameter uniform after that stage's storage bindings", () => {
    expect(rgbaToLumaWGSL).toContain("@group(0) @binding(2) var<uniform> parameters");
    expect(sobelWGSL).toContain("@group(0) @binding(2) var<uniform> parameters");
    expect(initializeDPWGSL).toContain("@group(0) @binding(2) var<uniform> parameters");
    expect(accumulateDPWGSL).toContain("@group(0) @binding(4) var<uniform> parameters");
    expect(reduceWGSL).toContain("@group(0) @binding(2) var<uniform> parameters");
    expect(backtrackWGSL).toContain("@group(0) @binding(3) var<uniform> parameters");
    expect(removeVerticalWGSL).toContain("@group(0) @binding(3) var<uniform> parameters");
  });

  it("seeds final reduction from a finite first-row cost", () => {
    expect(reduceWGSL).toContain("var best = row[0];");
    expect(reduceWGSL).toContain("for (var x = 1u;");
    expect(reduceWGSL).not.toContain("0x7f800000u");
  });
});
