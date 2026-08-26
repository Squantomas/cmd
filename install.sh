#!/usr/bin/env bash
# install.sh — installiert »cmd«:
#   cmd-core            → ~/.local/bin/
#   cmd.sh, schema.json → ~/.local/share/cmd/
# Legt Config-/State-/Cache-Verzeichnisse an und bietet (nur nach Rückfrage)
# den source-Eintrag in ~/.zshrc bzw. ~/.bashrc an.
# Überschreibt nichts ohne Rückfrage.

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share/cmd"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cmd"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cmd"
CACHE_DIR="$HOME/.cache/cmd"

say()  { printf '%s\n' "$*"; }
fail() { printf 'Fehler: %s\n' "$*" >&2; exit 1; }

ask_yn() {
    # $1 = Frage, $2 = Default (y|n); Return 0 = ja
    local q="$1" def="${2:-n}" hint r
    if [ "$def" = y ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    printf '%s %s ' "$q" "$hint"
    IFS= read -r r || r=""
    case "$r" in
        "") [ "$def" = y ] ;;
        y|Y|j|J|yes) return 0 ;;
        *) return 1 ;;
    esac
}

install_file() {
    # $1 = Quelle, $2 = Ziel; fragt vor jedem Überschreiben nach
    local src="$1" dst="$2"
    [ -f "$src" ] || fail "Quelldatei fehlt: $src"
    if [ -e "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            say "  $dst ist bereits aktuell."
            return 0
        fi
        ask_yn "  $dst existiert und unterscheidet sich — überschreiben?" n || { say "  Übersprungen: $dst"; return 0; }
    fi
    cp "$src" "$dst" || fail "Konnte $dst nicht schreiben."
    say "  Installiert: $dst"
}

add_source_line() {
    # $1 = rc-Datei; trägt die source-Zeile ein, wenn gewünscht und noch nicht vorhanden
    local rc="$1"
    if [ -f "$rc" ] && grep -Fq 'share/cmd/cmd.sh' "$rc"; then
        say "  $rc enthält den Eintrag bereits."
        return 0
    fi
    if ask_yn "  Eintrag in $rc automatisch ergänzen?" n; then
        printf '\n# cmd — Shell-Befehle aus natürlicher Sprache\n%s\n' "$SOURCE_LINE" >> "$rc" \
            || fail "Konnte $rc nicht schreiben."
        say "  Ergänzt: $rc"
    fi
}

say "cmd wird installiert…"

# Abhängigkeiten prüfen (Warnung, kein Abbruch — Installation ist trotzdem sinnvoll)
command -v jq >/dev/null 2>&1 \
    || say "Warnung: jq fehlt — bitte installieren (sudo apt install jq / brew install jq)."
command -v claude >/dev/null 2>&1 \
    || say "Warnung: Claude Code CLI (»claude«) fehlt — siehe https://claude.com/claude-code (Login per Abo: »claude« starten, dann /login)."

mkdir -p "$BIN_DIR" "$SHARE_DIR" "$CONFIG_DIR" "$STATE_DIR" "$CACHE_DIR" \
    || fail "Konnte Zielverzeichnisse nicht anlegen."

install_file "$SRC_DIR/cmd-core"    "$BIN_DIR/cmd-core"
chmod +x "$BIN_DIR/cmd-core" 2>/dev/null
install_file "$SRC_DIR/cmd.sh"      "$SHARE_DIR/cmd.sh"
install_file "$SRC_DIR/schema.json" "$SHARE_DIR/schema.json"

case ":$PATH:" in
    *":$BIN_DIR:"*) : ;;
    *) say "Hinweis: $BIN_DIR ist nicht im PATH — cmd.sh findet cmd-core trotzdem (fester Fallback)." ;;
esac

SOURCE_LINE='[ -f "$HOME/.local/share/cmd/cmd.sh" ] && . "$HOME/.local/share/cmd/cmd.sh"'

say ""
say "Damit »cmd« in der Shell verfügbar ist, muss cmd.sh gesourct werden."
say "Diese Zeile gehört in ~/.zshrc bzw. ~/.bashrc:"
say ""
say "  $SOURCE_LINE"
say ""

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [ -f "$rc" ]; then
        add_source_line "$rc"
    fi
done

say ""
say "Fertig. Neue Shell öffnen (oder: . \"$SHARE_DIR/cmd.sh\") und ausprobieren:"
say "  cmd zeige die 10 größten dateien in diesem verzeichnis"
