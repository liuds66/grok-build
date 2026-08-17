import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

enum CheckpointFileKind: String, Codable {
    case file
    case directory
    case symbolicLink
}

struct CheckpointFileRecord: Codable, Equatable {
    let relativePath: String
    let kind: CheckpointFileKind
    let digest: String?
    let linkDestination: String?
    let permissions: UInt16?
}

/// A Git-backed checkpoint stores the user's pre-task patch and only the
/// untracked files that existed before the task. Git can reconstruct clean
/// tracked files far faster than copying an entire Rust/Cargo build tree from
/// an external volume.
struct GitCheckpointMetadata: Codable, Equatable {
    let repositoryPath: String
    let patchPath: String
    let untrackedSnapshotPath: String
    let untrackedPaths: [String]
}

struct CheckpointRecord: Codable, Identifiable, Equatable {
    let id: String
    let projectPath: String
    let snapshotPath: String
    let createdAt: Date
    let files: [CheckpointFileRecord]
    let git: GitCheckpointMetadata?
}

struct RollbackVerification: Codable, Equatable {
    let checkpointID: String
    let verified: Bool
    let restoredFiles: Int
    let removedFiles: Int
    let missingFiles: [String]
    let unexpectedFiles: [String]
}

enum CheckpointError: LocalizedError {
    case projectMissing(String)
    case unsafePath(String)
    case io(String)

    var errorDescription: String? {
        switch self {
        case .projectMissing(let path): return "项目目录不存在：\(path)"
        case .unsafePath(let path): return "拒绝处理项目外路径：\(path)"
        case .io(let message): return message
        }
    }
}

/// Content-addressed enough for rollback verification while keeping the
/// existing Rust/ACP runtime untouched. The snapshot lives outside the
/// project, so a failed task can be restored even when the project is dirty.
final class CheckpointManager {
    static let shared = CheckpointManager()

    // These directories contain source-control metadata or reproducible build
    // output. Traversing them makes a checkpoint unnecessarily expensive (and
    // can block for a long time when a project is on an external volume),
    // while restoring them would only put generated artifacts back on disk.
    // Keep this list narrow so user-authored hidden files and configuration
    // directories are still protected by the checkpoint.
    private static let skippedDirectoryNames: Set<String> = [
        ".git",
        "target",
        "node_modules",
        "dist",
        "build",
        ".next",
        ".cache",
        "DerivedData",
    ]

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let lock = NSLock()

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.rootURL = support.appendingPathComponent("Nexus/checkpoints", isDirectory: true)
        }
        try? fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
    }

    func create(projectPath: String) throws -> CheckpointRecord {
        let project = try validatedProjectURL(projectPath)
        let checkpointID = UUID().uuidString.lowercased()
        let checkpointURL = rootURL.appendingPathComponent(checkpointID, isDirectory: true)
        let snapshotURL = checkpointURL.appendingPathComponent("snapshot", isDirectory: true)
        try fileManager.createDirectory(at: snapshotURL, withIntermediateDirectories: true)

        do {
            if let repository = try gitRepository(for: project) {
                let gitMetadata = try captureGitCheckpoint(
                    projectURL: project,
                    repositoryURL: repository,
                    checkpointURL: checkpointURL,
                    snapshotURL: snapshotURL
                )
                let record = CheckpointRecord(
                    id: checkpointID,
                    projectPath: project.path,
                    snapshotPath: snapshotURL.path,
                    createdAt: Date(),
                    files: [],
                    git: gitMetadata
                )
                let data = try encoder.encode(record)
                try data.write(to: checkpointURL.appendingPathComponent("manifest.json"), options: .atomic)
                return record
            }
            let records = try capture(projectURL: project, snapshotURL: snapshotURL)
            let record = CheckpointRecord(
                id: checkpointID,
                projectPath: project.path,
                snapshotPath: snapshotURL.path,
                createdAt: Date(),
                files: records.sorted { $0.relativePath < $1.relativePath },
                git: nil
            )
            let data = try encoder.encode(record)
            try data.write(to: checkpointURL.appendingPathComponent("manifest.json"), options: .atomic)
            return record
        } catch {
            try? fileManager.removeItem(at: checkpointURL)
            throw error
        }
    }

    func rollback(_ record: CheckpointRecord) throws -> RollbackVerification {
        let project = try validatedProjectURL(record.projectPath)
        let snapshotURL = URL(fileURLWithPath: record.snapshotPath, isDirectory: true)
        guard fileManager.fileExists(atPath: snapshotURL.path) else {
            throw CheckpointError.io("找不到 checkpoint 快照：\(record.id)")
        }

        lock.lock()
        defer { lock.unlock() }

        if let git = record.git {
            return try rollbackGit(record: record, metadata: git)
        }

        let expected = Set(record.files.map(\.relativePath))
        let current = try enumerate(projectURL: project)
        var removed = 0
        for item in current where item.relativePath != ".git" && !item.relativePath.hasPrefix(".git/") {
            guard !expected.contains(item.relativePath) else { continue }
            try remove(project: project, relativePath: item.relativePath)
            removed += 1
        }

        var restored = 0
        // Directories first so files can always be copied into their parents.
        for item in record.files.sorted(by: { lhs, rhs in
            if lhs.kind == rhs.kind { return lhs.relativePath < rhs.relativePath }
            return lhs.kind == .directory
        }) {
            let destination = try safeChild(project, relativePath: item.relativePath)
            switch item.kind {
            case .directory:
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            case .file:
                let source = try safeChild(snapshotURL, relativePath: item.relativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
                restored += 1
            case .symbolicLink:
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                guard let linkDestination = item.linkDestination else {
                    throw CheckpointError.io("checkpoint 符号链接缺少目标：\(item.relativePath)")
                }
                try fileManager.createSymbolicLink(atPath: destination.path, withDestinationPath: linkDestination)
                restored += 1
            }
            if let permissions = item.permissions {
                try? fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: permissions)],
                    ofItemAtPath: destination.path
                )
            }
        }

        let finalFiles = try enumerate(projectURL: project, includeDigests: true)
            .filter { $0.relativePath != ".git" && !$0.relativePath.hasPrefix(".git/") }
        let finalMap = Dictionary(uniqueKeysWithValues: finalFiles.map { ($0.relativePath, $0) })
        var missing: [String] = []
        for expectedRecord in record.files where expectedRecord.relativePath != ".git" {
            guard let actual = finalMap[expectedRecord.relativePath], actual.kind == expectedRecord.kind else {
                missing.append(expectedRecord.relativePath)
                continue
            }
            if expectedRecord.kind == .file {
                let expectedDigest = expectedRecord.digest ?? {
                    let snapshotFile = try? safeChild(snapshotURL, relativePath: expectedRecord.relativePath)
                    guard let snapshotFile else { return nil }
                    return try? digest(at: snapshotFile)
                }()
                if expectedDigest == nil || actual.digest != expectedDigest {
                    missing.append(expectedRecord.relativePath)
                }
            }
        }
        let unexpected = finalMap.keys.filter { !expected.contains($0) }.sorted()
        return RollbackVerification(
            checkpointID: record.id,
            verified: missing.isEmpty && unexpected.isEmpty,
            restoredFiles: restored,
            removedFiles: removed,
            missingFiles: missing.sorted(),
            unexpectedFiles: unexpected
        )
    }

    private func gitRepository(for projectURL: URL) throws -> URL? {
        guard let output = try? runGit(["rev-parse", "--show-toplevel"], workingDirectory: projectURL),
              let path = String(data: output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }
        let repository = URL(fileURLWithPath: path).standardizedFileURL
        // A checkpoint for a subdirectory must not reset files outside that
        // directory. Use the Git fast path only when the selected project is
        // the repository root; nested projects use the safe file snapshot.
        guard repository.path == projectURL.resolvingSymlinksInPath().path else { return nil }
        return repository
    }

    private func captureGitCheckpoint(
        projectURL: URL,
        repositoryURL: URL,
        checkpointURL: URL,
        snapshotURL: URL
    ) throws -> GitCheckpointMetadata {
        let patchPath = checkpointURL.appendingPathComponent("git-baseline.patch")
        let patch = try runGit(["diff", "--binary", "HEAD", "--", "."], workingDirectory: repositoryURL)
        try patch.write(to: patchPath, options: .atomic)

        let rawUntracked = try runGit(
            ["ls-files", "--others", "--exclude-standard", "-z"],
            workingDirectory: repositoryURL
        )
        let untrackedPaths = rawUntracked
            .split(separator: 0, omittingEmptySubsequences: true)
            .compactMap { String(data: Data($0), encoding: .utf8) }
            .filter { !$0.isEmpty }
            .sorted()
        let untrackedSnapshot = snapshotURL.appendingPathComponent("untracked", isDirectory: true)
        try fileManager.createDirectory(at: untrackedSnapshot, withIntermediateDirectories: true)
        for relativePath in untrackedPaths {
            let source = try safeChild(projectURL, relativePath: relativePath)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = try safeChild(untrackedSnapshot, relativePath: relativePath)
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
        return GitCheckpointMetadata(
            repositoryPath: repositoryURL.path,
            patchPath: patchPath.path,
            untrackedSnapshotPath: untrackedSnapshot.path,
            untrackedPaths: untrackedPaths
        )
    }

    private func runGit(_ arguments: [String], workingDirectory: URL) throws -> Data {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.currentDirectoryURL = workingDirectory
        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr
        do {
            try task.run()
        } catch {
            throw CheckpointError.io("无法启动 Git checkpoint：\(error.localizedDescription)")
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let detail = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CheckpointError.io(detail?.isEmpty == false ? detail! : "Git checkpoint 命令失败")
        }
        return output
    }

    private func rollbackGit(
        record: CheckpointRecord,
        metadata: GitCheckpointMetadata
    ) throws -> RollbackVerification {
        let repository = try validatedProjectURL(metadata.repositoryPath)
        let patchURL = URL(fileURLWithPath: metadata.patchPath)
        guard fileManager.fileExists(atPath: patchURL.path) else {
            throw CheckpointError.io("找不到 Git checkpoint 补丁：\(record.id)")
        }
        let baselinePatch = try Data(contentsOf: patchURL)
        let baselineUntracked = Set(metadata.untrackedPaths)
        let currentUntracked = try gitPaths(
            ["ls-files", "--others", "--exclude-standard", "-z"],
            repository: repository
        )
        let unexpectedBeforeRestore = currentUntracked.subtracting(baselineUntracked)

        _ = try runGit(["restore", "--source=HEAD", "--worktree", "--", "."], workingDirectory: repository)

        // Remove task-created untracked files and empty directories in one
        // Git-aware operation. Ignored build output remains untouched; the
        // baseline untracked files are copied back immediately below.
        _ = try runGit(["clean", "-fd", "--", "."], workingDirectory: repository)

        if !baselinePatch.isEmpty {
            try baselinePatch.write(to: patchURL, options: .atomic)
            _ = try runGit(["apply", "--binary", "--whitespace=nowarn", patchURL.path], workingDirectory: repository)
        }

        for relativePath in unexpectedBeforeRestore {
            let destination = try safeChild(repository, relativePath: relativePath)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
        }
        let sourceRoot = URL(fileURLWithPath: metadata.untrackedSnapshotPath, isDirectory: true)
        for relativePath in baselineUntracked {
            let source = try safeChild(sourceRoot, relativePath: relativePath)
            let destination = try safeChild(repository, relativePath: relativePath)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }

        let finalPatch = try runGit(["diff", "--binary", "HEAD", "--", "."], workingDirectory: repository)
        let finalUntracked = try gitPaths(
            ["ls-files", "--others", "--exclude-standard", "-z"],
            repository: repository
        )
        var missing: [String] = []
        for relativePath in baselineUntracked {
            let expected = try safeChild(sourceRoot, relativePath: relativePath)
            let actual = try safeChild(repository, relativePath: relativePath)
            if !fileManager.fileExists(atPath: expected.path)
                || !fileManager.fileExists(atPath: actual.path)
                || (try? digest(at: expected)) != (try? digest(at: actual)) {
                missing.append(relativePath)
            }
        }
        let missingUntracked = baselineUntracked.subtracting(finalUntracked)
        missing.append(contentsOf: missingUntracked)
        let unexpected = finalUntracked.subtracting(baselineUntracked).sorted()
        let trackedMatches = finalPatch == baselinePatch
        let verified = trackedMatches && missing.isEmpty && unexpected.isEmpty
        let trackedNames = try gitPaths(["diff", "--name-only", "-z", "HEAD", "--", "."], repository: repository)
        return RollbackVerification(
            checkpointID: record.id,
            verified: verified,
            restoredFiles: trackedNames.count + baselineUntracked.count,
            removedFiles: unexpectedBeforeRestore.count,
            missingFiles: missing.sorted(),
            unexpectedFiles: unexpected
        )
    }

    private func gitPaths(_ arguments: [String], repository: URL) throws -> Set<String> {
        let output = try runGit(arguments, workingDirectory: repository)
        return Set(output.split(separator: 0, omittingEmptySubsequences: true).compactMap {
            String(data: Data($0), encoding: .utf8)
        })
    }

    func load(id: String) throws -> CheckpointRecord {
        guard id.range(of: "^[a-f0-9-]+$", options: .regularExpression) != nil else {
            throw CheckpointError.unsafePath(id)
        }
        let manifest = rootURL.appendingPathComponent(id).appendingPathComponent("manifest.json")
        do {
            return try decoder.decode(CheckpointRecord.self, from: Data(contentsOf: manifest))
        } catch {
            throw CheckpointError.io("无法读取 checkpoint：\(id)")
        }
    }

    private func validatedProjectURL(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CheckpointError.projectMissing(path)
        }
        return url
    }

    private func capture(projectURL: URL, snapshotURL: URL) throws -> [CheckpointFileRecord] {
        let entries = try enumerate(projectURL: projectURL)
        var records: [CheckpointFileRecord] = []
        for entry in entries where entry.relativePath != ".git" && !entry.relativePath.hasPrefix(".git/") {
            let source = try safeChild(projectURL, relativePath: entry.relativePath)
            switch entry.kind {
            case .directory:
                try fileManager.createDirectory(
                    at: try safeChild(snapshotURL, relativePath: entry.relativePath),
                    withIntermediateDirectories: true
                )
                records.append(entry)
            case .file:
                let destination = try safeChild(snapshotURL, relativePath: entry.relativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.copyItem(at: source, to: destination)
                records.append(entry)
            case .symbolicLink:
                records.append(entry)
            }
        }
        return records
    }

    private func enumerate(projectURL: URL, includeDigests: Bool = false) throws -> [CheckpointFileRecord] {
        let traversalRoot = projectURL.resolvingSymlinksInPath()
        guard let enumerator = fileManager.enumerator(
            at: traversalRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileResourceIdentifierKey],
            options: []
        ) else {
            throw CheckpointError.io("无法扫描项目目录：\(projectURL.path)")
        }
        var records: [CheckpointFileRecord] = []
        for case let url as URL in enumerator {
            // FileManager may return /private/var URLs even when the caller
            // supplied the /var alias. Derive the suffix by components so a
            // harmless filesystem alias can never become an unsafe path.
            let rootName = traversalRoot.lastPathComponent
            let components = url.pathComponents
            guard let rootIndex = components.lastIndex(of: rootName), rootIndex + 1 < components.count else {
                continue
            }
            let relative = components[(rootIndex + 1)...].joined(separator: "/")
            guard !relative.isEmpty else { continue }
            // Check the relative path before asking the filesystem for more
            // metadata. On a slow external volume even a resourceValues call
            // for the top-level build directory can block; skipping by path
            // lets the enumerator prune it immediately.
            if relative.split(separator: "/").contains(where: {
                Self.skippedDirectoryNames.contains(String($0))
            }) {
                enumerator.skipDescendants()
                continue
            }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isDirectory == true,
               Self.skippedDirectoryNames.contains(url.lastPathComponent)
            {
                enumerator.skipDescendants()
                continue
            }
            if relative == ".git" || relative.hasPrefix(".git/") {
                enumerator.skipDescendants()
                continue
            }
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            let permissions = (attributes?[.posixPermissions] as? NSNumber).map { UInt16(truncating: $0) }
            if let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) {
                records.append(CheckpointFileRecord(
                    relativePath: relative,
                    kind: .symbolicLink,
                    digest: nil,
                    linkDestination: destination,
                    permissions: permissions
                ))
            } else if values.isDirectory == true {
                records.append(CheckpointFileRecord(
                    relativePath: relative,
                    kind: .directory,
                    digest: nil,
                    linkDestination: nil,
                    permissions: permissions
                ))
            } else {
                records.append(CheckpointFileRecord(
                    relativePath: relative,
                    kind: .file,
                    // Hashing every source file before the task doubles the
                    // external-volume reads. Rollback performs the full hash
                    // verification after restoring; creation only needs to
                    // copy the bytes into the snapshot.
                    digest: includeDigests ? try digest(at: url) : nil,
                    linkDestination: nil,
                    permissions: permissions
                ))
            }
        }
        return records
    }

    private func digest(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
#if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
#else
        // CryptoKit is present on all supported macOS builds; keep a stable
        // fallback for source-only Linux contract tests.
        return data.base64EncodedString()
#endif
    }

    private func remove(project: URL, relativePath: String) throws {
        let destination = try safeChild(project, relativePath: relativePath)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }

    private func safeChild(_ root: URL, relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            throw CheckpointError.unsafePath(relativePath)
        }
        let child = root.appendingPathComponent(relativePath).standardizedFileURL
        guard child.path == root.standardizedFileURL.path || child.path.hasPrefix(root.standardizedFileURL.path + "/") else {
            throw CheckpointError.unsafePath(relativePath)
        }
        return child
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
