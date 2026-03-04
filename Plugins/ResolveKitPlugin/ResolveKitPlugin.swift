import Foundation
import PackagePlugin

@main
struct ResolveKitPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let swiftTarget = target as? SwiftSourceModuleTarget else {
            return []
        }

        let output = context.pluginWorkDirectory.appending("ResolveKitAutoRegistry.swift")
        let codegenTool = try context.tool(named: "ResolveKitCodegen")

        return [
            .buildCommand(
                displayName: "Generating ResolveKit function registry",
                executable: codegenTool.path,
                arguments: [swiftTarget.directory.string, output.string],
                inputFiles: swiftTarget.sourceFiles(withSuffix: ".swift").map(\.path),
                outputFiles: [output]
            )
        ]
    }
}
