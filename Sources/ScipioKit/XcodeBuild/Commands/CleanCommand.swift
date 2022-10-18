import TSCBasic

struct CleanCommand: XcodeBuildCommand {
    let projectPath: AbsolutePath
    let buildDirectory: AbsolutePath

    let subCommand: String = "clean"
    var options: [Pair] {
        [.init(key: "project", value: projectPath.pathString)]
    }

    var environmentVariables: [Pair] {
        [.init(key: "BUILD_DIR", value: buildDirectory.pathString)]
    }
}
