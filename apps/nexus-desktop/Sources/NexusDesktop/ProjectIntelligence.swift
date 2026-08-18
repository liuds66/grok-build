import Foundation
import Darwin

#if canImport(CryptoKit)
import CryptoKit
#endif

// MARK: - Project Intelligence 数据模型

/// 索引 schema 版本。版本不兼容时安全丢弃旧索引并重建，而不是让旧数据
/// 通过解码错误把整个桌面端拖垮。
let projectIntelligenceIndexVersion = 1

enum ProjectIntelligenceStatus: String, Codable {
    case idle
    case scanning
    case indexing
    case ready
    case stale
    case error
}

struct StackSignal: Codable, Equatable {
    let name: String
    let confidence: Double
    let evidence: [String]
}

struct Project: Codable, Equatable {
    let projectId: String
    let rootPath: String
    let name: String
    let gitRoot: String?
    let branch: String?
    let headCommit: String?
    let languages: [String]
    let frameworks: [String]
    let frameworkConfidence: [String: Double]
    let packageManagers: [String]
    let buildSystems: [String]
    let entryPoints: [String]
    let lastIndexedAt: Date
    let indexVersion: Int
    let dirtyFiles: [String]
    let recentChangedFiles: [String]
}

struct SymbolNode: Codable, Equatable {
    let symbolId: String
    let name: String
    let kind: String
    let file: String
    let lineStart: Int
    let lineEnd: Int
    let signature: String
    let visibility: String
    let parentSymbol: String?
}

struct FileNode: Codable, Equatable {
    let path: String
    let relativePath: String
    let language: String?
    let size: Int64
    let modifiedAt: Date
    let hash: String?
    let role: String
    let module: String?
    var symbols: [SymbolNode]
    var imports: [String]
    var exports: [String]
    var dependencies: [String]
    var testTargets: [String]
    let sensitive: Bool
}

struct DependencyEdge: Codable, Equatable {
    let from: String
    let to: String
    let type: String
}

struct ModuleNode: Codable, Equatable {
    let name: String
    let path: String
    let files: [String]
    let dependencies: [String]
    let entryPoints: [String]
    let tests: [String]
}

struct TestNode: Codable, Equatable {
    let path: String
    let framework: String?
    let targetFiles: [String]
    let commands: [String]
}

struct TaskKnowledge: Codable, Equatable {
    let taskId: String
    let summary: String
    let filesRead: [String]
    let filesChanged: [String]
    let symbolsChanged: [String]
    let verification: [String]
    let finalState: String
    let recordedAt: Date
}

struct ProjectIntelligenceIndex: Codable, Equatable {
    let indexVersion: Int
    let project: Project
    let files: [FileNode]
    let symbols: [SymbolNode]
    let dependencies: [DependencyEdge]
    let modules: [ModuleNode]
    let tests: [TestNode]
    var taskKnowledge: [TaskKnowledge]
    let generatedAt: Date
    let reusedFileCount: Int
    let changedFileCount: Int
    let warnings: [String]

    var fileCount: Int { files.count }
    var moduleCount: Int { modules.count }
    var symbolCount: Int { symbols.count }
    var testCount: Int { tests.count }
}

struct ProjectIntelligenceOverview: Equatable {
    let status: ProjectIntelligenceStatus
    let index: ProjectIntelligenceIndex?
    let error: String?
}

// MARK: - 安全与确定性工具

private enum ProjectIntelligenceError: LocalizedError {
    case projectMissing(String)
    case unsafeProject(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .projectMissing(let path): return "项目目录不存在：\(path)"
        case .unsafeProject(let path): return "拒绝扫描不安全项目路径：\(path)"
        case .unreadable(let path): return "无法读取项目：\(path)"
        }
    }
}

private enum ProjectIntelligenceDigest {
    static func hex(_ data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        var value: UInt64 = 14695981039346656037
        for byte in data { value = (value ^ UInt64(byte)) &* 1099511628211 }
        return String(format: "%016llx", value)
        #endif
    }

    static func file(_ url: URL, size: Int64, modifiedAt: Date) -> String? {
        guard size <= 8 * 1024 * 1024,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            // 大型文件不读入内存；元数据摘要仍能稳定地参与增量比较，且
            // 不会把构建产物拖进索引。
            return hex(Data("\(url.path)|\(size)|\(modifiedAt.timeIntervalSince1970)".utf8))
        }
        return hex(data)
    }

    static func string(_ value: String) -> String {
        hex(Data(value.utf8))
    }
}

private extension String {
    var projectIntelligenceTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func projectIntelligenceCapped(_ value: String, _ limit: Int = 240) -> String {
    guard value.count > limit else { return value }
    return String(value.prefix(limit)) + "…"
}

private enum ProjectIntelligenceRedaction {
    private static let patterns: [(String, String)] = [
        (#"(?i)sk-[A-Za-z0-9_.*=\-]{8,}"#, "<redacted-key>"),
        (#"(?i)xai-[A-Za-z0-9_.*=\-]{8,}"#, "<redacted-key>"),
        (#"(?i)(bearer\s+)[A-Za-z0-9._~+\-/=]+"#, "$1<redacted-key>"),
        (#"(?i)(api[_-]?key\s*[=:]\s*)[^\s,&]+"#, "$1<redacted-key>"),
        (#"(?i)(password|secret|token)\s*[=:]\s*[^\s,&]+"#, "$1=<redacted>"),
    ]

    static func text(_ value: String, limit: Int = 600) -> String {
        var result = value
        for (pattern, replacement) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            result = expression.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..<result.endIndex, in: result),
                withTemplate: replacement
            )
        }
        return projectIntelligenceCapped(result, limit)
    }
}

private func projectIntelligenceSanitizeKnowledge(_ knowledge: TaskKnowledge) -> TaskKnowledge {
    TaskKnowledge(
        taskId: ProjectIntelligenceRedaction.text(knowledge.taskId, limit: 128),
        summary: ProjectIntelligenceRedaction.text(knowledge.summary),
        filesRead: knowledge.filesRead.prefix(80).map { ProjectIntelligenceRedaction.text($0, limit: 240) },
        filesChanged: knowledge.filesChanged.prefix(80).map { ProjectIntelligenceRedaction.text($0, limit: 240) },
        symbolsChanged: knowledge.symbolsChanged.prefix(80).map { ProjectIntelligenceRedaction.text($0, limit: 240) },
        verification: knowledge.verification.prefix(80).map { ProjectIntelligenceRedaction.text($0, limit: 240) },
        finalState: ProjectIntelligenceRedaction.text(knowledge.finalState, limit: 64),
        recordedAt: knowledge.recordedAt
    )
}

private func projectIntelligenceSanitizeIndex(_ index: ProjectIntelligenceIndex) -> ProjectIntelligenceIndex {
    var result = index
    result.taskKnowledge = index.taskKnowledge.map(projectIntelligenceSanitizeKnowledge)
    return result
}

// MARK: - Project Scanner

final class ProjectIntelligenceScanner {
    static let defaultExcludedDirectories: Set<String> = [
        ".git", "node_modules", "target", "dist", "build", "DerivedData",
        ".venv", "venv", "__pycache__", "coverage", ".cache", ".next",
        ".turbo", ".swiftpm", "Pods", "vendor",
    ]

    private let fileManager = FileManager.default
    private let maxFiles: Int

    init(maxFiles: Int = 100_000) {
        self.maxFiles = max(1_000, maxFiles)
    }

    func scan(projectPath: String, previous: ProjectIntelligenceIndex? = nil) throws -> ProjectIntelligenceIndex {
        let projectURL = try validatedProjectURL(projectPath)
        let canonicalPath = projectURL.path
        let gitRoot = gitValue(["-C", canonicalPath, "rev-parse", "--show-toplevel"])
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        let repositoryIdentity = gitValue(["-C", canonicalPath, "config", "--get", "remote.origin.url"])
        let projectID = Self.projectID(rootPath: canonicalPath, gitRoot: gitRoot, repositoryIdentity: repositoryIdentity)
        let ignorePatterns = loadIgnorePatterns(projectURL: projectURL)
        let previousFiles = previous?.project.projectId == projectID
            && previous?.indexVersion == projectIntelligenceIndexVersion
            ? Dictionary(uniqueKeysWithValues: (previous?.files ?? []).map { ($0.relativePath, $0) })
            : [:]

        var warnings: [String] = []
        var files: [FileNode] = []
        var reused = 0
        var changed = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(
            at: projectURL,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            throw ProjectIntelligenceError.unreadable(canonicalPath)
        }

        while let item = enumerator.nextObject() as? URL {
            if files.count >= maxFiles {
                warnings.append("索引达到文件上限 \(maxFiles)，其余文件未纳入。")
                break
            }
            let relative = relativePath(item, projectURL: projectURL)
            if relative.isEmpty { continue }
            let components = relative.split(separator: "/").map(String.init)
            if components.contains(where: { Self.defaultExcludedDirectories.contains($0) })
                || matchesIgnore(relative, patterns: ignorePatterns) {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if components.contains(where: { Self.defaultExcludedDirectories.contains($0) }) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile != false else { continue }
            let resolved = item.resolvingSymlinksInPath()
            guard resolved.path == canonicalPath || resolved.path.hasPrefix(canonicalPath + "/") else {
                warnings.append("跳过指向项目外的链接：\(relative)")
                continue
            }
            let size = Int64(values?.fileSize ?? 0)
            let modified = values?.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            let sensitive = Self.isSensitive(relativePath: relative)
            if let old = previousFiles[relative],
               old.size == size, abs(old.modifiedAt.timeIntervalSince(modified)) < 0.001 {
                // Sensitive files are still reusable by metadata only. We do
                // not read their contents or derive a content hash; reusing
                // the previous metadata keeps incremental scans quiet while
                // preserving the no-secrets-in-index guarantee.
                files.append(old)
                reused += 1
                continue
            }
            changed += 1
            files.append(makeFileNode(
                fileURL: item,
                relativePath: relative,
                size: size,
                modifiedAt: modified,
                sensitive: sensitive,
                projectURL: projectURL
            ))
        }

        let knownPaths = Set(files.map(\.relativePath))
        var filesWithTests = files
        let testPaths = files.filter { $0.role == "test" }.map(\.relativePath)
        for index in filesWithTests.indices {
            if filesWithTests[index].role == "test" { continue }
            let base = URL(fileURLWithPath: filesWithTests[index].relativePath).deletingPathExtension().lastPathComponent.lowercased()
            filesWithTests[index].testTargets = testPaths.filter { test in
                let testBase = URL(fileURLWithPath: test).deletingPathExtension().lastPathComponent.lowercased()
                return testBase.contains(base) || base.contains(testBase.replacingOccurrences(of: ".test", with: "").replacingOccurrences(of: ".spec", with: ""))
            }.prefix(8).map { $0 }
        }

        let dependencies = makeDependencyEdges(files: &filesWithTests, knownPaths: knownPaths)
        let modules = makeModules(files: filesWithTests, dependencies: dependencies)
        let tests = makeTests(files: filesWithTests, projectURL: projectURL)
        let project = makeProject(
            projectID: projectID,
            projectURL: projectURL,
            gitRoot: gitRoot,
            files: filesWithTests,
            modules: modules,
            tests: tests
        )
        let symbols = filesWithTests.flatMap(\.symbols).sorted {
            ($0.file, $0.lineStart, $0.name) < ($1.file, $1.lineStart, $1.name)
        }
        let oldKnowledge = previous?.project.projectId == projectID && previous?.indexVersion == projectIntelligenceIndexVersion
            ? (previous?.taskKnowledge ?? [])
            : []
        return ProjectIntelligenceIndex(
            indexVersion: projectIntelligenceIndexVersion,
            project: project,
            files: filesWithTests.sorted { $0.relativePath < $1.relativePath },
            symbols: symbols,
            dependencies: dependencies.sorted { ($0.from, $0.to, $0.type) < ($1.from, $1.to, $1.type) },
            modules: modules.sorted { $0.name < $1.name },
            tests: tests.sorted { $0.path < $1.path },
            taskKnowledge: oldKnowledge,
            generatedAt: Date(),
            reusedFileCount: reused,
            changedFileCount: changed,
            warnings: warnings
        )
    }

    static func projectID(rootPath: String, gitRoot: String?, repositoryIdentity: String?) -> String {
        let seed = [rootPath, gitRoot ?? "", repositoryIdentity ?? ""].joined(separator: "\n")
        return String(ProjectIntelligenceDigest.string(seed).prefix(32))
    }

    private func validatedProjectURL(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProjectIntelligenceError.projectMissing(path)
        }
        let home = fileManager.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        let denied = ["/", "/System", "/Library", home + "/.ssh", home + "/.gnupg", home + "/.aws"]
        guard !denied.contains(url.path) else { throw ProjectIntelligenceError.unsafeProject(url.path) }
        return url
    }

    private func loadIgnorePatterns(projectURL: URL) -> [String] {
        guard let content = try? String(contentsOf: projectURL.appendingPathComponent(".gitignore"), encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.projectIntelligenceTrimmed
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }
            return trimmed
        }
    }

    private func matchesIgnore(_ relative: String, patterns: [String]) -> Bool {
        var ignored = false
        for raw in patterns {
            let negated = raw.hasPrefix("!")
            let pattern = negated ? String(raw.dropFirst()) : raw
            let normalized = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let base = URL(fileURLWithPath: relative).lastPathComponent
            let match = relative == normalized
                || relative.hasPrefix(normalized + "/")
                || base == normalized
                || (normalized.hasSuffix("/") && relative.hasPrefix(normalized))
                || globMatch(relative, pattern: normalized)
            if match { ignored = !negated }
        }
        return ignored
    }

    private func globMatch(_ path: String, pattern: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "\\?", with: "[^/]")
        return path.range(of: "^" + escaped + "$", options: .regularExpression) != nil
    }

    private func relativePath(_ url: URL, projectURL: URL) -> String {
        let prefix = projectURL.path.hasSuffix("/") ? projectURL.path : projectURL.path + "/"
        let itemPath = url.resolvingSymlinksInPath().path
        return itemPath.hasPrefix(prefix) ? String(itemPath.dropFirst(prefix.count)) : ""
    }

    private static func isSensitive(relativePath: String) -> Bool {
        let lower = relativePath.lowercased()
        let name = URL(fileURLWithPath: relativePath).lastPathComponent.lowercased()
        return name == ".env" || name.hasPrefix(".env.") || name.contains("credential")
            || name.contains("secret") || name == "id_rsa" || name == "id_ed25519"
            || [".pem", ".key", ".p12", ".pfx"].contains(where: { name.hasSuffix($0) })
            || lower.contains("/.ssh/")
    }

    private func makeFileNode(
        fileURL: URL,
        relativePath: String,
        size: Int64,
        modifiedAt: Date,
        sensitive: Bool,
        projectURL: URL
    ) -> FileNode {
        let language = languageFor(path: relativePath)
        let role = roleFor(path: relativePath, language: language)
        let module = moduleFor(path: relativePath)
        guard !sensitive, size <= 2 * 1024 * 1024,
              let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              !isBinary(data) else {
            return FileNode(
                path: fileURL.path, relativePath: relativePath, language: language,
                size: size, modifiedAt: modifiedAt,
                hash: sensitive ? nil : ProjectIntelligenceDigest.file(fileURL, size: size, modifiedAt: modifiedAt),
                role: role, module: module, symbols: [], imports: [], exports: [], dependencies: [], testTargets: [], sensitive: sensitive
            )
        }
        let text = String(decoding: data, as: UTF8.self)
        let parsed = parseSource(text, path: relativePath, language: language)
        return FileNode(
            path: fileURL.path, relativePath: relativePath, language: language,
            size: size, modifiedAt: modifiedAt, hash: ProjectIntelligenceDigest.hex(data),
            role: role, module: module, symbols: parsed.symbols, imports: parsed.imports,
            exports: parsed.exports, dependencies: [], testTargets: [], sensitive: false
        )
    }

    private func isBinary(_ data: Data) -> Bool {
        data.prefix(4096).contains(0)
    }

    private func languageFor(path: String) -> String? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let values: [String: String] = [
            "ts": "TypeScript", "tsx": "TypeScript", "mts": "TypeScript", "cts": "TypeScript",
            "js": "JavaScript", "jsx": "JavaScript", "mjs": "JavaScript", "cjs": "JavaScript",
            "rs": "Rust", "py": "Python", "swift": "Swift", "go": "Go",
            "java": "Java", "kt": "Kotlin", "c": "C", "cc": "C++", "cpp": "C++", "h": "C/C++",
            "md": "Markdown", "json": "JSON", "toml": "TOML", "yaml": "YAML", "yml": "YAML",
        ]
        return values[ext]
    }

    private func roleFor(path: String, language: String?) -> String {
        let lower = path.lowercased()
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if name == ".env" || name.hasPrefix(".env.") || lower.contains("/config") { return "config" }
        if ["md", "mdx", "txt", "rst"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) { return "documentation" }
        if lower.contains("test") || lower.contains("spec") || lower.contains("__tests__") || lower.contains("/tests/") { return "test" }
        if lower.contains("generated") || lower.contains("/build/") || lower.contains("/dist/") { return "generated" }
        return language == nil ? "other" : "source"
    }

    private func moduleFor(path: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nil }
        if components.count == 1 { return "根模块" }
        return components[0]
    }

    private func parseSource(_ text: String, path: String, language: String?) -> (symbols: [SymbolNode], imports: [String], exports: [String]) {
        guard let language else { return ([], [], []) }
        let lines = text.components(separatedBy: .newlines)
        var symbols: [SymbolNode] = []
        var imports: [String] = []
        var exports: [String] = []
        let symbolPatterns: [(String, String)]
        switch language {
        case "TypeScript", "JavaScript":
            symbolPatterns = [
                ("function", #"(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)"#),
                ("class", #"(?:export\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)"#),
                ("interface", #"(?:export\s+)?interface\s+([A-Za-z_$][\w$]*)"#),
                ("type", #"(?:export\s+)?type\s+([A-Za-z_$][\w$]*)"#),
                ("variable", #"(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)"#),
            ]
        case "Rust":
            symbolPatterns = [
                ("function", #"(?:pub\s+)?(?:async\s+)?fn\s+([A-Za-z_][\w]*)"#),
                ("struct", #"(?:pub\s+)?struct\s+([A-Za-z_][\w]*)"#),
                ("enum", #"(?:pub\s+)?enum\s+([A-Za-z_][\w]*)"#),
                ("trait", #"(?:pub\s+)?trait\s+([A-Za-z_][\w]*)"#),
                ("module", #"(?:pub\s+)?mod\s+([A-Za-z_][\w]*)"#),
            ]
        case "Python":
            symbolPatterns = [
                ("function", #"(?:async\s+)?def\s+([A-Za-z_][\w]*)"#),
                ("class", #"class\s+([A-Za-z_][\w]*)"#),
            ]
        case "Swift":
            symbolPatterns = [
                ("function", #"(?:public\s+|private\s+|internal\s+|static\s+|class\s+)*func\s+([A-Za-z_][\w]*)"#),
                ("type", #"(?:public\s+|private\s+|internal\s+)*\b(struct|class|enum|protocol|actor)\s+([A-Za-z_][\w]*)"#),
            ]
        case "Go":
            symbolPatterns = [
                ("function", #"func\s+(?:\([^)]*\)\s*)?([A-Za-z_][\w]*)"#),
                ("type", #"type\s+([A-Za-z_][\w]*)\s+(struct|interface)"#),
            ]
        default:
            symbolPatterns = []
        }
        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1
            let trimmed = line.projectIntelligenceTrimmed
            for (kind, pattern) in symbolPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
                let nameRangeIndex = kind == "type" && language == "Swift" ? 2 : 1
                guard match.numberOfRanges > nameRangeIndex,
                      let range = Range(match.range(at: nameRangeIndex), in: line) else { continue }
                let name = String(line[range])
                let visibility = trimmed.hasPrefix("pub ") || trimmed.hasPrefix("public ") ? "public" : "internal"
                symbols.append(SymbolNode(
                    symbolId: ProjectIntelligenceDigest.string("\(path):\(lineNumber):\(name)"),
                    name: name, kind: kind, file: path, lineStart: lineNumber, lineEnd: lineNumber,
                    signature: projectIntelligenceCapped(trimmed), visibility: visibility, parentSymbol: nil
                ))
                break
            }
            let importPatterns: [String] = {
                switch language {
                case "TypeScript", "JavaScript": return [#"(?:from\s+|import\s*\(\s*|require\(\s*)["']([^"']+)["']"#]
                case "Rust": return [#"(?:use|mod)\s+([A-Za-z0-9_:/-]+)"#]
                case "Python": return [#"(?:from|import)\s+([A-Za-z0-9_./-]+)"#]
                case "Swift": return [#"import\s+([A-Za-z0-9_.]+)"#]
                case "Go": return [#"import\s+"([^"]+)""#]
                default: return []
                }
            }()
            for pattern in importPatterns {
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      match.numberOfRanges > 1,
                      let range = Range(match.range(at: 1), in: line) else { continue }
                let value = String(line[range]).projectIntelligenceTrimmed
                if !value.isEmpty && !imports.contains(value) { imports.append(value) }
            }
            if trimmed.hasPrefix("export ") || trimmed.contains(" export ") { exports.append(contentsOf: symbols.last.map { [$0.name] } ?? []) }
        }
        return (symbols, imports.sorted(), Array(Set(exports)).sorted())
    }

    private func makeDependencyEdges(files: inout [FileNode], knownPaths: Set<String>) -> [DependencyEdge] {
        var edges: [DependencyEdge] = []
        for index in files.indices {
            let file = files[index]
            var resolved: [String] = []
            for imported in file.imports {
                if let target = resolveImport(imported, from: file.relativePath, knownPaths: knownPaths) {
                    resolved.append(target)
                    edges.append(DependencyEdge(from: file.relativePath, to: target, type: "import"))
                }
            }
            files[index].dependencies = Array(Set(resolved)).sorted()
        }
        var unique: [String: DependencyEdge] = [:]
        for edge in edges { unique["\(edge.from)\u{1f}\(edge.to)\u{1f}\(edge.type)"] = edge }
        return unique.values.sorted { ($0.from, $0.to, $0.type) < ($1.from, $1.to, $1.type) }
    }

    private func resolveImport(_ imported: String, from path: String, knownPaths: Set<String>) -> String? {
        let cleaned = imported.replacingOccurrences(of: "\\", with: "/")
        let candidates: [String]
        if cleaned.hasPrefix(".") {
            let directory = (path as NSString).deletingLastPathComponent
            let joined = (directory == "." ? "" : directory + "/") + cleaned
            let normalized = joined.replacingOccurrences(of: "./", with: "")
            candidates = [normalized, normalized + ".ts", normalized + ".tsx", normalized + ".js", normalized + ".rs"]
        } else {
            let suffix = "/" + cleaned
            candidates = knownPaths.filter { $0 == cleaned || $0.hasSuffix(suffix) }.sorted()
        }
        for candidate in candidates {
            let normalized = candidate.hasPrefix("/") ? String(candidate.dropFirst()) : candidate
            if knownPaths.contains(candidate) { return candidate }
            if knownPaths.contains(normalized) { return normalized }
        }
        return nil
    }

    private func makeModules(files: [FileNode], dependencies: [DependencyEdge]) -> [ModuleNode] {
        let groups = Dictionary(grouping: files) { $0.module ?? "根模块" }
        return groups.map { name, group in
            let paths = Set(group.map(\.relativePath))
            let moduleDeps = dependencies.filter { paths.contains($0.from) }.map(\.to)
            let entries = group.filter { isEntryPoint($0.relativePath) }.map(\.relativePath)
            return ModuleNode(
                name: name,
                path: name == "根模块" ? "." : name,
                files: group.map(\.relativePath).sorted(),
                dependencies: Array(Set(moduleDeps)).sorted(),
                entryPoints: entries.sorted(),
                tests: group.filter { $0.role == "test" }.map(\.relativePath).sorted()
            )
        }
    }

    private func makeTests(files: [FileNode], projectURL: URL) -> [TestNode] {
        let commands: [String]
        if fileManager.fileExists(atPath: projectURL.appendingPathComponent("package.json").path) { commands = ["npm test"] }
        else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) { commands = ["cargo test"] }
        else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("pyproject.toml").path) { commands = ["pytest"] }
        else if fileManager.fileExists(atPath: projectURL.appendingPathComponent("go.mod").path) { commands = ["go test ./..."] }
        else { commands = [] }
        return files.filter { $0.role == "test" }.map { file in
            let framework: String?
            switch file.language {
            case "TypeScript", "JavaScript": framework = "Jest/Vitest"
            case "Rust": framework = "cargo test"
            case "Python": framework = "pytest"
            case "Go": framework = "go test"
            case "Swift": framework = "XCTest"
            default: framework = nil
            }
            let base = URL(fileURLWithPath: file.relativePath).deletingPathExtension().lastPathComponent
            let targets = files.filter { $0.role == "source" && URL(fileURLWithPath: $0.relativePath).deletingPathExtension().lastPathComponent.lowercased().contains(base.lowercased().replacingOccurrences(of: ".test", with: "").replacingOccurrences(of: ".spec", with: "")) }.map(\.relativePath).prefix(8)
            return TestNode(path: file.relativePath, framework: framework, targetFiles: Array(targets), commands: commands)
        }
    }

    private func makeProject(projectID: String, projectURL: URL, gitRoot: String?, files: [FileNode], modules: [ModuleNode], tests: [TestNode]) -> Project {
        var languages = Set<String>()
        for language in files.compactMap(\.language) { languages.insert(language) }
        let stack = detectStack(projectURL: projectURL)
        let entryPoints = files.map(\.relativePath).filter(isEntryPoint)
        let status = gitValue(["-C", projectURL.path, "status", "--short"]) ?? ""
        let dirty = status.split(separator: "\n").compactMap { line in
            let raw = String(line)
            return raw.count > 3 ? String(raw.dropFirst(3)).projectIntelligenceTrimmed : nil
        }
        let recent = (gitValue(["-C", projectURL.path, "diff", "--name-only", "HEAD"]) ?? "").split(separator: "\n").map(String.init)
        return Project(
            projectId: projectID,
            rootPath: projectURL.path,
            name: projectURL.lastPathComponent,
            gitRoot: gitRoot,
            branch: gitValue(["-C", projectURL.path, "branch", "--show-current"]),
            headCommit: gitValue(["-C", projectURL.path, "rev-parse", "HEAD"]),
            languages: languages.sorted(), frameworks: stack.map(\.name).sorted(),
            frameworkConfidence: Dictionary(uniqueKeysWithValues: stack.map { ($0.name, $0.confidence) }),
            packageManagers: packageManagers(projectURL: projectURL),
            buildSystems: buildSystems(projectURL: projectURL), entryPoints: entryPoints.sorted(),
            lastIndexedAt: Date(), indexVersion: projectIntelligenceIndexVersion,
            dirtyFiles: dirty.sorted(), recentChangedFiles: recent.sorted()
        )
    }

    private func detectStack(projectURL: URL) -> [StackSignal] {
        let fm = fileManager
        var signals: [StackSignal] = []
        if let data = try? Data(contentsOf: projectURL.appendingPathComponent("package.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let dependencies = Array((json["dependencies"] as? [String: Any] ?? [:]).keys)
            let devDependencies = Array((json["devDependencies"] as? [String: Any] ?? [:]).keys)
            let all = Set(dependencies + devDependencies)
            if all.contains("react") { signals.append(StackSignal(name: "React", confidence: 0.98, evidence: ["package.json:react"])) }
            if all.contains("vite") { signals.append(StackSignal(name: "Vite", confidence: 0.98, evidence: ["package.json:vite"])) }
            if all.contains("next") { signals.append(StackSignal(name: "Next.js", confidence: 0.98, evidence: ["package.json:next"])) }
            if fm.fileExists(atPath: projectURL.appendingPathComponent("electron").path) { signals.append(StackSignal(name: "Electron", confidence: 0.72, evidence: ["electron/"])) }
        }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("Cargo.toml").path) { signals.append(StackSignal(name: "Rust", confidence: 0.99, evidence: ["Cargo.toml"])) }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("Package.swift").path) { signals.append(StackSignal(name: "Swift", confidence: 0.99, evidence: ["Package.swift"])) }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("pyproject.toml").path) || fm.fileExists(atPath: projectURL.appendingPathComponent("requirements.txt").path) { signals.append(StackSignal(name: "Python", confidence: 0.96, evidence: ["Python project manifest"])) }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("go.mod").path) { signals.append(StackSignal(name: "Go", confidence: 0.99, evidence: ["go.mod"])) }
        if fm.fileExists(atPath: projectURL.appendingPathComponent("platformio.ini").path) { signals.append(StackSignal(name: "PlatformIO", confidence: 0.99, evidence: ["platformio.ini"])) }
        return signals
    }

    private func packageManagers(projectURL: URL) -> [String] {
        let names = ["package-lock.json": "npm", "yarn.lock": "Yarn", "pnpm-lock.yaml": "pnpm", "Cargo.lock": "Cargo", "poetry.lock": "Poetry", "requirements.txt": "pip", "go.sum": "Go modules"]
        return names.compactMap { fileManager.fileExists(atPath: projectURL.appendingPathComponent($0.key).path) ? $0.value : nil }.sorted()
    }

    private func buildSystems(projectURL: URL) -> [String] {
        var values: [String] = []
        let names = ["Cargo.toml": "Cargo", "Package.swift": "SwiftPM", "Makefile": "Make", "CMakeLists.txt": "CMake", "go.mod": "Go", "package.json": "npm scripts", "platformio.ini": "PlatformIO"]
        for (file, system) in names where fileManager.fileExists(atPath: projectURL.appendingPathComponent(file).path) { values.append(system) }
        return values.sorted()
    }

    private func isEntryPoint(_ path: String) -> Bool {
        let lower = path.lowercased()
        let names = ["main.swift", "main.rs", "main.ts", "main.js", "index.ts", "index.tsx", "index.js", "app.tsx", "app.swift", "manage.py", "main.py"]
        return names.contains(URL(fileURLWithPath: lower).lastPathComponent) || lower.hasSuffix("/cmd/main.go") || lower == "main.go"
    }

    private func gitValue(_ arguments: [String]) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = arguments
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }
        let value = String(data: data, encoding: .utf8)?.projectIntelligenceTrimmed
        return value?.isEmpty == false ? value : nil
    }
}

// MARK: - 本地持久化与增量服务

final class ProjectIntelligenceStore {
    static let shared = ProjectIntelligenceStore()

    let rootURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            // Existing installations keep sessions under Application Support/
            // Nexus (often a symlink to the external data volume). Reuse that
            // application-data root when present; fresh installs use the
            // branded AI Dev One directory. This avoids a second local store
            // and keeps index data beside the existing session abstraction.
            let legacyRoot = support.appendingPathComponent("Nexus", isDirectory: true)
            let appRoot = FileManager.default.fileExists(atPath: legacyRoot.path)
                ? legacyRoot
                : support.appendingPathComponent("AI Dev One", isDirectory: true)
            self.rootURL = appRoot.appendingPathComponent("project-intelligence", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
        encoder = JSONEncoder.nexusIntelligence
        decoder = JSONDecoder.nexusIntelligence
    }

    func projectURL(for projectPath: String) -> URL {
        if let index = load(projectPath: projectPath) {
            return rootURL.appendingPathComponent(index.project.projectId, isDirectory: true)
        }
        let projectID = ProjectIntelligenceScanner.projectID(rootPath: URL(fileURLWithPath: projectPath).standardizedFileURL.resolvingSymlinksInPath().path, gitRoot: nil, repositoryIdentity: nil)
        return rootURL.appendingPathComponent(projectID, isDirectory: true)
    }

    func load(projectPath: String) -> ProjectIntelligenceIndex? {
        let base = rootURL.appendingPathComponent(projectIDForStoredPath(projectPath), isDirectory: true)
        guard let data = try? Data(contentsOf: base.appendingPathComponent("index.json")),
              let index = try? decoder.decode(ProjectIntelligenceIndex.self, from: data),
              index.indexVersion == projectIntelligenceIndexVersion else { return nil }
        let sanitized = projectIntelligenceSanitizeIndex(index)
        if sanitized != index, let cleaned = try? encoder.encode(sanitized) {
            try? cleaned.write(to: base.appendingPathComponent("index.json"), options: .atomic)
        }
        return sanitized
    }

    func load(indexID: String) -> ProjectIntelligenceIndex? {
        let url = rootURL.appendingPathComponent(indexID, isDirectory: true).appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url), let index = try? decoder.decode(ProjectIntelligenceIndex.self, from: data), index.indexVersion == projectIntelligenceIndexVersion else { return nil }
        let sanitized = projectIntelligenceSanitizeIndex(index)
        if sanitized != index, let cleaned = try? encoder.encode(sanitized) {
            try? cleaned.write(to: url, options: .atomic)
        }
        return sanitized
    }

    @discardableResult
    func save(_ index: ProjectIntelligenceIndex) throws -> URL {
        let safeIndex = projectIntelligenceSanitizeIndex(index)
        let directory = rootURL.appendingPathComponent(safeIndex.project.projectId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("index.json")
        try encoder.encode(safeIndex).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    func remove(projectPath: String) {
        guard let index = load(projectPath: projectPath) else { return }
        try? FileManager.default.removeItem(at: rootURL.appendingPathComponent(index.project.projectId, isDirectory: true))
    }

    private func projectIDForStoredPath(_ path: String) -> String {
        if let entries = try? FileManager.default.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) {
            for entry in entries {
                guard let index = load(indexID: entry.lastPathComponent), index.project.rootPath == URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path else { continue }
                return index.project.projectId
            }
        }
        return ProjectIntelligenceScanner.projectID(rootPath: URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path, gitRoot: nil, repositoryIdentity: nil)
    }
}

private extension JSONEncoder {
    static var nexusIntelligence: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var nexusIntelligence: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

final class ProjectIntelligenceService {
    static let shared = ProjectIntelligenceService()

    private let scanner: ProjectIntelligenceScanner
    private let store: ProjectIntelligenceStore
    private let queue = DispatchQueue(label: "cn.ai-dev-one.project-intelligence", qos: .utility)
    private let stateLock = NSLock()
    private var indexes: [String: ProjectIntelligenceIndex] = [:]
    private var statuses: [String: ProjectIntelligenceStatus] = [:]
    private var errors: [String: String] = [:]
    private var watcher: DispatchSourceFileSystemObject?
    private var watcherFD: Int32 = -1
    private var debounceWorkItem: DispatchWorkItem?
    private var watchedPath: String?
    private var watcherCompletion: ((ProjectIntelligenceOverview) -> Void)?
    private var rollbackObserver: NSObjectProtocol?

    init(scanner: ProjectIntelligenceScanner = ProjectIntelligenceScanner(), store: ProjectIntelligenceStore = .shared) {
        self.scanner = scanner
        self.store = store
        rollbackObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("cn.ai-dev-one.checkpoint.did-rollback"),
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let path = notification.object as? String, !path.isEmpty else { return }
            self?.reindexAfterRollback(projectPath: path)
        }
    }

    deinit {
        if let rollbackObserver { NotificationCenter.default.removeObserver(rollbackObserver) }
        stopWatching()
    }

    func indexSynchronously(projectPath: String, force: Bool = false) throws -> ProjectIntelligenceIndex {
        let key = canonicalPath(projectPath)
        stateLock.lock(); statuses[key] = .scanning; errors[key] = nil; stateLock.unlock()
        do {
            let previous = force ? nil : cachedIndex(projectPath: key) ?? store.load(projectPath: key)
            stateLock.lock(); statuses[key] = .indexing; stateLock.unlock()
            let index = try scanner.scan(projectPath: key, previous: previous)
            try store.save(index)
            stateLock.lock(); indexes[key] = index; statuses[key] = .ready; errors[key] = nil; stateLock.unlock()
            return index
        } catch {
            stateLock.lock(); statuses[key] = .error; errors[key] = error.localizedDescription; stateLock.unlock()
            throw error
        }
    }

    func index(projectPath: String, force: Bool = false, completion: ((ProjectIntelligenceOverview) -> Void)? = nil) {
        let key = canonicalPath(projectPath)
        stateLock.lock(); statuses[key] = .scanning; errors[key] = nil; stateLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let previous = force ? nil : self.cachedIndex(projectPath: key) ?? self.store.load(projectPath: key)
                self.stateLock.lock(); self.statuses[key] = .indexing; self.stateLock.unlock()
                let index = try self.scanner.scan(projectPath: key, previous: previous)
                try self.store.save(index)
                self.stateLock.lock(); self.indexes[key] = index; self.statuses[key] = .ready; self.errors[key] = nil; self.stateLock.unlock()
                self.deliver(overview: ProjectIntelligenceOverview(status: .ready, index: index, error: nil), completion: completion)
            } catch {
                self.stateLock.lock(); self.statuses[key] = .error; self.errors[key] = error.localizedDescription; self.stateLock.unlock()
                self.deliver(overview: ProjectIntelligenceOverview(status: .error, index: nil, error: error.localizedDescription), completion: completion)
            }
        }
    }

    func cachedIndex(projectPath: String) -> ProjectIntelligenceIndex? {
        let key = canonicalPath(projectPath)
        stateLock.lock(); defer { stateLock.unlock() }
        // Context queries run on the AppKit path before a task starts. Only
        // return the in-memory index here; loading a large JSON snapshot from
        // an external volume must never freeze the composer. The background
        // indexing path is responsible for warming this cache first.
        return indexes[key]
    }

    func overview(projectPath: String) -> ProjectIntelligenceOverview {
        let key = canonicalPath(projectPath)
        stateLock.lock()
        let status = statuses[key] ?? (indexes[key] == nil ? .idle : .ready)
        let error = errors[key]
        let index = indexes[key]
        stateLock.unlock()
        return ProjectIntelligenceOverview(status: status, index: index ?? store.load(projectPath: key), error: error)
    }

    func recordTaskKnowledge(_ knowledge: TaskKnowledge, projectPath: String, completion: (() -> Void)? = nil) {
        let key = canonicalPath(projectPath)
        let safeKnowledge = projectIntelligenceSanitizeKnowledge(knowledge)
        queue.async { [weak self] in
            guard let self else { return }
            let base = self.cachedIndex(projectPath: key) ?? (try? self.indexSynchronously(projectPath: key))
            guard var index = base else { self.deliver(completion: completion); return }
            index.taskKnowledge = index.taskKnowledge.map(projectIntelligenceSanitizeKnowledge)
            index.taskKnowledge.removeAll { $0.taskId == safeKnowledge.taskId }
            index.taskKnowledge.append(safeKnowledge)
            if index.taskKnowledge.count > 100 { index.taskKnowledge.removeFirst(index.taskKnowledge.count - 100) }
            _ = try? self.store.save(index)
            self.stateLock.lock(); self.indexes[key] = index; self.stateLock.unlock()
            self.deliver(completion: completion)
        }
    }

    func reindexAfterRollback(projectPath: String, completion: ((ProjectIntelligenceOverview) -> Void)? = nil) {
        index(projectPath: projectPath, force: true, completion: completion)
    }

    func startWatching(projectPath: String, onUpdate: ((ProjectIntelligenceOverview) -> Void)? = nil) {
        stopWatching()
        let key = canonicalPath(projectPath)
        let fd = open(key, O_EVTONLY)
        guard fd >= 0 else { return }
        watcherFD = fd; watchedPath = key; watcherCompletion = onUpdate
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.stateLock.lock(); self.statuses[key] = .stale; self.stateLock.unlock()
            self.debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.index(projectPath: key, force: false, completion: self.watcherCompletion)
            }
            self.debounceWorkItem = work
            self.queue.asyncAfter(deadline: .now() + 0.75, execute: work)
        }
        source.setCancelHandler { close(fd) }
        watcher = source
        source.resume()
    }

    func stopWatching() {
        debounceWorkItem?.cancel(); debounceWorkItem = nil
        watcher?.cancel(); watcher = nil
        watcherFD = -1; watchedPath = nil; watcherCompletion = nil
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func deliver(overview: ProjectIntelligenceOverview, completion: ((ProjectIntelligenceOverview) -> Void)?) {
        guard let completion else { return }
        DispatchQueue.main.async { completion(overview) }
    }

    private func deliver(completion: (() -> Void)?) {
        guard let completion else { return }
        DispatchQueue.main.async(execute: completion)
    }
}

// MARK: - 有界上下文查询

final class ProjectContextProvider {
    static let shared = ProjectContextProvider()
    private let service: ProjectIntelligenceService

    init(service: ProjectIntelligenceService = .shared) {
        self.service = service
    }

    func getProjectOverview(projectPath: String) -> ProjectIntelligenceOverview {
        service.overview(projectPath: projectPath)
    }

    func findRelevantFiles(projectPath: String, query: String, limit: Int = 8) -> [FileNode] {
        guard let index = service.cachedIndex(projectPath: projectPath) else { return [] }
        let tokens = query.lowercased().split { $0 == " " || $0 == "\n" || $0 == "，" || $0 == "。" }.map(String.init)
        func score(_ file: FileNode) -> Int {
            let path = file.relativePath.lowercased()
            let symbolNames = file.symbols.map { $0.name.lowercased() }
            var score = 0
            for token in tokens {
                if path == token { score += 100 }
                if URL(fileURLWithPath: path).lastPathComponent.contains(token) { score += 40 }
                if path.contains(token) { score += 18 }
                if symbolNames.contains(token) { score += 60 }
                if symbolNames.contains(where: { $0.contains(token) }) { score += 24 }
                if file.module?.lowercased().contains(token) == true { score += 15 }
            }
            if file.role == "test" { score += 2 }
            if index.project.recentChangedFiles.contains(file.relativePath) { score += 6 }
            return score
        }
        var scored: [(file: FileNode, score: Int)] = []
        for file in index.files {
            let value = score(file)
            if tokens.isEmpty || value > 0 { scored.append((file: file, score: value)) }
        }
        scored.sort { left, right in
            if left.score == right.score { return left.file.relativePath < right.file.relativePath }
            return left.score > right.score
        }
        return scored.prefix(max(1, limit)).map { $0.file }
    }

    func findSymbol(projectPath: String, name: String, limit: Int = 12) -> [SymbolNode] {
        guard let index = service.cachedIndex(projectPath: projectPath) else { return [] }
        let needle = name.lowercased()
        var values = index.symbols.filter { symbol in
            let lower = symbol.name.lowercased()
            return lower == needle || lower.contains(needle)
        }
        values.sort { left, right in
            if left.name == right.name { return left.file < right.file }
            return left.name < right.name
        }
        return Array(values.prefix(limit))
    }

    func getFileRelations(projectPath: String, path: String) -> [DependencyEdge] {
        guard let index = service.cachedIndex(projectPath: projectPath) else { return [] }
        let normalized = path.hasPrefix("/") ? URL(fileURLWithPath: path).path.replacingOccurrences(of: index.project.rootPath + "/", with: "") : path
        return index.dependencies.filter { $0.from == normalized || $0.to == normalized }
    }

    func getRelatedTests(projectPath: String, path: String) -> [TestNode] {
        guard let index = service.cachedIndex(projectPath: projectPath) else { return [] }
        let normalized = path.hasPrefix("/") ? path.replacingOccurrences(of: index.project.rootPath + "/", with: "") : path
        let base = URL(fileURLWithPath: normalized).deletingPathExtension().lastPathComponent
        return index.tests.filter { test in
            test.targetFiles.contains(normalized) || test.path.localizedCaseInsensitiveContains(base)
        }
    }

    func getModule(projectPath: String, name: String) -> ModuleNode? {
        service.cachedIndex(projectPath: projectPath)?.modules.first { $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.path.caseInsensitiveCompare(name) == .orderedSame }
    }

    func getRecentTaskKnowledge(projectPath: String, query: String = "", limit: Int = 6) -> [TaskKnowledge] {
        guard let values = service.cachedIndex(projectPath: projectPath)?.taskKnowledge else { return [] }
        let needle = query.lowercased()
        var matched: [TaskKnowledge] = []
        for value in values.reversed() {
            if needle.isEmpty || value.summary.lowercased().contains(needle)
                || value.filesChanged.joined(separator: " ").lowercased().contains(needle) {
                matched.append(value)
            }
            if matched.count >= limit { break }
        }
        return matched
    }

    /// 返回小而有界的上下文。项目索引失败或仍在首次扫描时返回空字符串，
    /// 调用方继续走传统 search/read 工具，不会把索引故障升级成 Agent 故障。
    func promptContext(projectPath: String, query: String, maxCharacters: Int = 6_000) -> String {
        guard let index = service.cachedIndex(projectPath: projectPath), index.indexVersion == projectIntelligenceIndexVersion else { return "" }
        let files = findRelevantFiles(projectPath: projectPath, query: query, limit: 8)
        guard !files.isEmpty else { return "" }
        var lines: [String] = [
            "[Project Intelligence — bounded local context]",
            "Stack: \(index.project.frameworks.joined(separator: ", "))",
            "Languages: \(index.project.languages.joined(separator: ", "))",
            "Relevant files:",
        ]
        for file in files {
            let symbols = file.symbols.prefix(5).map { "\($0.name)(\($0.kind))" }.joined(separator: ", ")
            lines.append("- \(file.relativePath) [\(file.role)]\(symbols.isEmpty ? "" : " · \(symbols)")")
            let tests = getRelatedTests(projectPath: projectPath, path: file.relativePath).prefix(3).map(\.path)
            if !tests.isEmpty { lines.append("  tests: \(tests.joined(separator: ", "))") }
        }
        let text = lines.joined(separator: "\n")
        return text.count > maxCharacters ? String(text.prefix(maxCharacters)) + "\n[context truncated]" : text
    }
}
