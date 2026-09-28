// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PoiseVoiceAnalysis",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PoiseVoiceAnalysis", targets: ["PoiseVoiceAnalysis"]),
        .executable(name: "voice-analyze-native", targets: ["VoiceAnalyzeNative"]),
    ],
    targets: [
        .target(name: "PoiseVoiceAnalysis", path: "apple", exclude: ["RecordedSpeechCheck.swift"],
                resources: [.process("Resources")]),
        .executableTarget(name: "VoiceAnalyzeNative", dependencies: ["PoiseVoiceAnalysis"], path: "native-cli"),
        .testTarget(name: "PoiseVoiceAnalysisTests", dependencies: ["PoiseVoiceAnalysis"], path: "native-tests"),
    ]
)
