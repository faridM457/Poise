import Foundation

// Xcode's PBXFileSystemSynchronizedRootGroup flattens every bundled resource
// to the app bundle's root (verified by inspecting a real build: Resources/
// Models/model.safetensors, tokenizer.model, and Resources/Models/voices/
// *.safetensors all land as loose files directly in Poise.app/, losing
// the Models/voices/ directory structure). PocketTtsEngine's Rust side
// expects a real directory containing model.safetensors + tokenizer.model
// alongside a voices/ subdirectory holding ALL voice embeddings by index
// (index -> file position matters; a missing file shifts every later
// index and silently fails to attach a voice embedding -- confirmed via a
// real InferenceFailed crash when only jean.safetensors was staged), so we
// reconstruct that full layout once, in Caches, from the flattened bundle
// resources, and point the engine at the reconstructed directory instead
// of the bundle itself.
enum PocketTTSModelStaging {
    // Bump this if the staged layout's contents change shape (e.g. voice
    // list) -- forces re-staging instead of reusing a stale Caches copy
    // from a previous build (this bump itself fixes exactly that: earlier
    // builds staged only "jean", leaving other voice indices unattached).
    private static let stagingVersion = 2

    // Every bundled voice embedding, in the exact index order the demo
    // harness's TTSVoice enum and this app's jeanVoiceIndex assume:
    // 0 Alba, 1 Marius, 2 Javert, 3 Jean, 4 Fantine, 5 Cosette, 6 Eponine, 7 Azelma.
    private static let voiceNames = ["alba", "marius", "javert", "jean", "fantine", "cosette", "eponine", "azelma"]

    enum StagingError: Error, LocalizedError {
        case missingBundleResource(String)

        var errorDescription: String? {
            switch self {
            case .missingBundleResource(let name):
                return "Missing bundled Pocket TTS resource: \(name)"
            }
        }
    }

    /// Returns the staged model directory, copying bundle resources into
    /// place on first use only (subsequent calls are near-instant no-ops).
    static func stagedModelDirectory() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let modelDir = caches.appendingPathComponent("PocketTTSModel-v\(stagingVersion)", isDirectory: true)
        let voicesDir = modelDir.appendingPathComponent("voices", isDirectory: true)
        try FileManager.default.createDirectory(at: voicesDir, withIntermediateDirectories: true)

        try stageIfNeeded(bundleResource: "model", ext: "safetensors", to: modelDir.appendingPathComponent("model.safetensors"))
        try stageIfNeeded(bundleResource: "tokenizer", ext: "model", to: modelDir.appendingPathComponent("tokenizer.model"))
        for name in voiceNames {
            try stageIfNeeded(bundleResource: name, ext: "safetensors", to: voicesDir.appendingPathComponent("\(name).safetensors"))
        }

        return modelDir
    }

    private static func stageIfNeeded(bundleResource: String, ext: String, to destination: URL) throws {
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        guard let sourceURL = Bundle.main.url(forResource: bundleResource, withExtension: ext) else {
            throw StagingError.missingBundleResource("\(bundleResource).\(ext)")
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }
}
