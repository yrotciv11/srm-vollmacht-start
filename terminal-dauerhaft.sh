#!/usr/bin/env bash
#
# Dauerhaftes Terminal für Cursor (und VS Code) über Remote SSH.
#
# Das Problem: Ein Terminal in Cursor lebt nur so lange wie die Verbindung.
# Bricht die Verbindung ab – Netzwechsel, Laptop zugeklappt, anderer Rechner –
# werden alle laufenden Prozesse abgeschossen. Ein halb gelaufener Build ist
# weg, eine laufende Datenbank auch.
#
# Die Lösung: Jeder Terminal-Tab hängt an einer tmux-Sitzung. Die Sitzung
# lebt auf der Maschine weiter, unabhängig von der Verbindung.
#
# Die wichtige Verbesserung gegenüber der üblichen Anleitung: Die Sitzungen
# bekommen STABILE Namen (vsc-1, vsc-2, …). Bei der nächsten Verbindung
# findet der erste Tab automatisch wieder die Sitzung vsc-1 – also genau die
# Prozesse von vorhin. Übliche Anleitungen benennen Sitzungen nach der
# Prozessnummer; dann findet man nach dem Verbinden nichts wieder.
#
# Aufruf: wird von Cursor als Terminal-Profil gestartet. Nicht von Hand.

set -u

VERZEICHNIS="${PWD}"
PRAEFIX="vsc"
SPERRE="${TMPDIR:-/tmp}/tmux-wahl-$(id -u).lock"

# ------------------------------------------------------- Sitzung auswählen
# Zuerst eine noch nicht benutzte Sitzung nehmen (das sind die von der
# letzten Verbindung). Gibt es keine, eine neue anlegen.
#
# Die Sperre verhindert, dass zwei gleichzeitig geöffnete Tabs dieselbe
# Sitzung erwischen – sonst säßen beide im selben Terminal.
name=""
for _versuch in 1 2 3 4 5 6 7 8 9 10; do
  if mkdir "$SPERRE" 2>/dev/null; then
    frei="$(tmux list-sessions -F '#{session_name} #{session_attached}' 2>/dev/null \
            | awk -v p="${PRAEFIX}-" '$1 ~ "^" p && $2 == 0 { print $1 }' \
            | sort -t- -k2 -n | head -1)"
    if [ -n "$frei" ]; then
      name="$frei"
    else
      hoechste="$(tmux list-sessions -F '#{session_name}' 2>/dev/null \
                  | grep -oE "^${PRAEFIX}-[0-9]+$" | grep -oE '[0-9]+$' \
                  | sort -n | tail -1)"
      name="${PRAEFIX}-$(( ${hoechste:-0} + 1 ))"
    fi
    rmdir "$SPERRE" 2>/dev/null
    break
  fi
  sleep 0.1
done
[ -z "$name" ] && name="${PRAEFIX}-$$"

# --------------------------------------------------------- Sitzung anlegen
# Die Variablen, die Cursor dem Terminal mitgibt, werden in die Sitzung
# weitergereicht. Dadurch funktioniert der Befehl "code" auch innerhalb von
# tmux. (Bei einer wiederaufgenommenen Sitzung zeigen sie auf die alte
# Verbindung – dann startet man für "code" kurz einen neuen Tab.)
eargs=()
for v in TERM_PROGRAM TERM_PROGRAM_VERSION VSCODE_IPC_HOOK_CLI VSCODE_IPC_HOOK \
         VSCODE_PID VSCODE_CWD VSCODE_NLS_CONFIG VSCODE_GIT_IPC_HANDLE \
         VSCODE_INJECTION VSCODE_SHELL_INTEGRATION; do
  wert="${!v:-}"
  [ -n "$wert" ] && eargs+=( -e "${v}=${wert}" )
done

if ! tmux has-session -t "$name" 2>/dev/null; then
  # Neue Sitzung. "${eargs[@]}" nur übergeben, wenn gefüllt – sonst meckert
  # tmux unter älteren Fassungen über ein leeres Argument.
  if [ "${#eargs[@]}" -gt 0 ]; then
    tmux new-session -d -s "$name" -c "$VERZEICHNIS" "${eargs[@]}"
  else
    tmux new-session -d -s "$name" -c "$VERZEICHNIS"
  fi
  # Keine tmux-Statusleiste – Cursor hat seine eigene.
  tmux set -t "$name" status off 2>/dev/null || true
fi

# ------------------------------------------- Cursor die Einbindung melden
# Diese Zeichenfolgen sagen Cursor: "Wir sind im Terminal, hier ist der
# Befehl, wir sind bereit." Ohne sie verliert Cursor die Verknüpfung zum
# Terminal und zeigt z. B. den aktuellen Ordner nicht mehr an.
printf '\033]633;A\007\033]633;B\007\033]633;E;tmux attach -t %s\007\033]633;C\007' "$name"

# ---------------------------------------------------------------- Anhängen
exec tmux attach -t "$name"
