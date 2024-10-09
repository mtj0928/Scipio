import struct TSCBasic.AbsolutePath
import TSCBasic
import Foundation
import PackageModel
import PackageGraph

struct MacroProducer {
    let descriptionPackage: DescriptionPackage
    let outputDirectory: URL
    let packageDirectory: URL
    let fileSystem: any FileSystem

    func processMacroTargets(graph: ScipioPackageDependencyGraph) async throws -> [String: PluginExecutable] {
        let macroTargets = graph.macroTrees
        var results: [String: PluginExecutable] = [:]
        for macroTree in macroTargets {
            let compiler = PIFCompiler(
                descriptionPackage: descriptionPackage,
                buildOptions: BuildOptions(
                    buildConfiguration: .release,
                    isDebugSymbolsEmbedded: false,
                    frameworkType: .dynamic,
                    sdks: [.macOS],
                    extraFlags: nil,
                    extraBuildParameters: nil,
                    enableLibraryEvolution: false,
                    customFrameworkModuleMapContents: nil
                ),
                buildOptionsMatrix: [:]
            )
            let outputURL = outputDirectory.appending(component: macroTree.buildProduct.target.name)
            try await compiler.createMacroExecutable(
                buildProduct: macroTree.buildProduct,
                outputDirectory: outputURL,
                overwrite: true
            )
            results[macroTree.buildProduct.target.name] = PluginExecutable(
                path: outputURL,
                targetName: macroTree.buildProduct.target.name
            )
        }
        return results
    }
}

import Basics

extension ModulesGraph {
    fileprivate func macroTargets() -> [ResolvedModule] {
        allModules.filter { $0.type == .macro }
    }

    func transformMacroTargetToExecutable() throws -> ModulesGraph {
        let packages = packages.map { package in
            let modules = package.modules.compactMap { module -> ResolvedModule? in
                if module.type == .macro {
                    let underlying = module.underlying as? SwiftModule
                    let newModule = SwiftModule(
                        name: module.name,
                        potentialBundleName: module.underlying.potentialBundleName,
                        type: .executable,
                        path: module.underlying.path,
                        sources: module.underlying.sources,
                        resources: module.underlying.resources,
                        ignored: module.underlying.ignored,
                        others: module.underlying.others,
                        dependencies: module.underlying.dependencies,
                        packageAccess: module.underlying.packageAccess,
                        declaredSwiftVersions: underlying!.declaredSwiftVersions,
                        buildSettings: module.underlying.buildSettings,
                        buildSettingsDescription: [], //  TODO
                        pluginUsages: module.underlying.pluginUsages,
                        usesUnsafeFlags: module.underlying.usesUnsafeFlags
                    )

                    package.products

                    return ResolvedModule(
                        packageIdentity: package.identity,
                        underlying: newModule,
                        dependencies: module.dependencies,
                        supportedPlatforms: module.supportedPlatforms,
                        platformVersionProvider: .init(implementation: .minimumDeploymentTargetDefault)
                    )
                }
                return module
            }
            package.underlying.modules = modules.map(\.underlying)
            return ResolvedPackage(
                underlying: package.underlying,
                defaultLocalization: package.defaultLocalization,
                supportedPlatforms: package.supportedPlatforms,
                dependencies: package.dependencies,
                modules: IdentifiableSet(modules),
                products: package.products,
                registryMetadata: package.registryMetadata,
                platformVersionProvider: PlatformVersionProvider(implementation: .minimumDeploymentTargetDefault)
            )
        }

        return try ModulesGraph(
            rootPackages: rootPackages.map { $0 },
            rootDependencies: inputPackages,
            packages: IdentifiableSet(packages),
            dependencies: requiredDependencies,
            binaryArtifacts: binaryArtifacts
        )
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
