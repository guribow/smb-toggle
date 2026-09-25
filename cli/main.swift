// smbctl: SMBCore のコマンドライン版
//   smbctl list | on [名前] | off [-f] [名前] | toggle <名前> | add <URL> [表示名] | remove <名前>
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func run(_ body: () throws -> Void) {
    do { try body() } catch { fail(error.localizedDescription) }
}

var args = Array(CommandLine.arguments.dropFirst())
let force = args.contains("-f")
args.removeAll { $0 == "-f" }

switch (args.first, args.dropFirst().first) {
case ("list", _):
    for s in SMBCore.all() {
        let state = s.mounted ? "マウント中\t\(s.mountPoint!)" : "未マウント"
        print("\(s.name)\t\(s.url ?? "(未登録) smb:" + (s.mountFrom ?? ""))\t\(state)")
    }
case ("on", nil):
    let targets = SMBCore.all().filter { $0.registered && !$0.mounted }
    if targets.isEmpty { fail("マウントしていない登録済みの共有がない") }
    var failed = false
    for s in targets {
        do { print("マウントした: \(s.name) → \(try SMBCore.mount(s))") }
        catch { failed = true; FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8)!) }
    }
    if failed { exit(1) }
case ("on", let q?):
    guard let s = SMBCore.find(q), s.registered else { fail("登録した共有に見つからない: \(q)") }
    run { print("マウントした: \(s.name) → \(try SMBCore.mount(s))") }
case ("off", nil):
    let targets = SMBCore.all().filter(\.mounted)
    if targets.isEmpty { fail("マウント中の SMB 共有がない") }
    var failed = false
    for s in targets {
        do { try SMBCore.unmount(s, force: force); print("取り外した: \(s.name)") }
        catch { failed = true; FileHandle.standardError.write((error.localizedDescription + "\n").data(using: .utf8)!) }
    }
    if failed { exit(1) }
case ("off", let q?):
    guard let s = SMBCore.find(q), s.mounted else { fail("マウント中の共有に見つからない: \(q)") }
    run { try SMBCore.unmount(s, force: force); print("取り外した: \(s.name)") }
case ("toggle", let q?):
    guard let s = SMBCore.find(q) else { fail("見つからない: \(q)") }
    run { try SMBCore.toggle(s); print("\(s.mounted ? "取り外した" : "マウントした"): \(s.name)") }
case ("add", let url?):
    let name = args.count > 2 ? args[2...].joined(separator: " ") : nil
    run { let s = try SMBCore.add(url: url, name: name); print("登録した: \(s.name)\t\(s.url)") }
case ("remove", let q?):
    guard let st = SMBCore.find(q), let url = st.url,
          let s = SMBCore.loadShares().first(where: { $0.url == url }) else { fail("登録した共有に見つからない: \(q)") }
    run { try SMBCore.remove(s); print("登録から外した: \(s.name)") }
default:
    print("""
    使い方:
      smbctl list                    共有の一覧（登録済み＋マウント中）
      smbctl on [名前]               マウント（名前なしで登録済みをすべて）
      smbctl off [-f] [名前]         取り外す（名前なしで SMB をすべて、-f で強制）
      smbctl toggle <名前>           マウント ⇄ 取り外し
      smbctl add <smb://ホスト/共有> [表示名]
      smbctl remove <名前>           登録から外す
    """)
    exit(2)
}
