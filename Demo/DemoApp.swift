import BuildCache
import BuildCacheUI
import SwiftUI

/// The demo's monorepo: the app owns its module graph, toolchain, signing key
/// and budget, and hands them to the library's console. That is the same split
/// a real adopter has: the package supplies the mechanism, the app supplies
/// the policy.
enum DemoMonorepo {
    static let specs: [ModuleSpec] = [
        ModuleSpec(name: "CoreModels", compileCostMs: 900, artifactBytes: 48_000),
        ModuleSpec(name: "DesignSystem", compileCostMs: 800, artifactBytes: 64_000),
        ModuleSpec(name: "Networking", compileCostMs: 700, artifactBytes: 32_000, dependencies: ["CoreModels"]),
        ModuleSpec(name: "Persistence", compileCostMs: 600, artifactBytes: 28_000, dependencies: ["CoreModels"]),
        ModuleSpec(name: "Analytics", compileCostMs: 300, artifactBytes: 12_000, dependencies: ["CoreModels"]),
        ModuleSpec(name: "AIAssist", compileCostMs: 500, artifactBytes: 20_000,
                   dependencies: ["Networking", "CoreModels"]),
        ModuleSpec(name: "FeatureFeed", compileCostMs: 1_200, artifactBytes: 56_000,
                   dependencies: ["Networking", "Persistence", "DesignSystem", "Analytics"]),
        ModuleSpec(name: "FeatureSearch", compileCostMs: 700, artifactBytes: 30_000,
                   dependencies: ["Networking", "DesignSystem"]),
        ModuleSpec(name: "FeatureProfile", compileCostMs: 650, artifactBytes: 26_000,
                   dependencies: ["Networking", "Persistence", "DesignSystem"]),
        ModuleSpec(name: "FeatureCheckout", compileCostMs: 1_100, artifactBytes: 52_000,
                   dependencies: ["Networking", "Persistence", "DesignSystem", "Analytics"]),
        ModuleSpec(name: "FeatureSettings", compileCostMs: 400, artifactBytes: 16_000,
                   dependencies: ["Persistence", "DesignSystem"]),
        ModuleSpec(name: "App", compileCostMs: 1_500, artifactBytes: 80_000,
                   dependencies: ["FeatureFeed", "FeatureSearch", "FeatureProfile", "FeatureCheckout",
                                  "FeatureSettings", "AIAssist"]),
    ]

    static let checkoutRoot = "/Users/ci/work/monorepo"

    /// Builds the scenario, or nil if the compiled-in graph were invalid
    /// (it is not; the fallback view exists so a bad edit to `specs` shows
    /// an error instead of crashing).
    static func scenario() -> ConsoleScenario? {
        guard let graph = try? BuildGraph(specs) else { return nil }
        let configuration = BuildConfiguration(
            toolchain: ToolchainIdentity(compilerVersion: "swiftlang-6.4.0.34.1",
                                         xcodeBuild: "27A9275", sdkBuild: "24A94425"),
            targetTriple: "arm64-apple-ios17.0-simulator",
            flags: ["-Onone", "-enable-testing", "-j", "10", "-I\(checkoutRoot)/Sources/Shared"],
            normalizer: FlagNormalizer(prefixMap: [checkoutRoot: "$SRCROOT"]))
        return ConsoleScenario(
            graph: graph,
            configuration: configuration,
            nextToolchain: ToolchainIdentity(compilerVersion: "swiftlang-6.4.1.12.3",
                                             xcodeBuild: "27B5012", sdkBuild: "24B5022"),
            // Demo-only secret. A real deployment signs in CI with a private
            // key and ships only the public key to readers (see the library
            // README's "Honest limitations").
            ciSigningKey: HMACArtifactKey(keyID: "ci-2026", secret: Array("demo-only-secret".utf8)),
            policy: BlastRadiusPolicy(maxInvalidatedCostFraction: 0.35),
            compositionRoots: ["App"],
            agentEditTargets: ["FeatureSearch", "DesignSystem", "CoreModels"],
            poisonTarget: "Networking")
    }
}

/// Optional scripted walkthroughs, selected with a launch argument
/// (`-tour core-edit`). They run through the same model methods the buttons
/// call; used to capture the README screenshots reproducibly with
/// `xcrun simctl launch <device> com.rajatlakhina.BuildCacheDemo -tour <name>`.
/// With no argument the app starts empty and waits for taps.
enum DemoTour {
    static func steps(arguments: [String]) -> [ConsoleStep] {
        guard let flag = arguments.firstIndex(of: "-tour"), flag + 1 < arguments.count else { return [] }
        switch arguments[flag + 1] {
        case "warm": return [.ciBuild, .developerCleanCheckout]
        case "leaf-edit": return [.ciBuild, .agentEdits("FeatureSearch")]
        case "core-edit": return [.ciBuild, .agentEdits("CoreModels")]
        case "poison": return [.ciBuild, .poisonRemoteArtifact, .developerCleanCheckout]
        case "outage": return [.ciBuild, .toggleOutage, .developerCleanCheckout]
        case "toolchain": return [.ciBuild, .bumpToolchain, .developerCleanCheckout]
        default: return []
        }
    }
}

@main
struct BuildCacheDemoApp: App {
    // Built once per launch, not on every body evaluation.
    private let scenario = DemoMonorepo.scenario()
    private let script = DemoTour.steps(arguments: ProcessInfo.processInfo.arguments)

    var body: some Scene {
        WindowGroup {
            if let scenario {
                BuildCacheConsoleView(scenario: scenario, script: script)
            } else {
                ContentUnavailableView("Invalid module graph", systemImage: "exclamationmark.triangle",
                                       description: Text("DemoMonorepo.specs has a cycle or an unknown dependency."))
            }
        }
    }
}
