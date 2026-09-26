#!/usr/bin/env bash
#
# "Arbeitsplatz überall" einrichten.
#
# Macht aus einem beliebigen Linux- oder macOS-Rechner eine Maschine, auf der
# Ihre Projekte liegen und an der Sie von jedem Computer der Welt mit Cursor
# arbeiten können – auf drei Wegen:
#
#   Weg 1  Cursor Desktop → Remote SSH     (der volle Cursor, wie zu Hause)
#   Weg 2  Browser → Editor                (nichts zu installieren)
#   Weg 3  cursor.com/agents               (vom Handy, ohne Vorbereitung)
#
# Aufruf:   bash einrichten.sh
# Prüfen:   bash einrichten.sh --pruefen     (nur nachsehen, nichts ändern)
#
# Das Skript ist wiederholbar: Ein zweiter Aufruf ändert nichts kaputt.

# Bewusst ohne "-o pipefail": Sobald ein "head" die Ausgabe frueh schliesst,
# bekommt der vorherige Befehl ein SIGPIPE und liefert einen Fehlercode.
# Mit pipefail wuerde das Skript an solchen Stellen grundlos abbrechen –
# bei der Versionsabfrage unten ist genau das passiert.
set -eu

NUR_PRUEFEN=0
[ "${1:-}" = "--pruefen" ] && NUR_PRUEFEN=1

# ---------------------------------------------------------------- Darstellung
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  GRUEN='\033[0;32m'; GELB='\033[0;33m'; ROT='\033[0;31m'
  FETT='\033[1m'; AUS='\033[0m'
else
  GRUEN=''; GELB=''; ROT=''; FETT=''; AUS=''
fi

kopf()  { printf "\n${FETT}%s${AUS}\n" "$*"; }
info()  { printf "    %s\n" "$*"; }
ok()    { printf "    ${GRUEN}✓${AUS} %s\n" "$*"; }
warn()  { printf "    ${GELB}!${AUS} %s\n" "$*"; }
fehl()  { printf "    ${ROT}✗${AUS} %s\n" "$*"; }
titel() { printf "\n${FETT}================================================================${AUS}\n  %s\n${FETT}================================================================${AUS}\n" "$*"; }

# ------------------------------------------------------------------ Erkennung
SYSTEM="$(uname -s)"
case "$SYSTEM" in
  Linux)  BETRIEB="linux" ;;
  Darwin) BETRIEB="macos" ;;
  *) fehl "Unbekanntes System: $SYSTEM"; exit 1 ;;
esac

# Den tatsächlich angemeldeten Benutzer ermitteln. $USER kann in
# nicht-interaktiven Sitzungen fehlen oder falsch gesetzt sein – dann
# stünde in der Anleitung ein Benutzer, den es nicht gibt.
BENUTZER="$(id -un 2>/dev/null || echo "${USER:-benutzer}")"
if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
  BENUTZER="$SUDO_USER"
fi
ZIEL="${HOME}/projekte"

titel "Arbeitsplatz überall – Einrichtung"
info "System:   $BETRIEB ($(uname -m))"
info "Benutzer: $BENUTZER"
info "Projekte: $ZIEL"
[ "$NUR_PRUEFEN" = "1" ] && warn "Nur Prüfmodus – es wird nichts verändert."

if [ "$NUR_PRUEFEN" = "0" ]; then
  if ! sudo -n true 2>/dev/null; then
    info "Für die Installation werden Administratorrechte gebraucht."
    sudo -v || { fehl "Ohne Administratorrechte nicht möglich."; exit 1; }
  fi
fi

# =============================================================== 1. Grundlagen
kopf "1. Grundlagen prüfen"

for werkzeug in curl git ssh; do
  if command -v "$werkzeug" >/dev/null 2>&1; then
    ok "$werkzeug vorhanden"
  else
    if [ "$NUR_PRUEFEN" = "1" ]; then
      fehl "$werkzeug fehlt"
      continue
    fi
    warn "$werkzeug fehlt – wird installiert"
    if [ "$BETRIEB" = "linux" ]; then
      sudo apt-get install -y -qq "$werkzeug" >/dev/null 2>&1 || true
    else
      fehl "$werkzeug fehlt. Auf macOS: xcode-select --install"
    fi
  fi
done

# Die Cursor-Server-Anwendung braucht glibc 2.28 oder neuer.
# Ohne das schlägt Remote SSH mit einer schwer deutbaren Meldung fehl.
if [ "$BETRIEB" = "linux" ]; then
  # Versionsnummer sauber herausziehen – "2.39" ergibt Haupt=2, Neben=39.
  GLIBC="$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)"
  if [ -n "$GLIBC" ]; then
    HAUPT="${GLIBC%%.*}"
    NEBEN="${GLIBC#*.}"
    NEBEN="${NEBEN%%.*}"
    if [ -n "$HAUPT" ] && [ -n "$NEBEN" ] && \
       { [ "$HAUPT" -gt 2 ] || { [ "$HAUPT" -eq 2 ] && [ "$NEBEN" -ge 28 ]; }; }; then
      ok "glibc $GLIBC genügt für Cursor"
    else
      fehl "glibc $GLIBC ist zu alt (Cursor braucht mindestens 2.28)"
      warn "Ubuntu 22.04 oder neuer verwenden"
    fi
  else
    warn "Version der Systembibliothek nicht ermittelbar – meist unkritisch"
  fi
fi

# ============================================================ 2. Projektordner
kopf "2. Ordner für Ihre Projekte"

if [ -d "$ZIEL" ]; then
  ok "$ZIEL ist schon da"
else
  if [ "$NUR_PRUEFEN" = "0" ]; then
    mkdir -p "$ZIEL"
    ok "$ZIEL angelegt"
  fi
fi

if [ "$NUR_PRUEFEN" = "0" ]; then
  cat > "$ZIEL/LIESMICH.md" <<'LIESMICH'
# Ihre Projekte

Hier liegen Ihre Projekte. Jeder Unterordner ist ein Projekt.

## In Cursor öffnen

Auf einem Rechner mit Cursor:
1. Cursor starten
2. Verbindung aufbauen (siehe Anleitung)
3. Ordner wählen: dieser Ordner

## Im Browser bearbeiten

Ohne etwas zu installieren – im Browser:
Editor öffnen, dann diesen Ordner wählen.

## Ein neues Projekt beginnen

```bash
cd ~/projekte
mkdir mein-neues-projekt
cd mein-neues-projekt
git init
```
LIESMICH
  ok "Kurzanleitung abgelegt"
fi

# ============================================================== 3. Cursor-CLI
kopf "3. Cursor-Werkzeug (für Agents auf dieser Maschine)"

if command -v agent >/dev/null 2>&1; then
  ok "bereits vorhanden: $(agent --version 2>/dev/null | head -1)"
else
  if [ "$NUR_PRUEFEN" = "0" ]; then
    info "wird geladen …"
    if curl -fsSL --retry 3 --max-time 300 https://cursor.com/install | bash >/dev/null 2>&1; then
      if command -v agent >/dev/null 2>&1; then
        ok "installiert"
      else
        warn "installiert, aber noch nicht im Suchpfad – neue Sitzung nötig"
      fi
    else
      fehl "Download fehlgeschlagen – Verbindung prüfen"
    fi
  fi
fi

# ============================================== 4. Editor im Browser (Weg 2)
kopf "4. Editor im Browser (nichts zu installieren)"

if command -v code-server >/dev/null 2>&1; then
  ok "bereits vorhanden: $(code-server --version 2>/dev/null | head -1)"
else
  if [ "$NUR_PRUEFEN" = "0" ]; then
    info "wird installiert …"
    if curl -fsSL --retry 3 --max-time 300 https://code-server.dev/install.sh | sh >/dev/null 2>&1; then
      ok "installiert"
    else
      fehl "Installation fehlgeschlagen"
    fi
  fi
fi

# Der Editor wird bewusst NICHT ins offene Internet gestellt, sondern nur
# auf der Maschine selbst angeboten. Erreichbar ist er über eine
# SSH-Weiterleitung – damit sieht ihn von außen niemand.
if command -v code-server >/dev/null 2>&1 && [ "$NUR_PRUEFEN" = "0" ]; then
  mkdir -p "$HOME/.config/code-server"
  PASSWORT="$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 20)"
  cat > "$HOME/.config/code-server/config.yaml" <<KONFIG
bind-addr: 127.0.0.1:8080
auth: password
password: ${PASSWORT}
cert: false
KONFIG
  chmod 600 "$HOME/.config/code-server/config.yaml"
  ok "Zugang eingerichtet (nur über die Maschine selbst erreichbar)"
  echo "$PASSWORT" > "$HOME/.code-server-passwort"
  chmod 600 "$HOME/.code-server-passwort"
fi

# ============================================== 5. Dauerbetrieb (Weg 1 + 2)
kopf "5. Dauerbetrieb – läuft nach einem Neustart von allein"

if [ "$BETRIEB" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
  if [ "$NUR_PRUEFEN" = "0" ]; then
    # Editor im Browser als Dienst
    sudo tee /etc/systemd/system/browser-editor.service >/dev/null <<DIENST
[Unit]
Description=Editor im Browser (code-server)
After=network.target

[Service]
Type=simple
User=${BENUTZER}
ExecStart=/usr/bin/code-server --config ${HOME}/.config/code-server/config.yaml
Restart=always
RestartSec=5
Environment=HOME=${HOME}

[Install]
WantedBy=multi-user.target
DIENST
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo systemctl enable browser-editor >/dev/null 2>&1 || true
    sudo systemctl restart browser-editor >/dev/null 2>&1 || true
    sleep 2
    if systemctl is-active --quiet browser-editor 2>/dev/null; then
      ok "Editor läuft dauerhaft"
    else
      warn "Dienst angelegt, startet aber noch nicht – später prüfen"
    fi
  fi
elif [ "$BETRIEB" = "macos" ]; then
  info "Auf macOS: Editor bei Bedarf von Hand starten – siehe Anleitung"
fi

# ============================================================ 6. Zugang (SSH)
kopf "6. Zugang für Cursor einrichten"

if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  ok "Schlüssel vorhanden"
else
  if [ "$NUR_PRUEFEN" = "0" ]; then
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$BENUTZER@arbeitsplatz" >/dev/null 2>&1
    ok "Schlüssel erzeugt"
  fi
fi

if [ "$NUR_PRUEFEN" = "0" ] && [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  if ! grep -qF "$(cat "$HOME/.ssh/id_ed25519.pub")" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    cat "$HOME/.ssh/id_ed25519.pub" >> "$HOME/.ssh/authorized_keys"
    ok "Schlüssel hinterlegt"
  else
    ok "Schlüssel schon hinterlegt"
  fi
fi

# =================================================================== 7. Bericht
titel "Fertig – so verbinden Sie sich"

# Die richtige Adresse ermitteln. Reine "hostname -I" liefert oft eine
# interne Adresse, die von außen nicht erreichbar ist (etwa 169.254.x.x
# oder eine Docker-Adresse). Deshalb wird zuerst die Adresse des
# Standardwegs genommen – das ist die, über die die Maschine wirklich
# am Netz hängt.
IP=""
if command -v ip >/dev/null 2>&1; then
  IP="$(ip route get 1.1.1.1 2>/dev/null | grep -oE 'src [0-9.]+' | awk '{print $2}' | head -1)"
fi
if [ -z "$IP" ] && command -v hostname >/dev/null 2>&1; then
  IP="$(hostname -I 2>/dev/null | tr ' ' '\n' \
        | grep -vE '^(127\.|169\.254\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[01]\.|10\.|$)' \
        | head -1)"
fi
if [ -z "$IP" ]; then
  IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi
[ -z "$IP" ] && IP="<IP-dieser-Maschine>"

# Ist die Adresse nur im eigenen Netz gültig, wird das ausdrücklich gesagt.
# Sonst sucht man von unterwegs vergeblich danach.
FALLS_INTERN=""
case "$IP" in
  127.*|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|169.254.*)
    FALLS_INTERN="  ACHTUNG: ${IP} gilt nur im eigenen Netz. Für den Zugriff
  aus dem Internet brauchen Sie die öffentliche Adresse: beim Anbieter
  nachsehen (dort steht sie unter „Server" oder „Netzwerk")."
    ;;
esac

cat <<BERICHT

  Diese Maschine ist bereit. Auf ihr liegen Ihre Projekte in
  $ZIEL
${FALLS_INTERN}

  ---------------------------------------------------------------
  WEG 1 – Der volle Cursor (wenn Sie Cursor installieren können)
  ---------------------------------------------------------------
  Auf dem Rechner, an dem Sie sitzen:

    1. Cursor installieren:            https://cursor.com/downloads
    2. In Cursor: Erweiterungen öffnen (Strg+Umschalt+X)
    3. Nach "Remote - SSH" suchen und installieren
    4. Strg+Umschalt+P drücken, "Remote-SSH: Connect to Host" wählen
    5. Als Adresse eingeben:           ${BENUTZER}@${IP}
    6. Ordner öffnen:                  ${ZIEL}

  Ab hier ist alles genau wie an Ihrem eigenen Rechner: Dateien,
  Terminal, Erweiterungen, der Cursor-Agent.

  ---------------------------------------------------------------
  WEG 2 – Editor im Browser (nichts zu installieren)
  ---------------------------------------------------------------
  Zuerst auf Ihrem Rechner eine Verbindung herstellen:

    ssh -L 8080:localhost:8080 ${BENUTZER}@${IP}

  Dann im Browser öffnen:             http://localhost:8080

  Das Passwort steht auf der Maschine in:  ~/.code-server-passwort

  Warum der Umweg? Weil der Editor dadurch von außen unsichtbar
  bleibt. Nur wer sich anmelden kann, kommt an ihn heran.

  ---------------------------------------------------------------
  WEG 3 – Vom Handy, ohne Vorbereitung
  ---------------------------------------------------------------
  Browser öffnen:                     https://cursor.com/agents

  Dort anmelden, Repository wählen, Auftrag beschreiben.
  Der Agent arbeitet, während Sie unterwegs sind.

BERICHT

if [ "$NUR_PRUEFEN" = "0" ]; then
  kopf "Zustand"
  command -v agent >/dev/null 2>&1 && ok "Cursor-Werkzeug bereit" || warn "Cursor-Werkzeug fehlt noch"
  command -v code-server >/dev/null 2>&1 && ok "Browser-Editor bereit" || warn "Browser-Editor fehlt noch"
  systemctl is-active --quiet browser-editor 2>/dev/null && ok "Editor läuft dauerhaft" || info "Editor: kein Dauerbetrieb (auf macOS normal)"
  ok "Projektordner bereit"
fi

printf "\n"
