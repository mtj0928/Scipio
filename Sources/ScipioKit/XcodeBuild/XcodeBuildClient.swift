import TSCBasic
import PackageGraph

struct XcodeBuildClient<E: Executor> {
    let executor: E

    func createXCFramework(context: CreateXCFrameworkCommand.Context, outputDir: AbsolutePath) async throws {
        try await executor.execute(CreateXCFrameworkCommand(context: context, outputDir: outputDir))
    }

    func archive(context: ArchiveCommand.Context) async throws {
        try await executor.execute(ArchiveCommand(context: context))
    }

    func clean(projectPath: AbsolutePath, buildDirectory: AbsolutePath) async throws {
        try await executor.execute(CleanCommand(projectPath: projectPath, buildDirectory: buildDirectory))
    }
}

struct Pair {
    var key: String
    var value: String?
}

protocol XcodeBuildCommand {
    var subCommand: String { get }
    var options: [Pair] { get }
    var environmentVariables: [Pair] { get }
}

extension XcodeBuildCommand {
    func buildArguments() -> [String] {
        ["/usr/bin/xcrun", "xcodebuild"]
        + environmentVariables.map { pair in
            "\(pair.key)=\(pair.value!)"
        }
        + [subCommand]
        + options.flatMap { option in
            if let value = option.value {
                return ["-\(option.key)", value]
            } else {
                return ["-\(option.key)"]
            }
        }
    }
}

protocol BuildContext {
    var package: Package { get }
    var target: ResolvedTarget { get }
    var buildConfiguration: BuildConfiguration { get }
}

extension BuildContext {
    func buildXCArchivePath(sdk: SDK) -> AbsolutePath {
        package.archivesPath.appending(component: "\(target.name)_\(sdk.name).xcarchive")
    }

    var projectPath: AbsolutePath {
        package.projectPath
    }
}

extension Package {
    fileprivate var archivesPath: AbsolutePath {
        workspaceDirectory.appending(component: "archives")
    }
}

extension Executor {
    @discardableResult
    fileprivate func execute<Command: XcodeBuildCommand>(_ command: Command) async throws -> ExecutorResult {
        try await execute(command.buildArguments())
    }
}
