#!/bin/sh
set -eu
umask 077

label=local.relock-after-unlock
domain="gui/$(/usr/bin/id -u)"
service="$domain/$label"
support_dir="$HOME/Library/Application Support/RelockAfterUnlock"
agents_dir="$HOME/Library/LaunchAgents"
app="$support_dir/RelockAfterUnlock.app"
program="$app/Contents/MacOS/RelockAfterUnlock"
plist="$agents_dir/$label.plist"

fail() {
    printf '%s\n' "$1" >&2
    exit 1
}

exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

is_loaded() {
    /bin/launchctl print "$service" >/dev/null 2>&1
}

require_gui_session() {
    [ "$(/usr/bin/id -u)" != 0 ] || fail "Run this command as your macOS user, without sudo."
    /bin/launchctl print "$domain" >/dev/null 2>&1 ||
        fail "Sign in to the macOS desktop and run this command as that user."
}

install_app() {
    if exists "$app" || exists "$plist" || is_loaded; then
        fail "Relock After Unlock is already installed. Run make uninstall, then make install to replace it."
    fi

    /usr/bin/make build
    built_app=build/RelockAfterUnlock.app
    /usr/bin/codesign --verify --strict "$built_app"
    "$built_app/Contents/MacOS/RelockAfterUnlock" --probe

    /bin/mkdir -p "$support_dir" "$agents_dir"
    stage="$(/usr/bin/mktemp -d "$support_dir/.install.XXXXXXXX")"
    placed_app=no
    placed_plist=no
    installed=no
    cleanup() {
        if [ "$installed" = no ]; then
            if [ "$placed_plist" = yes ]; then /bin/rm -f "$plist"; fi
            if [ "$placed_app" = yes ]; then /bin/rm -rf "$app"; fi
        fi
        /bin/rm -rf "$stage"
    }
    trap cleanup EXIT
    trap 'exit 1' HUP INT TERM
    /usr/bin/ditto "$built_app" "$stage/RelockAfterUnlock.app"
    /bin/cp Resources/LaunchAgent.plist "$stage/$label.plist"
    /usr/bin/plutil -replace ProgramArguments.0 -string "$program" "$stage/$label.plist"
    /usr/bin/plutil -lint "$stage/$label.plist"

    # macOS mv -n leaves its source in place when the destination already exists.
    /bin/mv -n "$stage/RelockAfterUnlock.app" "$support_dir/"
    [ ! -e "$stage/RelockAfterUnlock.app" ] || fail "Another installation already placed the app."
    placed_app=yes
    /bin/mv -n "$stage/$label.plist" "$agents_dir/"
    [ ! -e "$stage/$label.plist" ] || fail "Another installation already placed the LaunchAgent."
    placed_plist=yes
    /bin/launchctl enable "$service"
    /bin/launchctl bootstrap "$domain" "$plist"
    installed=yes
    printf '%s\n' "Installed. The timer starts at the next unlock."
}

uninstall_app() {
    if exists "$plist"; then
        [ ! -L "$plist" ] &&
            [ "$(/usr/bin/plutil -extract Label raw "$plist")" = "$label" ] &&
            [ "$(/usr/bin/plutil -extract ProgramArguments.0 raw "$plist")" = "$program" ] ||
            fail "The existing LaunchAgent does not belong to this installation. Its files were left in place."
    elif is_loaded; then
        fail "The LaunchAgent is loaded without its expected plist. Stop it before removing the app."
    fi

    if exists "$app"; then
        [ ! -L "$app" ] &&
            [ "$(/usr/bin/plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist")" = "$label" ] ||
            fail "The existing app does not match this installation. Its files were left in place."
    fi

    if is_loaded; then
        /bin/launchctl bootout "$service"
    fi
    /bin/rm -f "$plist"
    /bin/rm -rf "$app"
    /bin/rmdir "$support_dir" 2>/dev/null || true
    printf '%s\n' "Uninstalled. The saved interval can be reused if you reinstall."
}

require_gui_session
case "${1:-}" in
    install) install_app ;;
    uninstall) uninstall_app ;;
    *) fail "Usage: $0 install|uninstall" ;;
esac
