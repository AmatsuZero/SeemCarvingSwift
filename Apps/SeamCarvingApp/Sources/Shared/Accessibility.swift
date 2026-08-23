// Accessibility.swift
//
// Centralized accessibility identifiers/labels for the shared editor. Using
// constants keeps UI tests stable and lets every platform share one vocabulary.

import Foundation

enum A11y {
    /// A namespaced collection of accessibility identifiers.
    enum ID {
        static let contentView = "editor.contentView"
        static let canvas = "editor.canvas"
        static let controls = "editor.controls"
        static let maskToolbar = "editor.maskToolbar"
        static let faceControls = "editor.faceControls"
        static let progress = "editor.progress"
        static let export = "editor.export"

        static let targetWidth = "editor.targetWidth"
        static let targetHeight = "editor.targetHeight"
        static let lockAspect = "editor.lockAspect"
        static let energyMode = "editor.energyMode"
        static let dimensionOrder = "editor.dimensionOrder"
        static let backend = "editor.backend"
        static let deterministic = "editor.deterministic"
        static let preScale = "editor.preScale"
        static let operationMode = "editor.operationMode"
        static let restoreOriginalSize = "editor.restoreOriginalSize"

        static let maskModeProtect = "editor.maskModeProtect"
        static let maskModeRemove = "editor.maskModeRemove"
        static let brushSize = "editor.brushSize"
        static let brushStrength = "editor.brushStrength"
        static let undo = "editor.undo"
        static let redo = "editor.redo"
        static let clearMasks = "editor.clearMasks"
        static let resetMasks = "editor.resetMasks"

        static let faceEnabled = "editor.faceEnabled"
        static let facePolicy = "editor.facePolicy"
        static let faceCadence = "editor.faceCadence"
        static let faceConfidence = "editor.faceConfidence"
        static let faceExpansion = "editor.faceExpansion"
        static let faceDetect = "editor.faceDetect"

        static let cancel = "editor.cancel"
        static let resize = "editor.resize"
        static let exportButton = "editor.exportButton"
        static let importButton = "editor.importButton"
        static let canvasPlaceholder = "editor.canvas.placeholder"
    }

    /// Human-readable labels kept in one place so translators/copy edits are easy.
    enum Label {
        static let canvas = "Image canvas"
        static let controls = "Resize controls"
        static let maskToolbar = "Mask tools"
        static let faceControls = "Face protection"
        static let progress = "Resize progress"
        static let export = "Export"

        static let targetWidth = "Target width"
        static let targetHeight = "Target height"
        static let lockAspect = "Lock aspect ratio"
        static let energyMode = "Energy mode"
        static let dimensionOrder = "Dimension order"
        static let backend = "Backend"
        static let deterministic = "Deterministic"
        static let preScale = "Pre-scale strategy"

        static let protect = "Protect"
        static let remove = "Remove"
        static let erase = "Erase"
        static let brushSize = "Brush size"
        static let strength = "Strength"
        static let undo = "Undo"
        static let redo = "Redo"
        static let clear = "Clear masks"
        static let reset = "Reset masks"

        static let faceEnabled = "Enable face protection"
        static let facePolicy = "Policy"
        static let faceCadence = "Detection cadence"
        static let confidence = "Minimum confidence"
        static let expansion = "Expansion"
        static let detectFaces = "Detect faces"

        static let cancel = "Cancel"
        static let resize = "Resize"
        static let exportButton = "Export image"
    }
}
