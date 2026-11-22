import Foundation
import AppKit

// MARK: - Umumiy fayl modeli

struct FileEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    var size: Int64
    var modified: Date?
    var selected: Bool
    var note: String? = nil
    /// Aqlli tozalash izohi: nega tanlanmagan (ilova ochiq, yaqinda ishlatilgan, siz qoldirgansiz…)
    var hint: String? = nil
    var name: String { url.lastPathComponent }
}

// MARK: - Fayl tizimi yordamchilari

enum FS {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser }

    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    static func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    static func isDir(_ url: URL) -> Bool {
        var d: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
    }

    static func children(_ url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
    }

    static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        return Int64(v?.totalFileAllocatedSize ?? v?.fileSize ?? 0)
    }

    /// Diskda haqiqatda egallagan joy (papka bo'lsa — rekursiv). BSD fts — FileManager'dan bir necha barobar tez.
    static func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        let root = url.path
        walk(root) { path, _, st, isDir in
            // Firmlink/mount nuqtalari orqali Data tomini ikki marta sanamaslik uchun
            if isDir { return path == root || (path != "/System/Volumes" && path != "/Volumes" && path != "/dev") }
            total += Int64(st.st_blocks) * 512
            return true
        }
        return total
    }

    /// Tez rekursiv aylanish (fts). visit(path, name, stat, isDir) -> false qaytarsa, papka ichiga kirilmaydi.
    static func walk(_ root: String,
                     _ visit: (_ path: String, _ name: String, _ st: stat, _ isDir: Bool) -> Bool) {
        root.withCString { cRoot in
            var paths: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: cRoot), nil]
            guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else { return }
            defer { fts_close(fts) }
            while let ent = fts_read(fts) {
                let info = Int32(ent.pointee.fts_info)
                switch info {
                case FTS_D:
                    guard let st = ent.pointee.fts_statp?.pointee else { continue }
                    let path = String(cString: ent.pointee.fts_path)
                    if !visit(path, lastComponent(path), st, true) { _ = fts_set(fts, ent, FTS_SKIP) }
                case FTS_F, FTS_SL, FTS_DEFAULT:
                    guard let st = ent.pointee.fts_statp?.pointee else { continue }
                    let path = String(cString: ent.pointee.fts_path)
                    _ = visit(path, lastComponent(path), st, false)
                default:
                    continue
                }
            }
        }
    }

    static func lastComponent(_ path: String) -> String {
        if let i = path.lastIndex(of: "/") { return String(path[path.index(after: i)...]) }
        return path
    }

    static func date(_ ts: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1e9)
    }

    /// Bitta element (paket) sifatida ko'riladigan papka kengaytmalari.
    static let packageExtensions: Set<String> = [
        "app", "logicx", "band", "photoslibrary", "fcpbundle", "bundle", "framework", "xcodeproj",
        "xcworkspace", "pkg", "musiclibrary", "tvlibrary", "imovielibrary", "rtfd", "pages",
        "numbers", "key", "sparsebundle", "vst3", "component", "vst", "aaxplugin", "plugin",
        "xcarchive", "dSYM", "playground", "abletonproject"
    ]

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum Format {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }
    static func mem(_ b: UInt64) -> String { bytes(Int64(clamping: b)) }

    static func relative(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: Lang.current.localeID)
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Shell va admin

enum Shell {
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    @discardableResult
    static func zsh(_ command: String) -> (status: Int32, out: String) {
        run("/bin/zsh", ["-c", command])
    }
}

enum Admin {
    /// macOS parol oynasi bilan root huquqida buyruq bajaradi.
    @MainActor
    static func run(_ command: String) -> (ok: Bool, out: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return (false, "AppleScript error") }
        let res = script.executeAndReturnError(&err)
        if let err {
            return (false, (err[NSAppleScript.errorMessage] as? String) ?? T("Bekor qilindi", "Cancelled", "Отменено"))
        }
        return (true, res.stringValue ?? "")
    }
}

// MARK: - Xavfsizlik

enum Safety {
    private static let protectedPrefixes = [
        "/System", "/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/lib", "/usr/libexec",
        "/private/var/db", "/Library/Apple", "/System/Applications"
    ]

    static func whitelist() -> [String] {
        UserDefaults.standard.stringArray(forKey: "whitelist") ?? []
    }

    static func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        let h = FS.home.path
        let exact: Set<String> = [
            "/", "/Applications", "/Library", "/Users", "/private", "/var", "/etc",
            h, h + "/Library", h + "/Documents", h + "/Desktop", h + "/Downloads",
            h + "/Music", h + "/Movies", h + "/Pictures", h + "/Applications",
            h + "/Library/Caches", h + "/Library/Logs", h + "/Library/Application Support",
            h + "/Library/Preferences", h + "/Library/Containers", h + "/Library/Group Containers",
            h + "/Library/Mobile Documents", h + "/Library/Keychains", h + "/.Trash"
        ]
        if exact.contains(p) { return true }
        if protectedPrefixes.contains(where: { p == $0 || p.hasPrefix($0 + "/") }) { return true }
        if p.hasPrefix(h + "/Library/Keychains") { return true }
        // Oq ro'yxatdagi papka yoki uni o'z ichiga olgan ota-papka ham himoyalanadi
        if whitelist().contains(where: { p == $0 || p.hasPrefix($0 + "/") || $0.hasPrefix(p + "/") }) { return true }
        let real = url.resolvingSymlinksInPath().path
        if real != p, protectedPrefixes.contains(where: { real == $0 || real.hasPrefix($0 + "/") }) { return true }
        if p == Bundle.main.bundlePath || p.hasPrefix(Bundle.main.bundlePath + "/") { return true }
        return false
    }
}

// MARK: - O'chirish + tarix

enum Remover {
    struct Result: Sendable {
        var freed: Int64 = 0
        var removed = 0
        var failed: [URL] = []
    }

    static func remove(_ entries: [FileEntry], permanently: Bool, appendUndo: Bool = false) -> Result {
        var r = Result()
        var trashed: [(String, String)] = []
        defer { if !trashed.isEmpty { UndoStore.save(trashed, append: appendUndo) } }
        for e in entries {
            if Safety.isProtected(e.url) { r.failed.append(e.url); continue }
            do {
                if permanently {
                    try FS.fm.removeItem(at: e.url)
                } else {
                    var out: NSURL?
                    try FS.fm.trashItem(at: e.url, resultingItemURL: &out)
                    if let t = out?.path { trashed.append((e.url.path, t)) }
                }
                r.freed += e.size
                r.removed += 1
                History.add("\(permanently ? "O'CHIRILDI" : "SAVATGA")\t\(Format.bytes(e.size))\t\(e.url.path)")
            } catch {
                r.failed.append(e.url)
            }
        }
        History.addFreed(r.freed)
        return r
    }
}

/// Oxirgi "Savatga" amalini qaytarish uchun: asl yo'l → Savatdagi yo'l.
enum UndoStore {
    private static let key = "undoLastBatch"
    private static let lock = NSLock()

    static func save(_ pairs: [(String, String)], append: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        var all = append ? ((UserDefaults.standard.array(forKey: key) as? [[String]]) ?? []) : []
        all += pairs.map { [$0.0, $0.1] }
        UserDefaults.standard.set(all, forKey: key)
    }

    static var count: Int {
        (UserDefaults.standard.array(forKey: key) as? [[String]])?.count ?? 0
    }

    /// Savatdan joyiga qaytaradi. Qaytarilganlar sonini beradi.
    @discardableResult
    static func restore() -> Int {
        lock.lock(); defer { lock.unlock() }
        guard let pairs = UserDefaults.standard.array(forKey: key) as? [[String]] else { return 0 }
        var n = 0
        for p in pairs where p.count == 2 {
            let original = URL(fileURLWithPath: p[0]), inTrash = URL(fileURLWithPath: p[1])
            guard FS.fm.fileExists(atPath: inTrash.path), !FS.fm.fileExists(atPath: original.path) else { continue }
            try? FS.fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? FS.fm.moveItem(at: inTrash, to: original)) != nil {
                n += 1
                History.add("QAYTARILDI\t\(original.path)")
            }
        }
        UserDefaults.standard.removeObject(forKey: key)
        return n
    }
}

enum History {
    private static let lock = NSLock()
    static var dir: URL { FS.home.appendingPathComponent("Library/Application Support/MaxClean", isDirectory: true) }
    static var file: URL { dir.appendingPathComponent("history.log") }

    static func add(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        try? FS.fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        guard let data = "\(stamp)\t\(line)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: file) {
            _ = try? h.seekToEnd()
            h.write(data)
            try? h.close()
        } else {
            try? data.write(to: file)
        }
    }

    static func read() -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    static func clear() { try? FS.fm.removeItem(at: file) }

    static var totalFreed: Int64 {
        Int64(UserDefaults.standard.double(forKey: "totalFreed"))
    }

    static func addFreed(_ b: Int64) {
        guard b > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        let d = UserDefaults.standard
        d.set(d.double(forKey: "totalFreed") + Double(b), forKey: "totalFreed")
    }
}

// MARK: - Ruxsatlar

enum Permissions {
    static var hasFullDiskAccess: Bool {
        let probes = ["Library/Safari", "Library/Mail", "Library/Messages"].map { FS.home.appendingPathComponent($0) }
        for p in probes where FS.exists(p) {
            return (try? FS.fm.contentsOfDirectory(atPath: p.path)) != nil
        }
        return FS.fm.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    static func openFullDiskAccess() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(u)
        }
    }

    static func openLoginItems() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }
}
