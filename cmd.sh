# cmd.sh — definiert die Shell-Funktion cmd() für zsh UND bash.
# Wird aus ~/.zshrc bzw. ~/.bashrc gesourct (siehe install.sh).
#
# Architektur (§3 der Spezifikation): cmd-core generiert und bestätigt den
# Befehl, führt ihn aber nie aus. Diese Funktion liest den bestätigten Befehl
# aus einer mktemp-Datei und führt ihn per eval in der AKTUELLEN Shell aus —
# dadurch wirken cd, export usw., und der Befehl landet in der Shell-History.

cmd() {
    local core result stderrf rc line ec sid final shellinfo dim rst

    if command -v cmd-core >/dev/null 2>&1; then
        core=cmd-core
    elif [ -x "$HOME/.local/bin/cmd-core" ]; then
        core="$HOME/.local/bin/cmd-core"
    else
        echo "cmd: cmd-core nicht gefunden — install.sh ausführen (erwartet in ~/.local/bin)." >&2
        return 127
    fi

    result=$(mktemp "${TMPDIR:-/tmp}/cmd.res.XXXXXX") || return 1
    stderrf=$(mktemp "${TMPDIR:-/tmp}/cmd.err.XXXXXX") || { rm -f "$result"; return 1; }

    # Temp-Dateien auch bei Abbruch (Strg-C) aufräumen: zsh-EXIT-Traps sind
    # funktionslokal, bash nutzt den RETURN-Trap.
    if [ -n "${ZSH_VERSION:-}" ]; then
        trap 'rm -f "$result" "$result.state" "$stderrf"' EXIT
    else
        trap 'rm -f "$result" "$result.state" "$stderrf"; trap - RETURN' RETURN
    fi

    if [ -n "${ZSH_VERSION:-}" ]; then
        shellinfo="zsh $ZSH_VERSION"
    elif [ -n "${BASH_VERSION:-}" ]; then
        shellinfo="bash $BASH_VERSION"
    else
        shellinfo="${SHELL:-unbekannt}"
    fi

    dim=""; rst=""
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && command -v tput >/dev/null 2>&1; then
        dim=$(tput dim 2>/dev/null); rst=$(tput sgr0 2>/dev/null)
    fi

    CMD_RESULT_FILE="$result" CMD_SHELL_INFO="$shellinfo" command "$core" "$@"
    rc=$?
    final=$rc

    while [ "$rc" -eq 0 ] && [ -s "$result" ]; do
        line=$(cat "$result")

        # In die Shell-History einfügen (§3/§9)
        if [ -n "${ZSH_VERSION:-}" ]; then
            print -s -- "$line"
        else
            history -s "$line"
        fi

        # Ausführung in der aktuellen Shell; stderr bleibt sichtbar und wird
        # zusätzlich für den Fehler-Loop mitgeschnitten.
        : > "$stderrf"
        eval "$line" 2> >(tee -a "$stderrf" >&2)
        ec=$?
        final=$ec

        # Log-Eintrag mit dem echten Exit-Code (append-only, via cmd-core)
        CMD_RESULT_FILE="$result" command "$core" --log-exec "$ec"

        if [ "$ec" -eq 0 ]; then
            printf '%s(exit 0)%s\n' "$dim" "$rst"
            break
        fi
        printf 'Exit-Code: %s\n' "$ec"
        # Strg-C im ausgeführten Befehl ist kein Fall für den Fehler-Loop.
        [ "$ec" -eq 130 ] && break

        sid=$(sed -n 's/^SESSION_ID=//p' "$result.state" 2>/dev/null | head -n 1)
        : > "$result"
        CMD_RESULT_FILE="$result" command "$core" --fix "${sid:-unbekannt}" "$ec" "$stderrf"
        rc=$?
    done

    rm -f "$result" "$result.state" "$stderrf"
    return "$final"
}
