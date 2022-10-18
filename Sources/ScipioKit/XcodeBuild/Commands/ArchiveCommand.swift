import TSCBasic
import PackageGraph

struct ArchiveCommand: XcodeBuildCommand {
    struct Context: BuildContext {
        var package: Package
        var target: ResolvedTarget
        var buildConfiguration: BuildConfiguration
        var sdk: SDK
    }
    var context: Context
    var xcArchivePath: AbsolutePath {
        context.xcArchivePath
    }

    let subCommand: String = "archive"
    var options: [Pair] {
        [
            ("project", context.projectPath.pathString),
            ("configuration", context.buildConfiguration.settingsValue),
            ("scheme", context.target.name),
            ("archivePath", xcArchivePath.pathString),
            ("destination", context.sdk.destination),
            ("sdk", context.sdk.name),
        ].map(Pair.init(key:value:))
    }

    var environmentVariables: [Pair] {
        [
            ("BUILD_DIR", context.package.workspaceDirectory.pathString),
            ("SKIP_INSTALL", "NO"),
        ].map(Pair.init(key:value:))
    }
}

extension ArchiveCommand.Context {
    var xcArchivePath: AbsolutePath {
        buildXCArchivePath(sdk: sdk)
    }
}
