SMBToggle

A menu bar app to mount and unmount SMB shares (shared folders on a NAS or another Mac).
No more "Connect to Server" in Finder every time.

Requires macOS 13 or later (Apple silicon or Intel).
The app shows English or Japanese, following your Mac's language.


== Install ==

1. Move SMBToggle.app to the Applications folder.
2. Double-click SMBToggle.app.
3. If macOS says it can't open the app, click "Done".
   (This happens only the first time, because the app is not from the App Store.)
4. Open System Settings > Privacy & Security.
   Scroll down and click "Open Anyway", then enter your password.
5. Double-click SMBToggle.app again and click "Open".

A drive icon appears in the menu bar. You're ready.
To start SMBToggle when you log in, click the icon and choose "Open at Login".


== How to use ==

- Save a share (easiest way):
  Connect once with Finder > Go > Connect to Server,
  then click the icon and choose "Save Mounted Shares".
  Or choose "Add Share…" and enter smb://host/share.
- Click the icon to see your shares. Click a share to mount or unmount it.
  A check mark means it is mounted.
- "Mount All" and "Unmount All" work on all shares.
- A share that is in use is not unmounted. Close open files, then try again.
- To see the version, click the icon and choose "About SMBToggle".


== Passwords ==

The app does not save passwords. It uses the standard macOS way to connect.
If your Keychain has the password, the share mounts right away.
If not, macOS asks for it. Check "Remember this password in my keychain"
so it won't ask next time.


== Command line (optional) ==

smbctl in this folder does the same from Terminal.
In Terminal, go to this folder and run:

  xattr -d com.apple.quarantine smbctl
  sudo mkdir -p /usr/local/bin && sudo cp smbctl /usr/local/bin/

  smbctl list                   List shares
  smbctl on                     Mount all saved shares
  smbctl off                    Unmount all SMB shares
  smbctl toggle <name>          Mount or unmount
  smbctl add smb://host/share   Save a share


== Notes ==

- After you install a new version, repeat steps 3-5 of "Install".
- The app connects only to the servers you save. It sends no other data.


== Uninstall ==

1. Menu bar icon > Quit
2. Move SMBToggle.app from the Applications folder to the Trash.
3. To delete your saved shares too: in Finder, choose Go > Go to Folder,
   enter ~/Library/Application Support/smbctl and move that folder to the Trash.
4. If you installed smbctl, run: sudo rm /usr/local/bin/smbctl


License: MIT (see LICENSE). No warranty.
Questions or problems: https://github.com/guribow/smb-toggle/issues
