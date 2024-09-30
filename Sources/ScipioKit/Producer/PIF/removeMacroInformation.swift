import PackageGraph
import PackageModel
import Basics

func removeMacroInformation(from graph: ModulesGraph) throws -> ModulesGraph {
    let packages = try graph.packages.map { package in
        let modules = package.modules.compactMap { module -> ResolvedModule? in
            if module.type == .macro {
                return nil
            }
            let dependencies = module.dependencies.filter { dependency in
                dependency.module?.type != .macro
            }
            return ResolvedModule(
                packageIdentity: package.identity,
                underlying: module.underlying,
                dependencies: dependencies,
                defaultLocalization: module.defaultLocalization,
                supportedPlatforms: module.supportedPlatforms,
                platformVersionProvider: PlatformVersionProvider(implementation: .minimumDeploymentTargetDefault)
            )
        }
        let products = try package.products.compactMap { product -> ResolvedProduct? in
            if product.type == .macro { return nil }
            let modules = product.modules.compactMap { module -> ResolvedModule? in
                if module.type == .macro { return nil }
                let dependencies = module.dependencies.filter { dependency in
                    dependency.module?.type != .macro
                }
                return ResolvedModule(
                    packageIdentity: package.identity,
                    underlying: module.underlying,
                    dependencies: dependencies,
                    defaultLocalization: module.defaultLocalization,
                    supportedPlatforms: module.supportedPlatforms,
                    platformVersionProvider: PlatformVersionProvider(implementation: .minimumDeploymentTargetDefault)
                )
            }
            let underlyingProduct = try Product(
                package: package.identity,
                name: product.underlying.name,
                type: product.type,
                modules: product.underlying.modules.filter { $0.type != .macro },
                testEntryPointPath: product.underlying.testEntryPointPath
            )
            return ResolvedProduct(
                packageIdentity: product.packageIdentity,
                product: underlyingProduct,
                modules: IdentifiableSet(modules)
            )
        }
        return ResolvedPackage(
            underlying: package.underlying,
            defaultLocalization: package.defaultLocalization,
            supportedPlatforms: package.supportedPlatforms,
            dependencies: package.dependencies,
            modules: IdentifiableSet(modules),
            products: products,
            registryMetadata: package.registryMetadata,
            platformVersionProvider: PlatformVersionProvider(implementation: .minimumDeploymentTargetDefault)
        )
    }

    return try ModulesGraph(
        rootPackages: graph.rootPackages.map { $0 },
        rootDependencies: graph.inputPackages,
        packages: IdentifiableSet(packages),
        dependencies: graph.requiredDependencies,
        binaryArtifacts: graph.binaryArtifacts
    )
}
