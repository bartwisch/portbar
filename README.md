# PortBar

Native macOS menu bar app for running local development servers.

## Start

Open `PortBar.xcodeproj` in Xcode and run the `ServerBar` scheme.

The app appears as PortBar only in the macOS menu bar. Click the server icon to see listening TCP processes. The default view shows likely development servers such as `node`, `bun`, `python`, `ruby`, `php`, `java`, `dotnet`, and similar processes. Switch to `Alle` to see every listener.

## Actions

- Open: opens `http://host:port` in the default browser.
- Copy URL or port from the row actions.
- Stop: sends `SIGTERM` to the process after confirmation.
- Refresh: re-runs `lsof`.
- Autostart: toggles PortBar as a macOS login item.

## Development

```sh
xcodegen generate
xcodebuild -scheme ServerBar -configuration Debug build
xcodebuild -scheme ServerBar -configuration Debug test
```
