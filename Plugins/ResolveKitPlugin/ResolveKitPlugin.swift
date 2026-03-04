import Foundation
import PackagePlugin

@main
struct ResolveKitPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let swiftTarget = target as? SwiftSourceModuleTarget else {
            return []
        }

        let output = context.pluginWorkDirectoryURL.appending(path: "ResolveKitAutoRegistry.swift")

        return [
            .buildCommand(
                displayName: "Generating ResolveKit function registry",
                executable: try context.tool(named: "ResolveKitCodegen").url,
                arguments: [swiftTarget.directoryURL.path(), output.path()],
                inputFiles: swiftTarget.sourceFiles(withSuffix: ".swift").map(\.url),
                outputFiles: [output]
            )
        ]
    }
}
