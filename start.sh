#!/usr/bin/env bash
# Ein-Befehl-Einrichtung auf jedem Linux- oder macOS-Rechner der Welt.
#
# Aufruf auf einem fremden Rechner (nichts muss vorinstalliert sein außer
# curl und git):
#
#   curl -fsSL <URL-dieses-Skripts> | bash -s -- yrotciv11/srm-vollmacht
#
# Danach ist der Rechner fertig eingerichtet: Werkzeuge installiert,
# Repository geklont, PDF gebaut und geprüft.
#
# Voraussetzung: Ein GitHub-Konto mit Zugriff auf das Repository. Die
# Anmeldung erfolgt über einen Gerätecode – Sie tippen ihn auf einem
# beliebigen Gerät mit Browser ein, auch auf Ihrem Handy. Auf diesem Rechner
# wird kein Passwort eingegeben.
set -uo pipefail

REPO="${1:-}"
IFS=' ' read -r -a REST <<< "${2:-}"

GRUEN=$'\033[0;32m'; GELB=$'\033[0;33m'; ROT=$'\033[0;31m'; AUS=$'\033[0m'
SCHRITT() { printf '\n%s==> %s%s\n' "$GRUEN" "$1" "$AUS"; }
INFO()    { printf '    %s\n' "$1"; }
WARN()    { printf '%s    ! %s%s\n' "$GELB" "$1" "$AUS"; }
FEHLER()  { printf '%s    x %s%s\n' "$ROT" "$1" "$AUS"; }
ABBRUCH() { FEHLER "$1"; exit 1; }

printf '\n%s========================================================%s\n' "$GRUEN" "$AUS"
printf '%s  Vollmacht-Paket: Einrichtung auf diesem Rechner%s\n' "$GRUEN" "$AUS"
printf '%s========================================================%s\n' "$GRUEN" "$AUS"

if [ -z "$REPO" ]; then
  printf '\nAufruf:  curl -fsSL <URL> | bash -s -- <benutzer>/<repository>\n'
  printf 'Beispiel: curl -fsSL <URL> | bash -s -- yrotciv11/srm-vollmacht\n\n'
  exit 1
fi

# ------------------------------------------------------- 1. System erkennen
SCHRITT "1/6  System prüfen"
OS="$(uname -s)"
case "$OS" in
  Linux)   INFO "Linux erkannt";  PAKET="apt" ;;
  Darwin)  INFO "macOS erkannt";  PAKET="brew" ;;
  *)       ABBRUCH "Nicht unterstütztes System: $OS. Auf Windows bitte WSL verwenden." ;;
esac

if [ "$PAKET" = "apt" ] && ! command -v sudo >/dev/null 2>&1; then
  ABBRUCH "sudo fehlt. Für die Installation werden erhöhte Rechte gebraucht."
fi

for werkzeug in curl git; do
  command -v "$werkzeug" >/dev/null 2>&1 || ABBRUCH "$werkzeug fehlt und wird gebraucht."
  INFO "$werkzeug vorhanden"
done

# ------------------------------------------------------- 2. GitHub-Anmeldung
SCHRITT "2/6  Bei GitHub anmelden"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  INFO "bereits angemeldet als $(gh api user --jq .login 2>/dev/null || echo 'unbekannt')"
else
  if ! command -v gh >/dev/null 2>&1; then
    INFO "GitHub-Werkzeug (gh) installieren"
    if [ "$PAKET" = "apt" ]; then
      sudo mkdir -p -m 755 /etc/apt/keyrings
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
        || ABBRUCH "gh-Schlüssel konnte nicht geladen werden."
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      sudo apt-get update -qq && sudo apt-get install -y -qq gh \
        || ABBRUCH "gh-Installation fehlgeschlagen."
    else
      command -v brew >/dev/null 2>&1 || ABBRUCH "Homebrew fehlt. Siehe https://brew.sh"
      brew install -q gh || ABBRUCH "gh-Installation fehlgeschlagen."
    fi
    INFO "gh installiert"
  fi

  if [ -n "${GH_TOKEN:-}" ]; then
    INFO "Anmeldung über die Umgebungsvariable GH_TOKEN"
    printf '%s' "$GH_TOKEN" | gh auth login --with-token \
      || ABBRUCH "GH_TOKEN wurde von GitHub abgelehnt."
  else
    printf '\n'
    printf '    Gleich erscheint ein %sGerätecode%s (Format XXXX-XXXX).\n' "$GELB" "$AUS"
    printf '    Öffnen Sie auf einem beliebigen Gerät mit Browser – auch Ihrem\n'
    printf '    Handy – die Seite https://github.com/login/device und geben Sie\n'
    printf '    den Code dort ein. Dieser Rechner erhält kein Passwort.\n\n'
    gh auth login --hostname github.com --git-protocol https --web \
      || ABBRUCH "Anmeldung abgebrochen."
  fi
  INFO "angemeldet als $(gh api user --jq .login 2>/dev/null || echo 'unbekannt')"
fi

# ------------------------------------------------------ 3. Repository klonen
SCHRITT "3/6  Repository beziehen"
ORDNER="$(basename "$REPO")"
ZIEL="${REST[0]:-./$ORDNER}"

if [ -d "$ZIEL/.git" ]; then
  INFO "Repository vorhanden – aktualisiere"
  git -C "$ZIEL" pull --ff-only -q || WARN "Aktualisierung übersprungen"
else
  if ! gh repo clone "$REPO" "$ZIEL" -- -q 2>/dev/null; then
    ABBRUCH "Klonen fehlgeschlagen. Haben Sie Zugriff auf $REPO?"
  fi
  INFO "geklont nach $ZIEL"
fi
cd "$ZIEL" || ABBRUCH "Verzeichnis $ZIEL nicht erreichbar."
INFO "Arbeitsverzeichnis: $(pwd)"

# ------------------------------------------------------- 4. Werkzeuge
SCHRITT "4/6  Werkzeuge installieren (dauert einige Minuten)"
if [ -f .cursor/install.sh ]; then
  bash .cursor/install.sh 2>&1 | sed 's/^/    /' || WARN "Einrichtung meldete Probleme"
else
  WARN ".cursor/install.sh fehlt – überspringe Werkzeuginstallation"
fi

# ------------------------------------------------------- 5. Bauen und prüfen
SCHRITT "5/6  Dokument bauen"
if ! command -v typst >/dev/null 2>&1; then
  ABBRUCH "Typst fehlt. Bitte .cursor/install.sh erneut ausführen."
fi
python3 scripts/build_certified.py 2>&1 | sed 's/^/    /' \
  || WARN "Build meldete Probleme – siehe oben"

SCHRITT "6/6  Ausfüllbarkeit prüfen"
python3 scripts/check_form.py 2>&1 | sed 's/^/    /' \
  || WARN "Prüfung meldete Probleme – siehe oben"

# ------------------------------------------------------------- Abschluss
PDF="out/Vollmacht_Pruefung_Betreuung_Versicherungen.pdf"
printf '\n%s========================================================%s\n' "$GRUEN" "$AUS"
if [ -f "$PDF" ]; then
  printf '%s  Fertig. Das Dokument liegt hier:%s\n' "$GRUEN" "$AUS"
  printf '    %s/%s  (%s KB)\n\n' "$(pwd)" "$PDF" "$(( $(stat -c%s "$PDF" 2>/dev/null || stat -f%z "$PDF") / 1024 ))"
  printf '  Weiterarbeiten:\n'
  printf '    cd %s\n' "$(pwd)"
  printf '    python3 scripts/build_certified.py   # nach Textänderungen\n'
  printf '    python3 scripts/check_form.py        # Ausfüllbarkeit prüfen\n'
  printf '    pdftoppm -r 110 -png %s /tmp/seite   # Seiten ansehen\n\n' "$PDF"
  printf '  Kopie auf diesen Rechner holen:\n'
  printf '    Der Pfad oben ist bereits lokal. Zum Herunterladen per SFTP/SCP\n'
  printf '    oder über GitHub: out/ ist nicht versioniert, das PDF also\n'
  printf '    gezielt übertragen.\n\n'
else
  printf '%s  Einrichtung abgeschlossen, aber es wurde kein PDF erzeugt.%s\n' "$GELB" "$AUS"
  printf '    Bitte die Ausgabe oben prüfen.\n\n'
fi
printf '%s========================================================%s\n\n' "$GRUEN" "$AUS"
exit 0
