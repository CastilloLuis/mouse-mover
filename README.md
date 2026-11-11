# Mouse Mover

A small macOS menu bar app. While you switch it on, it moves the mouse
cursor 1 px and back at a fixed interval, so the system idle timer resets.
While it is off, it does nothing.

- Menu bar only (no Dock icon).
- Icon: outline mouse = off, filled mouse = on, warning triangle = on but
  the Accessibility permission is missing.
- Interval: 30 s, 1 min (default), 2 min or 5 min.
- It posts real `mouseMoved` events to the HID event tap. It never clicks
  and never types.
- It skips a tick when you used the mouse or keyboard in the last 5 s, when
  a mouse button is down, or when the screen is locked.
- It remembers on/off and the interval across launches (`UserDefaults`,
  domain `local.MouseMover`).
- Optional "Launch at Login" item (`SMAppService`).

## Build and run

Needs Xcode (or the Command Line Tools) with Swift 6.

```bash
make build   # builds build/MouseMover.app, ad-hoc signed
make run     # builds, then opens the app
make stop    # quits the app
make clean   # removes build output
```

## Grant the Accessibility permission

macOS lets an app post mouse events only with the Accessibility permission.

1. Click the menu bar icon, then click **Enable**.
2. macOS shows a dialog. Click **Open System Settings**.
3. In **Privacy & Security > Accessibility**, turn on **Mouse Mover**.
4. The icon changes from the warning triangle to the filled mouse.

If you closed the dialog, use **Grant Accessibility Permission…** in the menu.

The build uses an ad-hoc signature. macOS ties the grant to that exact
binary. After you change the code and rebuild, the old grant no longer
applies: remove Mouse Mover from the Accessibility list with the minus
button, then grant it again. To keep the grant across rebuilds, sign with a
real identity:

```bash
make build SIGN_ID="Apple Development: Your Name (TEAMID)"
```

## Check that it works

Print the system idle time in seconds:

```bash
ioreg -c IOHIDSystem | awk '/HIDIdleTime/ {print $NF/1000000000; exit}'
```

While it is on and you do not touch anything, the value goes back near 0
after each move. While it is off, the value keeps growing.

The app logs each tick:

```bash
/usr/bin/log show --last 10m --predicate 'subsystem == "local.MouseMover"' --style compact
```
