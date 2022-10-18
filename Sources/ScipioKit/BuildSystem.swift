import Foundation
import PackageGraph
import TSCBasic

struct _Compiler<E: Executor> {
    let rootPackage: Package
    let executor: E
    let fileSystem: any FileSystem
    let xcodebuild: XcodeBuildClient<E>
    private let extractor: DwarfExtractor<E>

    init(rootPackage: Package, executor: E, fileSystem: any FileSystem, extractor: DwarfExtractor<E>, xcodebuild: XcodeBuildClient<E>) {
        self.rootPackage = rootPackage
        self.executor = executor
        self.fileSystem = fileSystem
        self.extractor = extractor
        self.xcodebuild = xcodebuild
    }

    func buildXCFramework(target: ResolvedTarget,
                           buildConfiguration: BuildConfiguration,
                           isDebugSymbolsEmbedded: Bool,
                           sdks: Set<SDK>,
                           outputDirectory: AbsolutePath) async throws {
        let sdkNames = sdks.map(\.displayName).joined(separator: ", ")
        logger.info("📦 Building \(target.name) for \(sdkNames)")

        for sdk in sdks {
            try await xcodebuild.archive(context: .init(
                package: rootPackage,
                target: target,
                buildConfiguration: buildConfiguration,
                sdk: sdk
            ))
        }

        logger.info("🚀 Combining into XCFramework...")

        let debugSymbolPaths = isDebugSymbolsEmbedded ? try await extractDebugSymbolPaths(
            target: target,
            buildConfiguration: buildConfiguration,
            sdks: sdks
        ) : nil

        try await xcodebuild.createXCFramework(
            context: .init(
                package: rootPackage,
                target: target,
                buildConfiguration: buildConfiguration,
                sdks: sdks,
                debugSymbolPaths: debugSymbolPaths
            ),
            outputDir: outputDirectory
        )
    }

    private func extractDebugSymbolPaths(target: ResolvedTarget, buildConfiguration: BuildConfiguration, sdks: Set<SDK>) async throws -> [AbsolutePath] {
        let debugSymbols: [DebugSymbol] = sdks.compactMap { sdk in
            let dsymPath = buildDebugSymbolPath(buildConfiguration: buildConfiguration, sdk: sdk, target: target)
            guard fileSystem.exists(dsymPath) else { return nil }
            return DebugSymbol(dSYMPath: dsymPath,
                               target: target,
                               sdk: sdk,
                               buildConfiguration: buildConfiguration)
        }
        // You can use AsyncStream
        var symbolMapPaths: [AbsolutePath] = []
        for dSYMs in debugSymbols {
            let maps = try await self.extractor.dump(dwarfPath: dSYMs.dwarfPath)
            let paths = maps.values.map { uuid in
                buildArtifactsDirectoryPath(buildConfiguration: dSYMs.buildConfiguration, sdk: dSYMs.sdk)
                    .appending(component: "\(uuid.uuidString).bcsymbolmap")
            }
            symbolMapPaths.append(contentsOf: paths)
        }
        return debugSymbols.map { $0.dSYMPath } + symbolMapPaths
    }

    private func buildArtifactsDirectoryPath(buildConfiguration: BuildConfiguration, sdk: SDK) -> AbsolutePath {
        rootPackage.workspaceDirectory.appending(component: "\(buildConfiguration.settingsValue)-\(sdk.name)")
    }

    private func buildDebugSymbolPath(buildConfiguration: BuildConfiguration, sdk: SDK, target: ResolvedTarget) -> AbsolutePath {
        buildArtifactsDirectoryPath(buildConfiguration: buildConfiguration, sdk: sdk).appending(component: "\(target).framework.dSYM")
    }
}







enum BuildMode {
    case createPackage
    case prepareDependencies
}

struct BuildSystem<E: Executor> {
    let rootPackage: Package
    let executor: E
    let cacheStorage: (any CacheStorage)?
    let fileSystem: any FileSystem

    private let xcodebuild: XcodeBuildClient<E>
    private let extractor: DwarfExtractor<E>
    private let compiler: _Compiler<E>



    init(rootPackage: Package, cacheStorage: (any CacheStorage)?, executor: E = ProcessExecutor(), fileSystem: any FileSystem = localFileSystem) {
        self.rootPackage = rootPackage
        self.executor = executor
        self.cacheStorage = cacheStorage
        self.fileSystem = fileSystem
        self.extractor = DwarfExtractor(executor: executor)
        self.xcodebuild = XcodeBuildClient(executor: executor)
        self.compiler = _Compiler(
            rootPackage: rootPackage,
            executor: executor,
            fileSystem: fileSystem,
            extractor: extractor,
            xcodebuild: xcodebuild
        )
    }

    enum CacheStatus {
        case validCacheExist
        case invalidCacheExist
        case existButDisabled
        case none
    }

    private func cacheStatus(
        cacheSystem: CacheSystem,
        xcframeworkPath: AbsolutePath,
        isCacheEnabled: Bool,
        subPackage: ResolvedPackage,
        target: ResolvedTarget
    ) async throws -> CacheStatus {
        guard fileSystem.exists(xcframeworkPath) else {
            return .none
        }
        guard isCacheEnabled else {
            return .existButDisabled
        }

        guard await cacheSystem.existsValidCache(subPackage: subPackage, target: target) else {
            return .invalidCacheExist
        }

        return .validCacheExist
    }

    func build(mode: BuildMode, buildOptions: BuildOptions, outputDir: AbsolutePath, isCacheEnabled: Bool) async throws {
        logger.info("🗑️ Cleaning \(rootPackage.name)...")
        try await xcodebuild.clean(projectPath: rootPackage.projectPath, buildDirectory: rootPackage.workspaceDirectory)

        let cacheSystem = CacheSystem(
            rootPackage: rootPackage,
            buildOptions: buildOptions,
            outputDirectory: outputDir,
            storage: cacheStorage
        )

        let packages = rootPackage.resolvePackages(for: mode)
        for subPackage in packages {
            for target in subPackage.targets where target.type == .library {
                let frameworkName = target.xcFrameworkFileName
                let xcframeworkPath = outputDir.appending(component: frameworkName)
                let cacheStatus = try await cacheStatus(
                    cacheSystem: cacheSystem,
                    xcframeworkPath: xcframeworkPath,
                    isCacheEnabled: isCacheEnabled,
                    subPackage: subPackage,
                    target: target
                )

                switch cacheStatus {
                case .validCacheExist:
                    logger.info("✅ Valid \(target.name).xcframework is exists. Skip building.", metadata: .color(.green))
                    continue
                case .invalidCacheExist:
                    logger.warning("⚠️ Existing \(frameworkName) is outdated.", metadata: .color(.yellow))
                    logger.info("💥 Delete \(frameworkName)", metadata: .color(.red))
                    try fileSystem.removeFileTree(xcframeworkPath)
                case .existButDisabled:
                    try fileSystem.removeFileTree(xcframeworkPath)
                case .none:
                    break
                }

                if await cacheSystem.restoreCacheIfPossible(subPackage: subPackage, target: target) {
                    logger.info("✅ Restore \(frameworkName) from cache storage", metadata: .color(.green))
                } else {
                    try await compiler.buildXCFramework(target: target, options: buildOptions, outputDirectory: outputDir)
                    try? await cacheSystem.cacheFramework(xcframeworkPath, subPackage: subPackage, target: target)
                }

                if mode == .prepareDependencies {
                    do {
                        try await cacheSystem.generateVersionFile(subPackage: subPackage, target: target)
                    } catch {
                        logger.warning("⚠️ Could not create VersionFile. This framework will not be cached.", metadata: .color(.yellow))
                    }
                }
            }
        }
    }

    private func resolvePackage(for package: Package, mode: BuildMode) -> [ResolvedPackage] {
        switch mode {
        case .createPackage:
            return rootPackage.graph.rootPackages
        case .prepareDependencies:
            return rootPackage.dependencies
        }
    }
}

extension _Compiler {
    func buildXCFramework(target: ResolvedTarget, options: BuildOptions, outputDirectory: AbsolutePath) async throws {
        try await buildXCFramework(target: target,
                                   buildConfiguration: options.buildConfiguration,
                                   isDebugSymbolsEmbedded: options.isDebugSymbolsEmbedded,
                                   sdks: Set(options.targetSDKs),
                                   outputDirectory: outputDirectory
        )
    }
}

extension ResolvedTarget {
    var xcFrameworkFileName: String {
        "\(name.packageNamed()).xcframework"
    }
}

extension Package {
    var dependencies: [ResolvedPackage] {
        graph.packages
            .filter { $0.manifest.displayName != manifest.displayName }
    }

    func resolvePackages(for mode: BuildMode) -> [ResolvedPackage] {
        switch mode {
        case .createPackage:
            return graph.rootPackages
        case .prepareDependencies:
            return dependencies
        }

    }
}

extension BuildOptions {
    fileprivate var targetSDKs: [SDK] {
        sdks.flatMap { sdk in [
            sdk,
            isSimulatorSupported ? sdk.simulator : nil
        ]}.compactMap { $0 }
    }
}
