// SMBCore: SMB 共有のマウント・取り外しの共通処理（アプリと smbctl の両方から使う）
import Foundation
import NetFS

struct Share: Codable, Equatable {
    var name: String   // メニューに出す名前
    var url: String    // smb://[ユーザー@]ホスト/共有名
}

struct ShareStatus {
    let name: String
    let url: String?          // 未登録のマウントは nil
    let mountPoint: String?   // マウント中ならマウント先
    var mountFrom: String? = nil   // マウント元（//user@host/share）
    var mounted: Bool { mountPoint != nil }
    var registered: Bool { url != nil }
}

struct SMBError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum SMBCore {
    // 登録した共有の一覧
    static let configURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/smbctl")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shares.json")
    }()

    static func loadShares() -> [Share] {
        guard let data = try? Data(contentsOf: configURL) else { return [] }
        return (try? JSONDecoder().decode([Share].self, from: data)) ?? []
    }

    static func saveShares(_ shares: [Share]) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        try enc.encode(shares).write(to: configURL, options: .atomic)
    }

    static func add(url raw: String, name: String? = nil) throws -> Share {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if !s.lowercased().hasPrefix("smb://") { s = "smb://" + s }
        s = escaped(s)
        guard let key = key(ofURL: s) else { throw SMBError("smb://ホスト/共有名 の形で指定してください: \(raw)") }
        var shares = loadShares()
        if shares.contains(where: { Self.key(ofURL: $0.url) == key }) { throw SMBError("登録済み: \(s)") }
        let share = Share(name: name ?? key.share, url: s)
        shares.append(share)
        try saveShares(shares)
        return share
    }

    static func remove(_ share: Share) throws {
        try saveShares(loadShares().filter { $0 != share })
    }

    // 登録済みの共有と、マウント中の SMB 共有（未登録も含む）をまとめて返す
    static func all() -> [ShareStatus] {
        var mounts = smbMounts()
        var result: [ShareStatus] = []
        for s in loadShares() {
            let k = key(ofURL: s.url)
            let i = mounts.firstIndex { $0.key == k }
            result.append(ShareStatus(name: s.name, url: s.url, mountPoint: i.map { mounts[$0].mountPoint }))
            if let i { mounts.remove(at: i) }
        }
        for m in mounts {
            result.append(ShareStatus(name: m.key.share, url: nil, mountPoint: m.mountPoint, mountFrom: m.from))
        }
        return result
    }

    // 名前・URL の一部で探す（大文字小文字は区別しない）
    static func find(_ query: String) -> ShareStatus? {
        let q = query.lowercased()
        let list = all()
        return list.first { $0.name.lowercased() == q }
            ?? list.first { $0.name.lowercased().contains(q) || ($0.url?.lowercased().contains(q) ?? false) }
    }

    // マウントする。パスワードはキーチェーンのものを使い、なければ macOS のログイン画面が出る
    @discardableResult
    static func mount(_ s: ShareStatus) throws -> String {
        if let mp = s.mountPoint { return mp }
        guard let str = s.url, let url = URL(string: str) else { throw SMBError("URL が不正: \(s.url ?? s.name)") }
        let openOptions = NSMutableDictionary()
        openOptions["UIOption"] = "AllowUI"   // kNAUIOptionKey = kNAUIOptionAllowUI
        var mountpoints: Unmanaged<CFArray>?
        let rc = NetFSMountURLSync(url as CFURL, nil, nil, nil, openOptions, nil, &mountpoints)
        let paths = mountpoints?.takeRetainedValue() as? [String] ?? []
        switch rc {
        case 0: return paths.first ?? ""
        case EEXIST: return paths.first ?? ""   // 既にマウント済み
        case ECANCELED, -128: throw SMBError("キャンセルしました: \(s.name)")
        case EAUTH, -5045: throw SMBError("認証に失敗しました: \(s.name)")
        case ENOENT: throw SMBError("共有が見つかりません: \(str)")
        case EHOSTUNREACH, ETIMEDOUT, -5999...(-5900):
            throw SMBError("サーバーに接続できません: \(str)（エラー \(rc)）")
        default: throw SMBError("マウントできません: \(str)（エラー \(rc)）")
        }
    }

    // 取り外す。使用中なら force しない限り失敗する
    static func unmount(_ s: ShareStatus, force: Bool = false) throws {
        guard let mp = s.mountPoint else { return }
        if Darwin.unmount(mp, force ? MNT_FORCE : 0) != 0 {
            let e = errno
            if e == EBUSY { throw SMBError("使用中のため取り外せません: \(s.name)\n開いているファイルやアプリを閉じてから試してください") }
            throw SMBError("取り外せません: \(s.name)（\(String(cString: strerror(e)))）")
        }
    }

    static func toggle(_ s: ShareStatus) throws {
        if s.mounted { try unmount(s) } else { try mount(s) }
    }

    // MARK: - マウント中の SMB 共有の取得と照合

    struct Key: Equatable {
        let host: String
        let share: String
    }

    // ホスト名は大文字小文字を無視し、Bonjour 名（xxx._smb._tcp.local）と xxx.local を同じとみなす
    static func normalizeHost(_ h: String) -> String {
        var s = h.lowercased()
        if s.hasSuffix(".") { s.removeLast() }
        for suffix in ["._smb._tcp.local", ".local"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
        }
        return s
    }

    // 共有名に空白などがあっても URL として読めるようにする（%xx 済みならそのまま）
    static func escaped(_ str: String) -> String {
        if URL(string: str) != nil { return str }
        let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: ":@"))
        return str.addingPercentEncoding(withAllowedCharacters: allowed) ?? str
    }

    static func key(ofURL str: String) -> Key? {
        guard let u = URLComponents(string: escaped(str)), let host = u.host, !host.isEmpty else { return nil }
        let share = u.path.split(separator: "/").first.map(String.init) ?? ""
        guard !share.isEmpty else { return nil }
        return Key(host: normalizeHost(host), share: share.lowercased())
    }

    // mntfromname は "//user@host/share" の形
    static func key(ofMountFrom from: String) -> Key? {
        key(ofURL: "smb:" + from)
    }

    static func smbMounts() -> [(key: Key, from: String, mountPoint: String)] {
        var mnt: UnsafeMutablePointer<statfs>?
        let n = getmntinfo(&mnt, MNT_NOWAIT)
        guard n > 0, let mnt else { return [] }
        return UnsafeBufferPointer(start: mnt, count: Int(n)).compactMap { entry -> (key: Key, from: String, mountPoint: String)? in
            var fs = entry
            let type = withUnsafeBytes(of: &fs.f_fstypename) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            guard type == "smbfs" else { return nil }
            let from = withUnsafeBytes(of: &fs.f_mntfromname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            let on = withUnsafeBytes(of: &fs.f_mntonname) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
            guard let k = key(ofMountFrom: from) else { return nil }
            return (k, from, on)
        }
    }
}
