<h1 align="center">Skia Graphite Compositing Bug - Chromium on macOS</h1>

<p align="center">
   <strong>A rendering glitch affecting all Chromium-based browsers and Electron apps on macOS 15 (Sequoia) / 26 (Tahoe), including the Codex desktop app and ChatGPT web client.</strong><br>
   <em>A GPU rendering synchronization bug causing visual corruption on macOS, and how to fix it.</em>
</p>

## Symptom

Windows fail to repaint correctly: portions of the desktop wallpaper, other apps, or stale buffer contents bleed through Chromium window surfaces. Visible as vertical bands, transparent strips, or ghosted UI fragments. Triggered by window resize, Mission Control, display sleep/wake, or external monitor switches.

## Root Cause

Chromium 130+ ships with **Skia Graphite** enabled by default: the new GPU rendering backend that replaces Ganesh. On macOS, Graphite uses **Metal** for surface allocation and presentation. A synchronization bug between Graphite's `MTLCommandBuffer` lifecycle and `CAMetalLayer` drawable presentation causes the compositor to display stale or uninitialized framebuffer regions instead of the freshly rasterized layer.

This is a system-level interaction between Chromium's renderer and macOS WindowServer, not a per-app misconfiguration. Disabling per-browser hardware acceleration does **not** fix it because Graphite still owns the GPU path when accel is on, and software rendering tanks performance.

## Fix

Disable the `SkiaGraphite` feature flag. Chromium falls back to the Ganesh backend, which renders correctly on Metal.

### Browsers (Chrome, Brave, Helium, Edge, Arc, Opera)

Navigate to the flags page and disable Skia Graphite:

```
chrome://flags/#skia-graphite     →  Disabled
helium://flags/#skia-graphite     →  Disabled
brave://flags/#skia-graphite      →  Disabled
edge://flags/#skia-graphite       →  Disabled
```

Relaunch. Verify at `chrome://gpu`: the **Graphite** line should read `Disabled`.

### Electron apps (Codex, ChatGPT desktop, Slack, VS Code, Discord, …)

Launch with the disable flag:

```bash
open -a Codex --args --disable-features=SkiaGraphite
```

For persistent launches, first try setting the Electron environment variable in your shell profile:

```bash
# ~/.zshrc
export ELECTRON_EXTRA_LAUNCH_ARGS="--disable-features=SkiaGraphite"
source ~/.zshrc
```

If that does not work, the app is probably not inheriting shell environment variables or does not honor `ELECTRON_EXTRA_LAUNCH_ARGS`.

Add a terminal alias instead:

```bash
# ~/.zshrc
alias codex-fixed='open -n -a Codex --args --disable-features=SkiaGraphite'
source ~/.zshrc
```

Then launch Codex with:

```bash
codex-fixed
```

For a Finder, Spotlight, or Dock launcher, create a wrapper app with Script Editor:

1. Open **Script Editor**.
2. Paste this script:

```applescript
do shell script "open -n -a Codex --args --disable-features=SkiaGraphite"
```

3. Export it with format **Application**.
4. Save it as `Codex Fixed.app` in `/Applications` or `~/Applications`.
5. Launch `Codex Fixed.app` instead of editing `Codex.app`.

### Codex app global launcher fix

Chrome policy files do not apply to Codex. Codex is an Electron app, so the reliable process-wide fix is a Chromium command-line switch. To make normal Dock, Finder, and Spotlight launches use the switch, use the helper script to replace the app launcher with a small shim and keep the original binary as `Codex.real`.

Check the current state:

```bash
scripts/codex-global-launcher-fix.sh status
```

Install or refresh the shim:

```bash
scripts/codex-global-launcher-fix.sh install
```

Quit Codex fully, then reopen `/Applications/Codex.app` normally. The script uses `sudo` for app bundle changes, reads the launcher name from `Contents/Info.plist`, and re-signs the modified bundle with an ad-hoc signature. A Codex update can overwrite the shim; rerun `scripts/codex-global-launcher-fix.sh install` after updating if the issue returns.

If Codex is installed somewhere else, pass the app bundle path:

```bash
scripts/codex-global-launcher-fix.sh status --app "$HOME/Applications/Codex.app"
scripts/codex-global-launcher-fix.sh install --app "$HOME/Applications/Codex.app"
```

Rollback by reinstalling Codex, or restore the original binary:

```bash
scripts/codex-global-launcher-fix.sh rollback
```

### System-wide (all Chromium binaries)

For managed Chrome-family browsers, set the Chromium policy file:

```bash
mkdir -p "/Library/Application Support/Google/Chrome/policies/managed"
cat > "/Library/Application Support/Google/Chrome/policies/managed/disable-graphite.json" <<EOF
{ "DisabledFeatures": ["SkiaGraphite"] }
EOF
```

Replicate the path for `BraveSoftware/Brave-Browser`, `Microsoft/Edge`, etc. This is a browser policy path, not a Codex or generic Electron policy.

## Verification

1. `chrome://gpu` → search for "Graphite" → must show `Disabled`.
2. Resize a window aggressively or trigger Mission Control. No bleed-through.
3. `chrome://flags/#skia-graphite` shows `Disabled` (default is `Default` which resolves to enabled on 130+).

## Status

Tracked upstream as a Skia/Chromium issue against the Metal backend. Expected to be resolved when Graphite's drawable presentation path is rewritten to use explicit fences. Until then, Ganesh is the stable path on macOS.

## Rollback

When the upstream fix lands (Chromium 14x), reset the flag to `Default` and remove the Electron env var to re-enable Graphite for the performance benefits (lower CPU, better HDR, faster canvas).

## Sources

- Chromium command-line flags: <https://www.chromium.org/developers/how-tos/run-chromium-with-flags>
- Electron command-line switches API: <https://www.electronjs.org/docs/latest/api/command-line-switches>
- Electron environment variables: <https://www.electronjs.org/docs/latest/api/environment-variables>
- Chrome enterprise policy list: <https://chromeenterprise.google/policies/>
