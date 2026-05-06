# Skia Graphite Compositing Bug — Chromium on macOS

A rendering glitch affecting all Chromium-based browsers and Electron apps on macOS 15 (Sequoia) / 26 (Tahoe), including the Codex desktop app and ChatGPT web client.

## Symptom

Windows fail to repaint correctly: portions of the desktop wallpaper, other apps, or stale buffer contents bleed through Chromium window surfaces. Visible as vertical bands, transparent strips, or ghosted UI fragments. Triggered by window resize, Mission Control, display sleep/wake, or external monitor switches.

## Root Cause

Chromium 130+ ships with **Skia Graphite** enabled by default — the new GPU rendering backend that replaces Ganesh. On macOS, Graphite uses **Metal** for surface allocation and presentation. A synchronization bug between Graphite's `MTLCommandBuffer` lifecycle and `CAMetalLayer` drawable presentation causes the compositor to display stale or uninitialized framebuffer regions instead of the freshly rasterized layer.

This is a system-level interaction between Chromium's renderer and macOS WindowServer — not a per-app misconfiguration. Disabling per-browser hardware acceleration does **not** fix it because Graphite still owns the GPU path when accel is on, and software rendering tanks performance.

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

Relaunch. Verify at `chrome://gpu` — the **Graphite** line should read `Disabled`.

### Electron apps (Codex, ChatGPT desktop, Slack, VS Code, Discord, …)

Launch with the disable flag:

```bash
open -a Codex --args --disable-features=SkiaGraphite
```

Persistent across launches — set the Electron environment variable in your shell profile:

```bash
# ~/.zshrc
export ELECTRON_EXTRA_LAUNCH_ARGS="--disable-features=SkiaGraphite"
```

### System-wide (all Chromium binaries)

For apps that don't honor `ELECTRON_EXTRA_LAUNCH_ARGS`, set the Chromium policy file:

```bash
mkdir -p "/Library/Application Support/Google/Chrome/policies/managed"
cat > "/Library/Application Support/Google/Chrome/policies/managed/disable-graphite.json" <<EOF
{ "DisabledFeatures": ["SkiaGraphite"] }
EOF
```

Replicate the path for `BraveSoftware/Brave-Browser`, `Microsoft/Edge`, etc.

## Verification

1. `chrome://gpu` → search for "Graphite" → must show `Disabled`.
2. Resize a window aggressively or trigger Mission Control. No bleed-through.
3. `chrome://flags/#skia-graphite` shows `Disabled` (default is `Default` which resolves to enabled on 130+).

## Status

Tracked upstream as a Skia/Chromium issue against the Metal backend. Expected to be resolved when Graphite's drawable presentation path is rewritten to use explicit fences. Until then, Ganesh is the stable path on macOS.

## Rollback

When the upstream fix lands (Chromium 14x), reset the flag to `Default` and remove the Electron env var to re-enable Graphite for the performance benefits (lower CPU, better HDR, faster canvas).
