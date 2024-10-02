import struct TSCBasic.AbsolutePath
import TSCBasic
import Foundation

struct MacroProducer {
    let outputDirectory: URL
    let packageDirectory: URL
    let fileSystem: any FileSystem

    func processMacroTargets(graph: ScipioPackageDependencyGraph) async throws -> [String: PluginExecutable] {
        let targetsUsingMacro = graph.tree.modulesUsingMacro()

        var pluginExecutables: [String: PluginExecutable] = [:]
        for target in targetsUsingMacro {
            let macroModules = target.dependencies.compactMap { $0.module }.filter { $0.type == .macro }
            let macroNodesNames = macroModules.map(\.name).joined(separator: ", ")
            logger.info("🔨 Prebuild a macro target: \(macroNodesNames)")
            let swift = SwiftCommand(workingDirectory: packageDirectory.absolutePath)
            try await swift.build(target: target.name)
            logger.info("✅ Success to build a macro target: \(macroNodesNames)")

            for macroModule in macroModules {
                let targetName = macroModule.name
                let executablePath = packageDirectory.appending(components: ".build", "release", "\(targetName)-tool")
                let destinationPath = outputDirectory.appending(path: targetName)
                try fileSystem.createDirectory(outputDirectory.absolutePath)
                try fileSystem.move(from: executablePath.absolutePath, to: destinationPath.absolutePath)

                pluginExecutables[targetName] = PluginExecutable(path: destinationPath, targetName: targetName)
            }
        }
        return pluginExecutables
    }
}

extension ScipioBuildNode {
    fileprivate func modulesUsingMacro() -> [ScipioResolvedModule] {
        orderedDependencies()
            .filter { buildProduct in
                buildProduct.target.dependencies.contains(where: { dependency in
                    dependency.module?.type == .macro
                })
            }
            .map(\.target)
            .reversed()
    }
}

struct PluginExecutable {
    let path: URL
    let targetName: String

    var compilerOption: String {
        path.absoluteURL.path() + "#" + targetName
    }
}
