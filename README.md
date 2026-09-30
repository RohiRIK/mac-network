# mac-network

Native macOS menu bar network panel. Port of the Omarchy widget
[rohi.network](https://github.com/RohiRIK/rohi.network).

<img src="docs/previews/PanelView-0-PanelView.png" width="340" alt="Panel with demo data">
<img src="docs/previews/SettingsScreen-0-Manual.png" width="340" alt="IP settings in manual mode">

Screenshots are Xcode preview renders with documentation-range addresses.

## Features

- Connection header: Wi-Fi name and band, or Ethernet link speed. Wi-Fi on/off switch.
- Details: IP address, router, router and internet ping, packet loss, download/upload rate, Wi-Fi signal and rate.
- **Public IPv4**: looked up through api.ipify.org, only when you click it.
- Wi-Fi list: known networks first, then others, strongest first. Click to join, password inline. Right-click to forget.
- **IP settings**: switch a Wi-Fi or Ethernet service between DHCP and a fixed address, with *Use Current IP as Fixed*.

| Key | Action |
|---|---|
| `s` | Open IP settings |
| `r` | Refresh |
| `w` | Toggle Wi-Fi |
| `Esc` | Leave IP settings, or close the panel |

## Permissions

- **Location Services**: macOS shows Wi-Fi network names only to apps with Location access. The app never records location.
- **Administrator password**: saving IP settings and forgetting a network change system settings, so macOS asks once per change.

## Differences from the Omarchy widget

- Wi-Fi band switching is gone: macOS has no API to force a band. The current band is shown.
- One static IPv4 address per service (a `networksetup` limit), and a router is required for manual mode.
- Enterprise (802.1X) Wi-Fi sign-in is not built in yet.

## Install

1. Download `MacNetwork-0.1.0.zip` from [Releases](https://github.com/RohiRIK/mac-network/releases/latest) and unzip it.
2. Move `MacNetwork.app` to Applications and open it.
3. The app is not notarized by Apple, so macOS blocks the first launch. Open **System Settings ›
   Privacy & Security**, scroll down, and click **Open Anyway** next to MacNetwork. Or in Terminal:
   `xattr -dr com.apple.quarantine /Applications/MacNetwork.app`

macOS 15 or later, Apple silicon and Intel.

## Build and test

```bash
scripts/check.sh                               # tests + release bundle + plist lint
scripts/bundle.sh && open build/MacNetwork.app # run it
```

Before a PR, render previews (Xcode open on the package) and post the report:

```bash
../../tools/render-previews.sh . MacNetworkUI  # from the workspace: renders docs/previews/
scripts/pr-report.sh                           # runs the gate, comments on the PR
```

Requires macOS 15+ and Xcode 16+ (or Swift 6 Command Line Tools).

## License

MIT. See `LICENSE`; notices for code adapted from Omarchy and CodexBar are in `THIRD_PARTY_NOTICES.md`.
