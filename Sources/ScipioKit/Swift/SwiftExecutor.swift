import TSCBasic
import class TSCBasic.Process

struct SwiftCommand {
    var executor = ProcessExecutor<StandardErrorOutputDecoder>()

    init(workingDirectory: AbsolutePath) {
        executor.workingDirectory = workingDirectory
    }

    func build(target: String) async throws {
        do {
            guard let swiftPath = Process.findExecutable("swift") else {
                fatalError("swift command is not found")
            }
            _ = try await executor.execute(
                swiftPath.pathString,
                "build",
                "--target",
                target,
                "-c",
                "release"
            )
        } catch let error as ProcessExecutorError {
            switch error {
            case .signalled, .unknownError: throw error
            case .terminated:
                throw ProcessExecutorError.terminated(errorOutput: "terminated")
            }
        } catch {
            throw ProcessExecutorError.unknownError(error)
        }
    }
}
