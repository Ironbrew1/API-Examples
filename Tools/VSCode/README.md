# Ironbrew1 for Visual Studio Code

Obfuscate the Lua or Luau script you are editing, using the same Ironbrew1 API and options as
the Roblox Studio plugin. The result is saved separately and opened in a new editor tab.
Your original file is kept, and unsaved edits in the current editor are included.

## Install

Requires VS Code 1.96 or newer on Windows, macOS or Linux, plus an Ironbrew1 API subscription.

1. Open Extensions in VS Code (`Ctrl+Shift+X`).
2. Open the `…` menu and choose **Install from VSIX…**.
3. Select `ironbrew1-0.1.0.vsix`.

This package is for Visual Studio Code, not the Visual Studio IDE.

## Use

1. Open a `.lua` or `.luau` file.
2. Run **Ironbrew1: Set API Key** from the Command Palette (`Ctrl+Shift+P`).
3. Optionally run **Ironbrew1: Obfuscation Options**, or search for `ironbrew1` in Settings.
4. Click the shield in the editor title bar, right-click the editor and select
   **Ironbrew1: Obfuscate Current Script**, or run that command from the Command Palette.
5. Choose where to save the result. The suggested filename is `name.obfuscated.lua` or
   `name.obfuscated.luau`. Choose a separate file; replacing your source is blocked.

The extension uploads the whole current script to `https://ironbrew1.com` only when you invoke
Obfuscate. It polls the job and downloads the result. Progress can be cancelled; cancellation
stops local polling/downloads but does not cancel a job already queued on the server.
Jobs time out after four minutes. Workspace Trust is required.

The API key is kept in [VS Code's encrypted SecretStorage](https://code.visualstudio.com/api/extension-capabilities/common-capabilities#data-storage), not in your project or settings JSON.
Use **Ironbrew1: Forget API Key** to remove it. Remote extension hosts may keep their own key.
No telemetry is collected. The extension never executes the obfuscated script.

| Setting | Values | Default |
| --- | --- | --- |
| `ironbrew1.platform` | `roblox`, `luau`, `universal` | `roblox` |
| `ironbrew1.aggressiveOptimizations` | `0`, `1`, `2` | `0` |
| `ironbrew1.intenseVmScrambling` | `false`, `true` | `false` |
| `ironbrew1.enableVmCompression` | `false`, `true` | `false` |

## Build from source

With Node.js 22+ installed, run in this folder:

```sh
npm ci
npm test
npm run package
```

The extension has no runtime npm dependencies. `vsce` is only used to produce the installable
VSIX. Packaging does not publish to the Marketplace.
The packaging tool's MSAL dependency is pinned to patched version 7.1.1; it is excluded from
the VSIX along with all other development dependencies.

## Verification

Verified on 2026-10-25:

- 19 automated client and editor-workflow tests passed, including cancellation, authentication,
  retries, deadlines, separate output files, and rejection of foreign API job URLs.
- Loaded and activated in a real VS Code 1.143.1 extension host; all four commands and settings
  were recognized.
- Submitted a sample script to the live API and downloaded its obfuscated result using this
  extension's client.

The interactive dialogs and editor workflow are covered with VS Code API mocks; the host test
checks actual activation and command registration. Run `node test/run-host.js` to repeat the
host test (a desktop display, or Xvfb and Electron's Linux libraries, is required).
