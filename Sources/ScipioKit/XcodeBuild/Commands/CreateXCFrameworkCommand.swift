import TSCBasic
import PackageGraph

struct CreateXCFrameworkCommand: XcodeBuildCommand {
    struct Context: BuildContext {
        let package: Package
        let target: ResolvedTarget
        let buildConfiguration: BuildConfiguration
        let sdks: Set<SDK>
        let debugSymbolPaths: [AbsolutePath]?
    }
    let context: Context
    let subCommand: String = "-create-xcframework"
    let outputDir: AbsolutePath

    var xcFrameworkPath: AbsolutePath {
        outputDir.appending(component: context.target.xcFrameworkFileName)
    }

    func buildFrameworkPath(sdk: SDK) -> AbsolutePath {
        context.buildXCArchivePath(sdk: sdk)
            .appending(components: "Products", "Library", "Frameworks")
            .appending(component: "\(context.target.name.packageNamed()).framework")
    }

    var options: [Pair] {
        context.sdks.map { sdk in
                .init(key: "framework", value: buildFrameworkPath(sdk: sdk).pathString)
        }
        +
        (context.debugSymbolPaths.flatMap {
            $0.map { .init(key: "debug-symbols", value: $0.pathString) }
        } ?? [])
        + [.init(key: "output", value: xcFrameworkPath.pathString)]
    }

    var environmentVariables: [Pair] {
        []
    }
}
