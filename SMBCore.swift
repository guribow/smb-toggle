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

/// 画面に出す文字列。日本語をキーにし、Mac の言語が日本語でなければ英語にする。
/// アプリとコマンド（smbctl）の両方で使うので、翻訳ファイルではなくここに表で持つ
func L(_ ja: String) -> String {
    guard !(Locale.preferredLanguages.first ?? "ja").hasPrefix("ja") else { return ja }
    return english[ja] ?? ja
}

func L(_ ja: String, _ args: CVarArg...) -> String { String(format: L(ja), arguments: args) }

private let english: [String: String] = [
    "登録済み: %@": "Already saved: %@",
    "URL が不正: %@": "Invalid URL: %@",
    "キャンセルしました: %@": "Canceled: %@",
    "認証に失敗しました: %@": "Sign-in failed: %@",
    "共有が見つかりません: %@": "Share not found: %@",
    "サーバーに接続できません: %@（エラー %d）": "Can't connect to the server: %@ (error %d)",
    "マウントできません: %@（エラー %d）": "Can't mount: %@ (error %d)",
    "使用中のため取り外せません: %@\n開いているファイルやアプリを閉じてから試してください":
        "Can't unmount %@ because it is in use.\nClose open files and apps, then try again.",
    "取り外せません: %@（%@）": "Can't unmount: %@ (%@)",
    "SMBToggle について": "About SMBToggle",
    "登録した共有なし": "No saved shares",
    "%@（未登録）": "%@ (not saved)",
    " …接続中": " …connecting",
    "クリックで取り外す（%@）": "Click to unmount (%@)",
    "クリックでマウントする（%@）": "Click to mount (%@)",
    "すべてマウント": "Mount All",
    "すべて取り外す": "Unmount All",
    "共有を追加…": "Add Share…",
    "マウント中の共有を登録": "Save Mounted Shares",
    "登録から外す": "Remove Share",
    "ログイン時に起動": "Open at Login",
    "終了": "Quit",
    "SMB 共有を追加": "Add SMB Share",
    "例：smb://nas.local/share または smb://user@192.168.1.10/share\n表示名は空欄なら共有名になります。":
        "Example: smb://nas.local/share or smb://user@192.168.1.10/share\nIf the name is empty, the share name is used.",
    "smb://ホスト/共有名": "smb://host/share",
    "表示名（省略可）": "Name (optional)",
    "追加": "Add",
    "キャンセル": "Cancel",
    "マウント中\t%@": "mounted\t%@",
    "未マウント": "not mounted",
    "(未登録) smb:": "(not saved) smb:",
    "マウントしていない登録済みの共有がない": "No saved shares to mount",
    "マウントした: %@ → %@": "Mounted: %@ → %@",
    "登録した共有に見つからない: %@": "Not found in saved shares: %@",
    "マウント中の SMB 共有がない": "No SMB shares are mounted",
    "取り外した: %@": "Unmounted: %@",
    "マウント中の共有に見つからない: %@": "Not found in mounted shares: %@",
    "見つからない: %@": "Not found: %@",
    "マウントした: %@": "Mounted: %@",
    "登録した: %@\t%@": "Saved: %@\t%@",
    "登録から外した: %@": "Removed: %@",
    "使い方:\n  smbctl list                    共有の一覧（登録済み＋マウント中）\n  smbctl on [名前]               マウント（名前なしで登録済みをすべて）\n  smbctl off [-f] [名前]         取り外す（名前なしで SMB をすべて、-f で強制）\n  smbctl toggle <名前>           マウント ⇄ 取り外し\n  smbctl add <smb://ホスト/共有> [表示名]\n  smbctl remove <名前>           登録から外す":
        "Usage:\n  smbctl list                    List shares (saved and mounted)\n  smbctl on [name]               Mount (all saved shares if no name)\n  smbctl off [-f] [name]         Unmount (all SMB shares if no name; -f to force)\n  smbctl toggle <name>           Mount or unmount\n  smbctl add <smb://host/share> [name]\n  smbctl remove <name>           Remove a saved share",
]

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
        if shares.contains(where: { Self.key(ofURL: $0.url) == key }) { throw SMBError(L("登録済み: %@", s)) }
        // 表示名の既定は共有名（照合用の key は小文字なので、URL から元の表記を取る）
        let original = URLComponents(string: s)?.path.split(separator: "/").first.map(String.init)
        let share = Share(name: name ?? original ?? key.share, url: s)
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
        guard let str = s.url, let url = URL(string: str) else { throw SMBError(L("URL が不正: %@", s.url ?? s.name)) }
        let openOptions = NSMutableDictionary()
        openOptions["UIOption"] = "AllowUI"   // kNAUIOptionKey = kNAUIOptionAllowUI
        var mountpoints: Unmanaged<CFArray>?
        let rc = NetFSMountURLSync(url as CFURL, nil, nil, nil, openOptions, nil, &mountpoints)
        let paths = mountpoints?.takeRetainedValue() as? [String] ?? []
        switch rc {
        case 0: return paths.first ?? ""
        case EEXIST: return paths.first ?? ""   // 既にマウント済み
        case ECANCELED, -128: throw SMBError(L("キャンセルしました: %@", s.name))
        case EAUTH, -5045: throw SMBError(L("認証に失敗しました: %@", s.name))
        case ENOENT: throw SMBError(L("共有が見つかりません: %@", str))
        case EHOSTUNREACH, ETIMEDOUT, -5999...(-5900):
            throw SMBError(L("サーバーに接続できません: %@（エラー %d）", str, Int(rc)))
        default: throw SMBError(L("マウントできません: %@（エラー %d）", str, Int(rc)))
        }
    }

    // 取り外す。使用中なら force しない限り失敗する
    static func unmount(_ s: ShareStatus, force: Bool = false) throws {
        guard let mp = s.mountPoint else { return }
        if Darwin.unmount(mp, force ? MNT_FORCE : 0) != 0 {
            let e = errno
            if e == EBUSY { throw SMBError(L("使用中のため取り外せません: %@\n開いているファイルやアプリを閉じてから試してください", s.name)) }
            throw SMBError(L("取り外せません: %@（%@）", s.name, String(cString: strerror(e))))
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
