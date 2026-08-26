# cmd — Shell-Befehle aus natürlicher Sprache

`cmd <anfrage>` übersetzt eine natürlichsprachliche Anfrage per Claude Code in
einen Shell-Befehl. Angezeigt werden 1–3 Optionen mit Erklärung und
Risikoeinstufung; per Tastendruck wird ausgeführt, verfeinert, im Editor
bearbeitet oder auf ein stärkeres Modell eskaliert. Die Ausführung erfolgt in
der **aktuellen Shell** (`cd`, `export` usw. wirken), und der Befehl landet in
der Shell-History.

```
$ cmd zeige die 10 größten dateien in diesem verzeichnis

── Vorschläge (haiku) ──

Option 1 · Risiko: niedrig
  du -ah . | sort -rh | head -n 10
  # Listet alle Dateien und Verzeichnisse mit Größe, sortiert absteigend,
  # und zeigt die obersten 10.

[Y/n/v/m/?/h] ›
```

## Voraussetzungen

- macOS (zsh) oder Ubuntu 22.04+/24.04 (bash 5); `cmd-core` läuft auch unter
  Bash 3.2.
- [Claude Code CLI](https://claude.com/claude-code) (`claude`), per Abo
  eingeloggt (`claude` starten, dann `/login`) — kein API-Key nötig.
- `jq`, POSIX-Standardtools, `mktemp`; `tput` optional für Farben.
- Ein interaktives Terminal (TTY). Pipe-Nutzung wird nicht unterstützt.

## Installation

```sh
./install.sh
```

Das kopiert `cmd-core` nach `~/.local/bin/`, `cmd.sh` und `schema.json` nach
`~/.local/share/cmd/`, legt Config-/State-Verzeichnisse an und bietet an
(nur nach Rückfrage), diese Zeile in `~/.zshrc` bzw. `~/.bashrc` einzutragen:

```sh
[ -f "$HOME/.local/share/cmd/cmd.sh" ] && . "$HOME/.local/share/cmd/cmd.sh"
```

Danach eine neue Shell öffnen. `cmd` ist eine **Shell-Funktion** (kein
Skript) — nur so können `cd`/`export` in der aufrufenden Shell wirken.

## Nutzung

```sh
cmd zeige die 10 größten dateien in diesem verzeichnis
cmd wechsle in mein home verzeichnis
cmd wieviel speicher ist noch frei
cmd                      # fragt interaktiv nach der Anfrage
cmd -h                   # Hilfe
cmd --version
```

**Quoting:** Alle Argumente werden als *eine* Anfrage behandelt —
Anführungszeichen sind optional. Enthält die Anfrage Shell-Metazeichen
(`| > < * ? ( ) ! $`), sind Quotes nötig:

```sh
cmd 'zähle die zeilen in allen *.md dateien'
```

## Menü-Referenz

| Eingabe | Verhalten |
|---|---|
| Enter, `y` | Option 1 ausführen |
| `2`, `3` | Option 2 bzw. 3 ausführen |
| `n`, `q` | Abbruch ohne Ausführung |
| `?` | Deutlich ausführlichere Erklärungen vom Eskalationsmodell (Default: opus, effort max) |
| `m` | Modell/Effort wechseln — frische Session mit der Original-Anfrage |
| `v`, `v2`, `v3` | Option im Editor bearbeiten (`v1` = `v`); danach finale Bestätigung |
| `h` | Hilfe (alle Eingaben, Config-Pfad, Version) |
| *Freitext* | Anfrage verfeinern — geht mit Session-Kontext an das zuletzt verwendete Modell (z. B. „nur die letzten 5") |

Nach der Ausführung wird der Exit-Code angezeigt. Bei Exit-Code ≠ 0 bietet
`cmd` an, den Fehler (Exit-Code + stderr) an Claude zu schicken und liefert
korrigierte Optionen — auch dort wird nie ohne Bestätigung ausgeführt.

## Sicherheit

- **Risiko-Gate:** Bei Risiko „hoch" genügt Enter nicht — es muss wörtlich
  `yes` eingetippt werden. Das gilt für jeden Ausführungspfad (Direktwahl,
  nach dem Editor, im Fehler-Loop).
- **Denylist:** Unabhängig von Claudes Einstufung prüft `cmd-core` jeden
  Befehl gegen eine fest einprogrammierte Musterliste (`rm -r/-f`, `dd`,
  `mkfs`, `shred`, `truncate`, `chmod/chown -R`, Schreiben auf `/dev/…`,
  `curl … | sh`, `iptables -F`, `git push --force`, Shutdown/Reboot …).
  Ein Treffer hebt das Risiko auf „hoch" an; abgesenkt wird nie.
- **Keine Tools:** Die `claude`-Aufrufe laufen mit `--tools ""` — Claude kann
  nichts lesen, schreiben oder ausführen, sondern nur Befehle vorschlagen.
  (`--max-turns` existiert in Claude Code 2.1.x nicht mehr und entfällt;
  verifiziert gegen 2.1.246.)
- Ausgeführt wird ausschließlich der schema-validierte `structured_output`
  bzw. was der Nutzer im Editor explizit bestätigt hat — nie automatisch.
- Die Aufrufe laufen mit Arbeitsverzeichnis `~/.cache/cmd/`, damit weder
  `CLAUDE.md` noch der Git-Status des aktuellen Verzeichnisses in den
  Kontext geladen werden. OS, Shell und `$PWD` gehen stattdessen als Text in
  den Prompt.

## Konfiguration

`~/.config/cmd/config` (wird beim ersten Start mit Defaults angelegt),
shell-sourcebares `KEY=VALUE`-Format:

| Schlüssel | Default | Bedeutung |
|---|---|---|
| `DEFAULT_MODEL` | `haiku` | Modell für den Erstaufruf (schnell, günstig) |
| `ESCALATION_MODEL` | `opus` | Modell für `?` — Alternative: `fable` |
| `ESCALATION_EFFORT` | `max` | Effort für `?` |
| `FALLBACK_MODEL` | `sonnet` | `--fallback-model` bei Überlastung |
| `CMD_TIMEOUT` | `120` | Sekunden je Claude-Aufruf |
| `ESCALATION_TIMEOUT` | `300` | Sekunden für `?`-Aufrufe |
| `EDITOR_OVERRIDE` | *(leer)* | leer = `$EDITOR` verwenden, Fallback `vi` |
| `MAX_OPTIONS` | `3` | 1–3 angezeigte Optionen |

Modelle: `haiku`, `sonnet`, `opus`, `fable` (Stand Aug 2026; `fable` zählt im
Abo etwa doppelt so stark aufs Kontingent wie `opus`). Effort nur, wo das
Modell es unterstützt: `haiku` nie; `sonnet` `low|medium|high|max`;
`opus`/`fable` zusätzlich `xhigh`. Ungültige Werte lösen eine Warnung aus,
dann gilt der Default.

## Logging

`~/.local/state/cmd/history.jsonl` — append-only, ein JSON-Objekt pro Zeile:
Zeitstempel (ISO 8601), Modell, Anfrage, Befehl, Aktion (`ausgeführt`,
`abgebrochen`, `editiert+ausgeführt`, `fehler+korrigiert`) und Exit-Code.
Die Datei wird nie automatisch gelöscht oder rotiert.

## Tests

```sh
bash tests/smoke.sh
```

Läuft ohne echten Claude-Aufruf (gemockte Antworten): JSON-Parsing, Denylist,
Menü-/Gate-Logik, Fehler-Loop und der Funktions-Roundtrip unter bash und zsh.

## Grenzen (v1)

Keine Windows/WSL-Sonderlogik, nur Einzeiler (ggf. mit `&&` verkettet), keine
Shell-Completion, keine Sessions über einen `cmd`-Aufruf hinaus, keine
Pipe-Nutzung. `sudo`-Befehle sind erlaubt (Passwortabfrage übernimmt die
Shell; Risiko mindestens „mittel").
