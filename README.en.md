# SMBToggle

[日本語](README.md)

A menu bar app to mount and unmount SMB shares (shared folders on a NAS or another Mac).
A command-line tool, `smbctl`, is included.
No more "Connect to Server" in Finder every time.

- Requires macOS 13 or later (Apple silicon or Intel).
- English and Japanese. The app and the command follow your Mac's language.

## Download and install

Download the zip from [Releases](https://github.com/guribow/smb-toggle/releases/latest).
`SMBToggle-<version>-en.zip` has an English guide, `-ja.zip` has a Japanese guide. The app is the same.

1. Open the zip and move SMBToggle.app to the Applications folder.
2. Double-click it. If macOS says it can't open the app, click "Done".
   (This happens only the first time, because the app is not from the App Store.)
3. Open System Settings > Privacy & Security, scroll down, click "Open Anyway" and enter your password.
4. Double-click the app again and click "Open".

A drive icon appears in the menu bar. After you install a new version, repeat steps 2-4.

## How to use

- **Save a share (easiest way):** Connect once with Finder > Go > Connect to Server,
  then click the icon and choose "Save Mounted Shares". Or choose "Add Share…" and enter `smb://host/share`.
- Click the icon to see your shares. Click a share to mount or unmount it. A check mark means it is mounted.
- "Mount All" and "Unmount All" work on all shares.
- A share that is in use is not unmounted. Close open files, then try again.
- Shares stay mounted when you quit the app.

## Passwords

The app does not save passwords. It uses the standard macOS way to connect (NetFS).
If your Keychain has the password, the share mounts right away.
If not, macOS asks for it. Check "Remember this password in my keychain" so it won't ask next time.

To use a specific user name, save the share as `smb://user@host/share`.

## Command line (optional)

`smbctl` in the zip does the same from Terminal. To install it:

```bash
xattr -d com.apple.quarantine smbctl
sudo mkdir -p /usr/local/bin && sudo cp smbctl /usr/local/bin/
```

```bash
smbctl list                          # list shares (saved and mounted)
smbctl on [name]                     # mount (all saved shares if no name)
smbctl off [-f] [name]               # unmount (all if no name; -f to force)
smbctl toggle <name>                 # mount or unmount
smbctl add smb://host/share [name]   # save a share
smbctl remove <name>                 # remove a saved share
```

## Troubleshooting

- **"Can't connect to the server":** Check the host name. If a name like `nas.local` does not work, save the share with its IP address.
- **A mounted share has no check mark:** The saved address and the mounted address are different (for example, IP address and name). Remove the share, then use "Save Mounted Shares".
- **"Open at Login" shows an error:** Add SMBToggle in System Settings > General > Login Items.

## Notes

- Privacy: the app connects only to the servers you save. It sends no other data.

## Uninstall

1. Menu bar icon > Quit
2. Move SMBToggle.app to the Trash.
3. To delete your saved shares too, move `~/Library/Application Support/smbctl` to the Trash.
4. If you installed smbctl: `sudo rm /usr/local/bin/smbctl`

## Build from source

Requires Xcode (swiftc).

```bash
./build.sh   # builds and installs the app and smbctl
./dist.sh    # makes the zips in dist/
```

## License

MIT ([LICENSE](LICENSE)). No warranty.
