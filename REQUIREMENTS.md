# REQUIREMENTS — `cmd`

**Shell-Befehle aus natürlicher Sprache, generiert per Claude Code**

Stand: 2026-08-26 · Status: verbindliche Spezifikation für die Implementierung

---

## 0. Hinweise für die Implementierung (Claude Code)

- Dieses Dokument ist die Spezifikation. Bei Widersprüchen oder Unklarheiten: nachfragen, nicht raten.
- Claude-Code-CLI-Flags entwickeln sich weiter. Vor Verwendung gegen die installierte Version prüfen (`claude --help` bzw. Doku-Links in §15). Insbesondere die exakte Flag-Syntax zur **Tool-Deaktivierung** verifizieren.
- Nichts außerhalb des Projektverzeichnisses verändern. `install.sh` fragt vor jedem Schreiben in Nutzerdateien nach und überschreibt nichts ungefragt.

## 1. Ziel

`cmd <anfrage>` übersetzt eine natürlichsprachliche Anfrage in einen Shell-Befehl. Angezeigt werden 1–3 Optionen mit Erklärung und Risikoeinstufung; per Tastendruck wird ausgeführt, verfeinert, im Editor bearbeitet oder auf ein stärkeres Modell eskaliert. Die Ausführung erfolgt **in der aktuellen Shell des Nutzers** (`cd`, `export` usw. wirken), und der Befehl landet in der Shell-History.

## 2. Zielumgebungen & Abhängigkeiten

- **macOS** (zsh als Login-Shell; `/bin/bash` ist Bash 3.2) und **Ubuntu 22.04+/24.04** (bash 5).
- Abhängigkeiten: `claude` (Claude Code CLI, per Abo eingeloggt — kein API-Key nötig), `jq`, POSIX-Standardtools, `mktemp`; `tput` optional für Farben.
- `cmd-core` muss mit **Bash 3.2 und Bash 5** laufen (keine Bash-4-Features wie assoziative Arrays). `cmd.sh` muss unter **zsh und bash** sourcebar sein.
- TTY erforderlich; ohne TTY sauberer Abbruch mit Hinweis (Pipe-Nutzung ist out of scope, §17).

## 3. Architektur (verbindlich)

Zwei Teile — Grund: Ein reines Skript liefe in einer Subshell, `cd`/`export` würden verpuffen.

1. **`cmd.sh`** — definiert die Shell-Funktion `cmd()`, wird aus `.zshrc`/`.bashrc` gesourct.
   - Ruft `cmd-core "$@"` auf und übergibt per Umgebungsvariable den Pfad einer mktemp-Datei (`CMD_RESULT_FILE`).
   - Bestätigt der Nutzer eine Option, schreibt `cmd-core` den finalen Befehl in diese Datei und endet mit Exit-Code 0.
   - Die Funktion liest die Datei, fügt den Befehl in die Shell-History ein (bash: `history -s`, zsh: `print -s`) und führt ihn per `eval` **in der aktuellen Shell** aus. stderr bleibt am Terminal sichtbar, wird aber zusätzlich in eine Temp-Datei mitgeschnitten (z. B. via `tee` und Process Substitution).
   - Exit-Code ≠ 0 → Fehler-Loop (§9): Die Funktion ruft `cmd-core --fix <session-id> <exit-code> <stderr-datei>` auf; bestätigt der Nutzer dort eine korrigierte Option, wiederholt sich der Ablauf.
   - Temp-Dateien werden am Ende immer aufgeräumt.
2. **`cmd-core`** — Bash-Skript in `~/.local/bin`: Argument-/Config-Verarbeitung, Claude-Aufrufe, Anzeige, Menü-Loop, Risiko-Gate, Editor, Logging. Führt selbst **niemals** den generierten Befehl aus.

## 4. Claude-Aufrufe

- **Arbeitsverzeichnis** für alle `claude`-Aufrufe: `~/.cache/cmd/` (bei Bedarf anlegen). Grund: Die Session-Zuordnung von Claude Code ist verzeichnisgebunden, und der Startkontext soll nicht CLAUDE.md/Git-Status des zufälligen aktuellen Verzeichnisses laden. Das tatsächliche Nutzerverzeichnis wird stattdessen als Text im Prompt übergeben (§5).
- **Erstaufruf** (sinngemäß):

  ```bash
  claude -p \
    --model "$DEFAULT_MODEL" \
    --output-format json \
    --json-schema "$(cat "$SCHEMA_FILE")" \
    --append-system-prompt "$SYSTEM_ANHANG" \
    --max-turns 1 \
    --fallback-model "$FALLBACK_MODEL" \
    <Tool-Deaktivierung, siehe §13.1> \
    "$PROMPT"
  ```

- Aus der JSON-Antwort auswerten: `.structured_output` (der validierte Antwortvertrag, §6) und `.session_id` (für Folge-Aufrufe merken).
- **Freitext-Folgeprompt:** gleiche Flags plus `--resume "$SESSION_ID"`; Modell = das zuletzt verwendete.
- **`?`-Eskalation:** `--resume "$SESSION_ID" --model "$ESCALATION_MODEL" --effort "$ESCALATION_EFFORT"`. Prompt sinngemäß: „Erkläre die vorgeschlagenen Optionen deutlich ausführlicher (Flags, Wirkung, Risiken, Alternativen) und verbessere sie, falls möglich. Antworte im selben JSON-Schema."
- **`m`:** frische Session (**kein** resume) mit der ursprünglichen Kommandozeilen-Anfrage und dem gewählten Modell/Effort. Das gewählte Modell ist ab dann das „letzte Modell" für Freitext-Folgeprompts.
- **Modell-Aliase** (Stand Aug 2026): `haiku` = Haiku 4.5, `sonnet` = Sonnet 4.6, `opus` = Opus 4.8, `fable` = Fable 5. Hinweis: `fable` zählt im Abo etwa doppelt so stark aufs Kontingent wie `opus`.
- **Effort-Regeln:** `--effort` nur setzen, wenn das Modell es unterstützt: `haiku` → nie; `sonnet` → `low|medium|high|max`; `opus`, `fable` → `low|medium|high|xhigh|max`.
- **Timeout** je Aufruf: `CMD_TIMEOUT` (Default 120 s), für die Eskalation `ESCALATION_TIMEOUT` (Default 300 s). Während des Wartens: Text-Spinner mit Modellname und Laufzeit.

## 5. System-Prompt-Anhang und Kontextblock

Inhalt des `--append-system-prompt` (sinngemäß, bei der Implementierung ausformulieren):

- Rolle: Generator für Shell-Befehle. Keine Ausführung, keine Rückfragen, keine Prosa.
- Ausgabe: ausschließlich JSON gemäß Schema; 1–3 Optionen, **Option 1 = beste Empfehlung**.
- Einzeiler bevorzugen (Verkettung mit `&&` und Pipes erlaubt); interaktive/blockierende Befehle nur mit Hinweis im Feld `hinweis`.
- OS und Shell aus dem Kontextblock beachten — insbesondere GNU- vs. BSD-Tool-Unterschiede (klassisches Beispiel: `sed -i` auf macOS vs. Linux).
- `risiko` ehrlich gemäß Definition einstufen (§7).

**Kontextblock im User-Prompt** (automatisch vorangestellt): OS + Version (`uname -s`, `sw_vers` bzw. `lsb_release`), Shell + Version, aktuelles Arbeitsverzeichnis des Nutzers (`$PWD`), danach die eigentliche Anfrage.

## 6. Antwortvertrag (JSON-Schema)

```json
{
  "optionen": [
    {
      "befehl": "ausführbarer Einzeiler",
      "erklaerung": "was der Befehl tut, inkl. der wichtigen Flags",
      "risiko": "niedrig | mittel | hoch"
    }
  ],
  "hinweis": "optional: Warnungen, Voraussetzungen, Alternativen"
}
```

- 1–3 Einträge in `optionen`. Das echte JSON-Schema entsprechend streng formulieren: required-Felder, `enum` für `risiko`, `minItems: 1`, `maxItems: 3`. Es wird als Datei `schema.json` mitgeliefert (§15).
- Antworten auf `?`, `m`, Freitext und den Fehler-Loop folgen **demselben Schema**; die neue Antwort **ersetzt** jeweils die Anzeige.

## 7. Risikostufen

- **niedrig:** rein lesend/anzeigend, keine Zustandsänderung.
- **mittel:** verändert Dateien oder Systemzustand, ist aber gezielt und praktisch umkehrbar (Datei anlegen, Paket installieren, Dienst neu starten).
- **hoch:** destruktiv oder schwer umkehrbar. Mindestens: Löschen/Überschreiben (`rm` mit `-r`/`-f`, `dd`, `mkfs`, `shred`, `truncate`), rekursive Rechte-/Eigentümeränderungen (`chmod -R`, `chown -R`), Schreiben auf Devices (`> /dev/…`), `curl … | sh`/`| bash`-Muster, Firewall-Flush (`iptables -F`), `git push --force`, Shutdown/Reboot.
- **Lokale Denylist (Defense-in-Depth):** `cmd-core` prüft jeden auszuführenden Befehl (auch editierte, auch im Fehler-Loop) zusätzlich gegen eine fest einprogrammierte Musterliste (mindestens die obigen Beispiele). Ein Treffer hebt das Risiko auf **hoch** an; die Denylist senkt ein Risiko nie ab.

## 8. Anzeige & Menü

Pro Option anzeigen: Nummer, der Befehl (hervorgehoben; Farben via `tput` nur bei TTY und wenn `NO_COLOR` nicht gesetzt ist), darunter die Erklärung als Kommentarzeilen, Risiko sichtbar markiert (hoch = rot/⚠). Danach ggf. der `hinweis`. Anschließend die Menüzeile — **dynamisch** je nach Optionszahl:

- 1 Option: `[Y/n/v/m/?/h]`
- 2 Optionen: `[Y/2/n/v/v2/m/?/h]`
- 3 Optionen: `[Y/2/3/n/v/v2/v3/m/?/h]`

| Eingabe | Verhalten |
|---|---|
| Enter, `y`, `Y` | Option 1 ausführen (Risiko-Gate beachten) |
| `2`, `3` | Option 2 bzw. 3 ausführen (Risiko-Gate) |
| `n`, `N`, `q` | Abbruch ohne Ausführung |
| `?` | Eskalation gemäß §4; neue Anzeige, Menü erneut |
| `m` | Modell/Effort-Dialog (§8.2); frische Session mit Original-Anfrage; neue Anzeige, Menü erneut |
| `v`, `v1` | Option 1 im Editor bearbeiten (§8.1) — `v1` ist Synonym für `v` |
| `v2`, `v3` | Option 2 bzw. 3 im Editor bearbeiten |
| `h` | Hilfe anzeigen (alle Eingaben, Config-Pfad, Version); danach Menü erneut |
| alles andere | **Freitext:** als Folgeprompt mit Session-Kontext an das zuletzt verwendete Modell; neue Anzeige, Menü erneut |

**Risiko-Gate:** Bei `risiko = hoch` genügt Enter/`y` **nicht** — es muss wörtlich `yes` eingetippt werden (mit deutlichem, rotem Hinweis). Das Gate gilt für jede Ausführungsart: Direktwahl, nach dem Editor und im Fehler-Loop.

### 8.1 Editor (`v` / `v2` / `v3`)

- Den Befehl der gewählten Option in eine Temp-Datei schreiben und im Editor öffnen: `EDITOR_OVERRIDE` aus der Config, sonst `$EDITOR`, sonst `vi`.
- Nach dem Speichern: den bearbeiteten Befehl anzeigen und final bestätigen `[Y/n]`. War das ursprüngliche Risiko „hoch" oder trifft die Denylist auf den bearbeiteten Befehl zu → `yes`-Gate statt `[Y/n]`.
- Leere Datei nach dem Editieren = Abbruch zurück ins Menü.

### 8.2 Modell-Dialog (`m`)

- Auswahlliste `1) haiku  2) sonnet  3) opus  4) fable`, aktueller Default markiert.
- Danach Effort-Auswahl — **nur** wenn das gewählte Modell Effort unterstützt (Werte je Modell: §4), Default `high`.
- Anschließend Neuausführung gemäß §4 („m"): frische Session, Original-Anfrage, bisherige Session und Antwort werden verworfen.

## 9. Ausführung & Fehler-Loop

- Vor der Ausführung: Befehl in die Shell-History einfügen (§3).
- Nach der Ausführung: Exit-Code kurz anzeigen (bei 0 unaufdringlich).
- Bei Exit-Code ≠ 0: Angebot `Fehler an Claude zur Korrektur schicken? [Y/n]`. Bei Y: `--resume` der Session mit Exit-Code und stderr (gekürzt auf max. ca. 4 000 Zeichen bzw. die letzten 60 Zeilen) und der Bitte um korrigierte Optionen im selben Schema → Anzeige + Menü wie üblich.
- Auch im Fehler-Loop wird **nie** ohne ausdrückliche Bestätigung ausgeführt.

## 10. Argumente & Aufruf

- `cmd <freitext …>`: alle Argumente werden als **eine** Anfrage behandelt (`"$*"`) — Anführungszeichen sind optional. Enthält die Anfrage Shell-Metazeichen (`| > < * ? ( ) ! $`), sind Quotes nötig; das steht so in Hilfe und README.
- `cmd` ohne Argumente: interaktive Eingabezeile („Anfrage: ").
- `cmd -h` / `cmd --help`: Hilfe. `cmd --version`: Versionsausgabe.

## 11. Konfiguration

Datei `~/.config/cmd/config`, shell-sourcebares `KEY=VALUE`-Format; beim ersten Start automatisch mit kommentierten Defaults anlegen:

```bash
DEFAULT_MODEL=haiku        # Modell für den Erstaufruf (schnell, günstig)
ESCALATION_MODEL=opus      # Modell für '?' — Alternative: fable
ESCALATION_EFFORT=max      # Effort für '?'
FALLBACK_MODEL=sonnet      # --fallback-model bei Überlastung
CMD_TIMEOUT=120            # Sekunden je Claude-Aufruf
ESCALATION_TIMEOUT=300     # Sekunden für '?'-Aufrufe
EDITOR_OVERRIDE=           # leer = $EDITOR verwenden, Fallback vi
MAX_OPTIONS=3              # 1–3
```

Ungültige Werte → Warnung ausgeben und Default verwenden.

## 12. Logging

`~/.local/state/cmd/history.jsonl`, append-only, ein JSON-Objekt pro Zeile: Zeitstempel (ISO 8601), Modell, Anfrage, betroffener Befehl, Aktion (`ausgeführt` / `abgebrochen` / `editiert+ausgeführt` / `fehler+korrigiert`), Exit-Code. Das Tool löscht oder rotiert diese Datei niemals selbständig.

## 13. Sicherheit (hart, nicht verhandelbar)

1. **Tool-Deaktivierung:** Die `claude`-Aufrufe dürfen keine Tools nutzen — nichts lesen, nichts schreiben, nichts ausführen. Tool-Zugriff per Flag vollständig deaktivieren (exakte Syntax gegen die installierte Version verifizieren; Kandidaten: `--tools`, `--allowed-tools`, `--disallowedTools`) und zusätzlich `--max-turns 1` setzen. Das macht die Aufrufe zugleich schneller.
2. Ein generierter Befehl wird **ausschließlich** nach ausdrücklicher Bestätigung im Menü ausgeführt — nie automatisch, auch nicht im Fehler-Loop.
3. Risiko-Gate und Denylist gemäß §7/§8 gelten für jeden Ausführungspfad.
4. **Kein `eval` von Rohtext:** Ausgeführt wird nur, was aus dem schema-validierten `structured_output` stammt oder vom Nutzer im Editor explizit bestätigt wurde.
5. Schlägt Parsing/Schema-Validierung fehl: Rohantwort anzeigen, sauber abbrechen, nichts ausführen.

## 14. Fehlerbehandlung

- `claude` fehlt oder ist nicht eingeloggt, `jq` fehlt → verständliche Meldung mit konkreter Abhilfe (Install-/Login-Hinweis), Exit ≠ 0.
- Netzwerk-/API-Fehler oder Timeout → Meldung mit einmaligem Angebot „Nochmal versuchen? [Y/n]", kein Endlos-Retry.
- Strg-C jederzeit: sauber abbrechen, Temp-Dateien aufräumen, nichts ausführen.

## 15. Deliverables

1. `cmd.sh` — Shell-Funktion, unter zsh und bash sourcebar.
2. `cmd-core` — Kernskript (Bash 3.2-kompatibel).
3. `schema.json` — das JSON-Schema aus §6.
4. `install.sh` — kopiert `cmd-core` nach `~/.local/bin/`, `cmd.sh` und `schema.json` nach `~/.local/share/cmd/`, legt Config- und State-Verzeichnisse an, gibt die `source`-Zeile für `.zshrc`/`.bashrc` aus (automatischer Eintrag nur nach Rückfrage), überschreibt nichts ohne Rückfrage.
5. `README.md` — Installation, Beispiele, Menü-Referenz, Konfiguration, Quoting-Hinweis.
6. `tests/smoke.sh` — soweit ohne echten Claude-Aufruf sinnvoll: JSON-Parsing, Denylist, Menü-/Gate-Logik mit gemockten Antworten.

Referenz-Doku: Claude Code Headless/Print-Mode: <https://code.claude.com/docs/en/headless> · CLI-Referenz: <https://code.claude.com/docs/en/cli-reference>

## 16. Akzeptanzkriterien

1. `cmd zeige die 10 größten dateien in diesem verzeichnis` → 1–3 Optionen mit Erklärung und Risiko; Enter führt Option 1 aus; der Befehl steht danach in der Shell-History.
2. `cmd wechsle in mein home verzeichnis` → nach der Ausführung ist `$PWD` der Nutzer-Shell tatsächlich geändert (Beweis für die Funktions-Architektur).
3. `cmd lösche rekursiv alle dateien unter /tmp/cmdtest` → Enter genügt nicht; erst das wörtliche `yes` führt aus.
4. `?` → deutlich ausführlichere Erklärungen vom Eskalationsmodell; Menü erscheint erneut, Optionen bleiben ausführbar.
5. `m` → Modell-/Effort-Dialog; frische Session mit der Original-Anfrage; bei `haiku` keine Effort-Abfrage.
6. `v` → Editor öffnet sich; nach Bestätigung wird der **geänderte** Befehl ausgeführt, nicht der ursprüngliche.
7. Freitext (z. B. „nur die letzten 5") → die Antwort nutzt erkennbar den Session-Kontext.
8. Ein absichtlich fehlschlagender Befehl → Fix-Angebot; nach Y erscheinen korrigierte Optionen.
9. Ohne `jq` bzw. ohne `claude`-Login → verständliche Fehlermeldung, kein Absturz, keine Ausführung.
10. Identisches Verhalten unter zsh/macOS und bash/Ubuntu; `cmd-core` läuft auch unter Bash 3.2.

## 17. Out of Scope (v1)

Windows/WSL-Sonderlogik · mehrzeilige Skripte (nur Einzeiler, ggf. mit `&&` verkettet) · Shell-Completion · Sessions über einen `cmd`-Aufruf hinaus · nicht-interaktive/Pipe-Nutzung · besondere sudo-Behandlung (sudo-Befehle sind erlaubt, die Passwortabfrage übernimmt die Shell; Risiko mindestens „mittel").
