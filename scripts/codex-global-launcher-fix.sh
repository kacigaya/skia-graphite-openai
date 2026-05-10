#!/bin/sh
set -eu

defaultApp="/Applications/Codex.app"
app="$defaultApp"
command=""
marker="# codex-global-launcher-fix: SkiaGraphite disabled"
featureFlag="--disable-features=SkiaGraphite"

usage() {
  cat <<'EOF'
Usage:
  codex-global-launcher-fix.sh install [--app /path/to/Codex.app]
  codex-global-launcher-fix.sh status [--app /path/to/Codex.app]
  codex-global-launcher-fix.sh rollback [--app /path/to/Codex.app]

Commands:
  install   Replace the Codex launcher with a shim that disables SkiaGraphite.
  status    Report whether the launcher shim is installed.
  rollback  Restore the original launcher from Codex.real.

Options:
  --app PATH  Target Codex.app bundle. Defaults to /Applications/Codex.app.
  -h, --help  Show this help.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

parseArgs() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      install|status|rollback)
        [ -z "$command" ] || fail "multiple commands supplied"
        command="$1"
        shift
        ;;
      --app)
        [ "$#" -ge 2 ] || fail "--app requires a path"
        app="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
  done

  [ -n "$command" ] || {
    usage >&2
    exit 2
  }
}

plistExecName() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || printf 'Codex\n'
}

resolvePaths() {
  [ -d "$app" ] || fail "app bundle not found: $app"
  [ -f "$app/Contents/Info.plist" ] || fail "Info.plist not found in: $app"

  execName=$(plistExecName)
  [ -n "$execName" ] || execName="Codex"

  bin="$app/Contents/MacOS/$execName"
  real="$app/Contents/MacOS/$execName.real"
}

isOurShim() {
  [ -f "$bin" ] && grep -Fq "$marker" "$bin" 2>/dev/null
}

signApp() {
  sudo codesign --force --deep --sign - "$app"
}

printStatus() {
  if [ ! -d "$app" ]; then
    printf 'missing: %s\n' "$app"
    return 1
  fi

  resolvePaths

  if isOurShim && [ -f "$real" ]; then
    printf 'installed: launcher shim is active for %s\n' "$app"
  elif isOurShim && [ ! -f "$real" ]; then
    printf 'partial: shim exists but original launcher is missing: %s\n' "$real"
    return 1
  elif [ -f "$real" ]; then
    printf 'partial: backup exists but launcher is not this script shim: %s\n' "$real"
    return 1
  elif [ -f "$bin" ]; then
    printf 'unmodified: launcher shim is not installed for %s\n' "$app"
  else
    printf 'missing: launcher executable not found: %s\n' "$bin"
    return 1
  fi
}

installShim() {
  resolvePaths
  [ -f "$bin" ] || fail "launcher executable not found: $bin"

  if isOurShim; then
    [ -f "$real" ] || fail "shim is installed but backup is missing: $real"
    printf 'refreshing existing launcher shim: %s\n' "$bin"
  else
    if [ -f "$real" ]; then
      fail "backup already exists but launcher is not this script shim: $real"
    fi
    sudo cp -p "$bin" "$real"
    printf 'saved original launcher: %s\n' "$real"
  fi

  sudo tee "$bin" >/dev/null <<EOF
#!/bin/sh
$marker
exec "\$(dirname "\$0")/$execName.real" $featureFlag "\$@"
EOF
  sudo chmod 755 "$bin"
  signApp
  printf 'installed: reopen %s normally to use %s\n' "$app" "$featureFlag"
}

rollbackShim() {
  resolvePaths
  [ -f "$real" ] || fail "backup launcher not found: $real"

  if [ -f "$bin" ] && ! isOurShim; then
    fail "launcher is not this script shim; refusing to overwrite: $bin"
  fi

  sudo cp -p "$real" "$bin"
  sudo rm "$real"
  signApp
  printf 'rolled back: restored original launcher for %s\n' "$app"
}

parseArgs "$@"

case "$command" in
  install)
    installShim
    ;;
  status)
    printStatus
    ;;
  rollback)
    rollbackShim
    ;;
esac
