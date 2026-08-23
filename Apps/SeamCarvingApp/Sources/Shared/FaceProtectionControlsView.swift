// FaceProtectionControlsView.swift
//
// Controls for the optional face-protection feature. Reads/writes
// `configuration.faceProtection` (the `FaceProtectionConfiguration`). The user
// can enable protection, choose a policy preset, set cadence, and exclude a
// detected region from protection by index. No detection runs here — detection
// is performed by the (future) carving pipeline; this view only reflects and
// edits configuration + detected region metadata.

import Foundation
import SeamCarvingCore
import SeamCarvingVision
import SwiftUI

struct FaceProtectionControlsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section(A11y.Label.faceControls) {
                Toggle(A11y.Label.faceEnabled, isOn: faceEnabled)
                    .accessibilityIdentifier(A11y.ID.faceEnabled)
                if model.configuration.faceProtection != nil {
                    policyPicker
                    cadencePicker
                    confidenceAndExpansion
                    detectedRegionsList
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11y.ID.faceControls)
        .disabled(model.phase.isProcessing)
    }

    // MARK: - Enable / disable

    private var faceEnabled: Binding<Bool> {
        Binding {
            model.configuration.faceProtection != nil
        } set: { on in
            if on {
                model.configuration.faceProtection = FaceProtectionConfiguration(
                    policy: .caireInspired(try! CaireInspiredParameters())
                )
            } else {
                model.configuration.faceProtection = nil
            }
        }
    }

    // MARK: - Policy preset

    @ViewBuilder
    private var policyPicker: some View {
        Picker(A11y.Label.facePolicy, selection: policySelection) {
            Text("Caire-inspired").tag(0)
            Text("Vision quality").tag(1)
        }
        .accessibilityIdentifier(A11y.ID.facePolicy)
    }

    private var policySelection: Binding<Int> {
        Binding {
            switch model.configuration.faceProtection?.policy {
            case .caireInspired: return 0
            case .visionQuality: return 1
            case nil: return 0
            }
        } set: { tag in
            guard model.configuration.faceProtection != nil else { return }
            switch tag {
            case 1:
                model.configuration.faceProtection?.policy = .visionQuality(try! VisionQualityParameters())
            default:
                model.configuration.faceProtection?.policy = .caireInspired(try! CaireInspiredParameters())
            }
        }
    }

    // MARK: - Cadence

    @ViewBuilder
    private var cadencePicker: some View {
        Picker(A11y.Label.faceCadence, selection: cadenceBinding) {
            Text("Detect once").tag(FaceDetectionCadence.detectOnceAndTransformMask)
            Text("Re-detect each pass").tag(FaceDetectionCadence.redetectEveryPass)
        }
        .accessibilityIdentifier(A11y.ID.faceCadence)
    }

    private var cadenceBinding: Binding<FaceDetectionCadence> {
        Binding {
            model.configuration.faceProtection?.cadence ?? .detectOnceAndTransformMask
        } set: { cadence in
            model.configuration.faceProtection?.cadence = cadence
        }
    }

    // MARK: - Confidence / expansion (policy params)

    @ViewBuilder
    private var confidenceAndExpansion: some View {
        let params = model.configuration.faceProtection?.policy
        let confidence = bindingForMinimumConfidence(params)
        let expansion = bindingForExpansionFraction(params)

        HStack {
            Text(A11y.Label.confidence)
            Slider(value: confidence, in: 0...1, step: 0.05)
                .accessibilityIdentifier(A11y.ID.faceConfidence)
            Text(String(format: "%.2f", confidence.wrappedValue)).frame(width: 44)
        }
        HStack {
            Text(A11y.Label.expansion)
            Slider(value: expansion, in: 0...1, step: 0.05)
                .accessibilityIdentifier(A11y.ID.faceExpansion)
            Text(String(format: "%.2f", expansion.wrappedValue)).frame(width: 44)
        }
    }

    private func bindingForMinimumConfidence(_ policy: FaceProtectionPolicy?) -> Binding<Double> {
        Binding {
            switch policy {
            case .caireInspired(let p): return Double(p.minimumConfidence)
            case .visionQuality(let p): return Double(p.minimumConfidence)
            case nil: return 0
            }
        } set: { v in
            guard var fp = model.configuration.faceProtection else { return }
            switch fp.policy {
            case .caireInspired(var p):
                p.minimumConfidence = Float(v)
                fp.policy = .caireInspired(p)
            case .visionQuality(var p):
                p.minimumConfidence = Float(v)
                fp.policy = .visionQuality(p)
            }
            model.configuration.faceProtection = fp
        }
    }

    private func bindingForExpansionFraction(_ policy: FaceProtectionPolicy?) -> Binding<Double> {
        Binding {
            switch policy {
            case .caireInspired(let p): return Double(p.expansionFraction)
            case .visionQuality(let p): return Double(p.expansionFraction)
            case nil: return 0
            }
        } set: { v in
            guard var fp = model.configuration.faceProtection else { return }
            switch fp.policy {
            case .caireInspired(var p):
                p.expansionFraction = Float(v)
                fp.policy = .caireInspired(p)
            case .visionQuality(var p):
                p.expansionFraction = Float(v)
                fp.policy = .visionQuality(p)
            }
            model.configuration.faceProtection = fp
        }
    }

    // MARK: - Detected regions (exclude toggle)

    @ViewBuilder
    private var detectedRegionsList: some View {
        let regions = model.configuration.faceProtection?.detectedRegions
        ?? model.document?.faceRegions
        if let regions, !regions.isEmpty {
            Section("Detected regions") {
                ForEach(Array(regions.enumerated()), id: \.offset) { index, region in
                    Toggle("Region \(index + 1) (\(region.width)×\(region.height), \(Int(region.confidence * 100))%)",
                           isOn: excludeBinding(for: index))
                }
            }
        }
    }

    /// A region is "protected" unless its index is in `excludedRegionIndices`;
    /// toggling adds/removes it from that set.
    private func excludeBinding(for index: Int) -> Binding<Bool> {
        Binding {
            !(model.configuration.faceProtection?.excludedRegionIndices.contains(index) ?? false)
        } set: { protected in
            guard model.configuration.faceProtection != nil else { return }
            if protected {
                model.configuration.faceProtection?.excludedRegionIndices.remove(index)
            } else {
                model.configuration.faceProtection?.excludedRegionIndices.insert(index)
            }
        }
    }
}
