#!/usr/bin/env bash
#
# "Gleicher Stand auf jedem Rechner" einrichten.
#
# Dieses Skript sorgt dafür, dass Sie an jedem Rechner genau dort
# weitermachen, wo Sie aufgehört haben. Es richtet vier Dinge ein:
#
#   1. Dauerhafte Terminals   – laufende Prozesse überleben die Trennung
#   2. Arbeitsstand           – ein Befehl zeigt, wo Sie aufgehört haben
#   3. Einstellungen          – Cursor-Einstellungen wandern mit
#   4. Automatisches Sichern  – beim Anmelden wird der Stand angezeigt
#
# Aufruf:  bash arbeitsstand-einrichten.sh
# Prüfen:  bash arbeitsstand-einrichten.sh --pruefen
#
# Wiederholbar: Ein zweiter Aufruf ändert nichts kaputt.

set -eu

NUR_PRUEFEN=0
[ "${1:-}" = "--pruefen" ] && NUR_PRUEFEN=1

FETT='\033[1m'; GRUEN='\033[0;32m'; GELB='\033[0;33m'; ROT='\033[0;31m'; AUS='\033[0m'
[ -t 1 ] || { FETT=''; GRUEN=''; GELB=''; ROT=''; AUS=''; }

kopf()  { printf "\n${FETT}%s${AUS}\n" "$*"; }
ok()    { printf "    ${GRUEN}✓${AUS} %s\n" "$*"; }
warn()  { printf "    ${GELB}!${AUS} %s\n" "$*"; }
fehl()  { printf "    ${ROT}✗${AUS} %s\n" "$*"; }
info()  { printf "    %s\n" "$*"; }
titel() { printf "\n${FETT}================================================================${AUS}\n  %s\n${FETT}================================================================${AUS}\n" "$*"; }

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${HOME}/.local/bin"
ABLAGE="${HOME}/.arbeitsstand"

titel "Gleicher Stand auf jedem Rechner – Einrichtung"
info "Skripte aus: $HIER"
info "Ablage:      $ABLAGE"
[ "$NUR_PRUEFEN" = "1" ] && warn "Nur Prüfmodus – es wird nichts verändert."

if [ "$NUR_PRUEFEN" = "0" ] && ! sudo -n true 2>/dev/null; then
  info "Für die Installation werden Administratorrechte gebraucht."
  sudo -v || { fehl "Ohne Administratorrechte nicht möglich."; exit 1; }
fi

# ============================================================ 1. tmux
kopf "1. Dauerhafte Terminals (tmux)"

if command -v tmux >/dev/null 2>&1; then
  ok "vorhanden: $(tmux -V)"
else
  if [ "$NUR_PRUEFEN" = "0" ]; then
    info "wird installiert …"
    if sudo apt-get install -y -qq tmux >/dev/null 2>&1; then
      ok "installiert: $(tmux -V)"
    else
      fehl "Installation fehlgeschlagen"
    fi
  else
    fehl "tmux fehlt"
  fi
fi

# Damit tmux sich in Cursor unauffällig verhält: keine eigene Statusleiste,
# Durchreichen von Grafik- und Zwischenablage-Sequenzen an das äußere
# Terminal, und Mausbedienung wie gewohnt.
if [ "$NUR_PRUEFEN" = "0" ]; then
  if [ -f "${HOME}/.tmux.conf" ] && ! grep -q "arbeitsstand-einrichtung" "${HOME}/.tmux.conf" 2>/dev/null; then
    cp "${HOME}/.tmux.conf" "${HOME}/.tmux.conf.vorher-$(date +%Y%m%d%H%M%S)"
    warn "vorhandene .tmux.conf gesichert"
  fi
  if ! grep -q "arbeitsstand-einrichtung" "${HOME}/.tmux.conf" 2>/dev/null; then
    cat >> "${HOME}/.tmux.conf" <<'TMUXCONF'

# --- arbeitsstand-einrichtung: für Cursor/VS Code angepasst ---
set -g status off
set -g mouse on
set -g allow-rename on
setw -g automatic-rename on
set -g allow-passthrough on
set -g default-terminal "tmux-256color"
set -g history-limit 50000
set -g escape-time 10
# --- Ende arbeitsstand-einrichtung ---
TMUXCONF
    ok "tmux-Einstellungen ergänzt"
  else
    ok "tmux-Einstellungen schon vorhanden"
  fi
fi

# ============================================ 2. Skripte bereitstellen
kopf "2. Skripte bereitstellen"

if [ "$NUR_PRUEFEN" = "0" ]; then
  mkdir -p "$BIN" "$ABLAGE"
  for skript in terminal-dauerhaft.sh arbeitsstand.sh; do
    if [ -f "${HIER}/${skript}" ]; then
      install -m 755 "${HIER}/${skript}" "${BIN}/${skript}"
      ok "$skript bereitgestellt"
    else
      fehl "$skript fehlt in $HIER"
    fi
  done
  # Kurzbefehle ohne ".sh"
  ln -sf "${BIN}/arbeitsstand.sh" "${BIN}/arbeitsstand" 2>/dev/null || true
  ok "Kurzbefehl 'arbeitsstand' angelegt"
else
  for skript in terminal-dauerhaft.sh arbeitsstand.sh; do
    [ -f "${HIER}/${skript}" ] && ok "$skript vorhanden" || fehl "$skript fehlt"
  done
fi

# Ist ~/.local/bin im Suchpfad?
case ":${PATH}:" in
  *":${BIN}:"*) ok "~/.local/bin ist im Suchpfad" ;;
  *)
    if [ "$NUR_PRUEFEN" = "0" ]; then
      for datei in "${HOME}/.bashrc" "${HOME}/.zshrc" "${HOME}/.profile"; do
        [ -f "$datei" ] || continue
        if ! grep -q '.local/bin' "$datei" 2>/dev/null; then
          printf '\n# arbeitsstand-einrichtung\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$datei"
          ok "Suchpfad in $(basename "$datei") ergänzt"
        fi
      done
    else
      warn "~/.local/bin nicht im Suchpfad"
    fi
    ;;
esac

# ============================== 3. Cursor auf das Terminal einstellen
kopf "3. Cursor auf dauerhafte Terminals einstellen"

# Diese Einstellungen gehören auf die Maschine, nicht auf den Laptop. Dann
# gelten sie für jedes Gerät, mit dem Sie sich verbinden – auch für ein
# Gerät, auf dem Sie Cursor zum ersten Mal starten.
PROFIL_JSON='{
  "terminal.integrated.profiles.linux": {
    "Dauerhaft": {
      "path": "/bin/bash",
      "args": ["-c", "exec $HOME/.local/bin/terminal-dauerhaft.sh"],
      "icon": "server-process"
    }
  },
  "terminal.integrated.defaultProfile.linux": "Dauerhaft",
  "terminal.integrated.automationProfile.linux": {
    "path": "/bin/bash",
    "args": ["-lc", "exec $SHELL -l"]
  },
  "terminal.integrated.enablePersistentSessions": false,
  "terminal.integrated.scrollback": 10000,
  "remote.SSH.restoreForwardedPorts": true,
  "files.hotExit": "onExitAndWindowClose"
}'

# Bei macOS heißen die Profile anders.
PROFIL_JSON_MAC='{
  "terminal.integrated.profiles.osx": {
    "Dauerhaft": {
      "path": "/bin/bash",
      "args": ["-c", "exec $HOME/.local/bin/terminal-dauerhaft.sh"],
      "icon": "server-process"
    }
  },
  "terminal.integrated.defaultProfile.osx": "Dauerhaft",
  "terminal.integrated.enablePersistentSessions": false,
  "remote.SSH.restoreForwardedPorts": true,
  "files.hotExit": "onExitAndWindowClose"
}'

if [ "$NUR_PRUEFEN" = "0" ]; then
  EINGERICHTET=0
  for server in ".cursor-server" ".vscode-server" ".cursor-server-insiders" ".vscode-server-insiders"; do
    ZIEL="${HOME}/${server}/data/Machine"
    mkdir -p "$ZIEL"
    DATEI="${ZIEL}/settings.json"

    # Vorhandene Einstellungen bewahren und ergänzen – nichts überschreiben.
    python3 - "$DATEI" "$PROFIL_JSON" "$PROFIL_JSON_MAC" <<'PY'
import json, sys, os
datei, linux_json, mac_json = sys.argv[1], sys.argv[2], sys.argv[3]
vorhanden = {}
if os.path.exists(datei):
    try:
        with open(datei) as f:
            inhalt = f.read().strip()
        if inhalt:
            vorhanden = json.loads(inhalt)
    except Exception:
        # Unlesbar? Dann sichern und neu anfangen.
        os.rename(datei, datei + ".unlesbar")
        vorhanden = {}
ergaenzung = json.loads(mac_json if sys.platform == 'darwin' else linux_json)
vorhanden.update(ergaenzung)
with open(datei, "w") as f:
    json.dump(vorhanden, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
    if grep -q "terminal-dauerhaft" "$DATEI" 2>/dev/null; then
      ok "eingerichtet: ~/${server}/data/Machine/settings.json"
      EINGERICHTET=$((EINGERICHTET + 1))
    fi
  done
  [ "$EINGERICHTET" = "0" ] && warn "kein Server-Verzeichnis gefunden – erscheint beim ersten Verbinden"
else
  for server in ".cursor-server" ".vscode-server"; do
    DATEI="${HOME}/${server}/data/Machine/settings.json"
    [ -f "$DATEI" ] && grep -q "terminal-dauerhaft" "$DATEI" && ok "eingerichtet: ~/${server}" || info "~/${server}: noch nicht eingerichtet"
  done
fi

# ================================= 4. Arbeitsstand beim Anmelden zeigen
kopf "4. Beim Anmelden an den letzten Stand erinnern"

if [ "$NUR_PRUEFEN" = "0" ]; then
  MARKER="# arbeitsstand-einrichtung"
  for datei in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    [ -f "$datei" ] || continue
    if ! grep -q "$MARKER" "$datei" 2>/dev/null; then
      cat >> "$datei" <<'BASHRC'

# arbeitsstand-einrichtung
# Beim Anmelden kurz zeigen, wo man aufgehört hat – nur in einer
# Anmeldesitzung, nicht in jedem Unterfenster.
if [ -n "${PS1:-}" ] && [ -z "${ARBEITSSTAND_GEZEIGT:-}" ] && [ -x "$HOME/.local/bin/arbeitsstand" ]; then
  export ARBEITSSTAND_GEZEIGT=1
  if [ -f "$HOME/.arbeitsstand/zuletzt.txt" ]; then
    "$HOME/.local/bin/arbeitsstand" zeigen 2>/dev/null | head -40
  fi
fi
# Ende arbeitsstand-einrichtung
BASHRC
      ok "Erinnerung in $(basename "$datei") eingetragen"
    else
      ok "Erinnerung in $(basename "$datei") schon vorhanden"
    fi
  done
fi

# ================================================= 5. Aufräumen alter Sitzungen
kopf "5. Aufräumen nicht mehr gebrauchter Sitzungen"

# Mit der Zeit sammeln sich abgetrennte Sitzungen an, in denen nichts mehr
# läuft. Ein täglicher Lauf räumt sie weg – aber nur, wenn darin wirklich
# kein Programm mehr arbeitet. Sonst würde ein laufender Build abgeschossen.
if [ "$NUR_PRUEFEN" = "0" ]; then
  cat > "${BIN}/sitzungen-aufraeumen.sh" <<'AUFRAEUMEN'
#!/usr/bin/env bash
# Beendet abgetrennte Sitzungen, in denen kein Programm mehr läuft.
set -u
command -v tmux >/dev/null 2>&1 || exit 0
tmux list-sessions -F '#{session_name}|#{session_attached}' 2>/dev/null | while IFS='|' read -r name angehaengt; do
  [ -n "$name" ] || continue
  [ "$angehaengt" -gt 0 ] 2>/dev/null && continue
  # Läuft in irgendeinem Fenster noch ein echtes Programm?
  aktiv=0
  for befehl in $(tmux list-panes -t "$name" -F '#{pane_current_command}' 2>/dev/null); do
    case "$befehl" in
      bash|zsh|sh|fish|dash|tmux) ;;
      *) aktiv=1 ;;
    esac
  done
  [ "$aktiv" -eq 0 ] && tmux kill-session -t "$name" 2>/dev/null || true
done
AUFRAEUMEN
  chmod 755 "${BIN}/sitzungen-aufraeumen.sh"
  ok "Aufräumskript angelegt"

  # Täglich laufen lassen
  if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
    sudo tee /etc/systemd/system/tmux-aufraeumen.service >/dev/null <<DIENST
[Unit]
Description=Abgetrennte tmux-Sitzungen ohne laufende Programme beenden

[Service]
Type=oneshot
User=$(id -un)
ExecStart=${BIN}/sitzungen-aufraeumen.sh
DIENST
    sudo tee /etc/systemd/system/tmux-aufraeumen.timer >/dev/null <<'ZEIT'
[Unit]
Description=Tägliches Aufräumen abgetrennter tmux-Sitzungen

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
ZEIT
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo systemctl enable --now tmux-aufraeumen.timer >/dev/null 2>&1 || true
    if systemctl is-active --quiet tmux-aufraeumen.timer 2>/dev/null; then
      ok "läuft täglich automatisch"
    else
      warn "Zeitgeber angelegt, startet aber noch nicht"
    fi
  else
    info "kein systemd – Aufräumen bei Bedarf von Hand starten"
  fi
fi

# ==================================================== 6. Stand von jetzt
kopf "6. Derzeitigen Stand sichern"

if [ "$NUR_PRUEFEN" = "0" ] && [ -x "${BIN}/arbeitsstand.sh" ]; then
  "${BIN}/arbeitsstand.sh" merken >/dev/null 2>&1 && ok "Stand gesichert" || warn "Sichern übersprungen"
fi

# ==================================================== 7. Prüfung
kopf "7. Prüfung"

if [ "$NUR_PRUEFEN" = "0" ]; then
  # Terminals
  command -v tmux >/dev/null 2>&1 && ok "tmux bereit" || fehl "tmux fehlt"
  [ -x "${BIN}/terminal-dauerhaft.sh" ] && ok "Terminal-Skript bereit" || fehl "Terminal-Skript fehlt"
  [ -x "${BIN}/arbeitsstand.sh" ] && ok "Arbeitsstand-Skript bereit" || fehl "Arbeitsstand-Skript fehlt"
  # Cursor
  for server in ".cursor-server" ".vscode-server"; do
    [ -f "${HOME}/${server}/data/Machine/settings.json" ] && \
      grep -q "terminal-dauerhaft" "${HOME}/${server}/data/Machine/settings.json" 2>/dev/null && \
      ok "Cursor-Einstellung in ~/${server} gesetzt"
  done
  # Kurzprobe: Lässt sich eine Sitzung anlegen und wiederfinden?
  tmux kill-session -t probe-arbeitsstand 2>/dev/null || true
  tmux new-session -d -s probe-arbeitsstand 'echo bereit; sleep 30' 2>/dev/null
  sleep 1
  if tmux has-session -t probe-arbeitsstand 2>/dev/null; then
    ok "Terminalsitzung lässt sich anlegen und wiederfinden"
    tmux kill-session -t probe-arbeitsstand 2>/dev/null || true
  else
    fehl "Terminalsitzung funktioniert nicht"
  fi
fi

titel "Fertig"

cat <<BERICHT

  Ab jetzt gilt für jeden Rechner, mit dem Sie sich verbinden:

  ---------------------------------------------------------------
  WAS VON ALLEIN GEHT
  ---------------------------------------------------------------
  · Ihre Dateien und der Projektstand     – liegen auf dieser Maschine
  · Ihre Cursor-Erweiterungen             – liegen auf dieser Maschine
  · Die offenen Dateien und das Fenster   – merkt sich die Maschine
    (sofern Sie den Ordner gleich öffnen)
  · Ihre Einstellungen                    – sind hier hinterlegt

  ---------------------------------------------------------------
  WAS EINEN HANDGRIFF BRAUCHT
  ---------------------------------------------------------------
  · Laufende Terminals: Beim Öffnen eines Terminals hängen Sie sich
    automatisch an die Sitzung von vorhin an. Sie sehen genau die
    Ausgaben und laufenden Programme von vorher.

  · Wo Sie aufgehört haben:  arbeitsstand zeigen

  · Beim Weggehen den Stand sichern:  arbeitsstand merken

  ---------------------------------------------------------------
  DER ERSTE HANDGRIFF AUF EINEM NEUEN RECHNER
  ---------------------------------------------------------------
  Einmal ausführen, danach wandern die Einstellungen mit:

    arbeitsstand einstellungen

  Auf dem neuen Rechner dann:

    arbeitsstand zurueck

BERICHT

if [ "$NUR_PRUEFEN" = "0" ]; then
  printf "  ${FETT}Damit Cursor die Einstellungen übernimmt: einmal neu verbinden.${AUS}\n\n"
fi