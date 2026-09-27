#!/usr/bin/env bash
#
# Arbeitsstand sichern und wiederfinden.
#
# Zweck: Wenn Sie an einen anderen Rechner gehen, wollen Sie nicht suchen
# müssen, wo Sie aufgehört haben. Dieses Skript beantwortet drei Fragen:
#
#   1. Wo stand ich?          (Git-Stand, letzte Änderungen, Notizen)
#   2. Was lief gerade?       (laufende Terminals und Prozesse)
#   3. Was habe ich dabei?    (meine Cursor-Einstellungen, Erweiterungen)
#
# Aufrufe:
#   arbeitsstand.sh merken        Stand jetzt sichern (beim Weggehen)
#   arbeitsstand.sh zeigen        Stand anzeigen (beim Ankommen)
#   arbeitsstand.sh einstellungen Meine Cursor-Einstellungen mitsichern
#   arbeitsstand.sh zurueck       Einstellungen auf diesem Rechner einsetzen
#
# Alles wird unter ~/.arbeitsstand/ abgelegt.

set -u

ABLAGE="${HOME}/.arbeitsstand"
NACHRICHT="${ABLAGE}/notiz.txt"
LETZTE="${ABLAGE}/zuletzt.txt"
HEUTE="$(date '+%Y-%m-%d %H:%M')"

FETT='\033[1m'; GRUEN='\033[0;32m'; GELB='\033[0;33m'; AUS='\033[0m'
[ -t 1 ] || { FETT=''; GRUEN=''; GELB=''; AUS=''; }

titel() { printf "\n${FETT}=== %s ===${AUS}\n" "$*"; }
gut()   { printf "  ${GRUEN}✓${AUS} %s\n" "$*"; }
hin()   { printf "  %s\n" "$*"; }
acht()  { printf "  ${GELB}!${AUS} %s\n" "$*"; }

mkdir -p "$ABLAGE"

# ============================================================ 1. MERKEN
merken() {
  titel "Arbeitsstand sichern – $HEUTE"

  # --- Projekte: Git-Stand ---
  local gefunden=0
  : > "${ABLAGE}/projekte.txt"
  # Alle üblichen Orte durchsuchen. Gefundene Projekte werden über ihren
  # vollständigen Pfad entdoppelt – falls ein Ort innerhalb eines anderen
  # liegt, taucht ein Projekt trotzdem nur einmal auf.
  local ort_liste="" kandidat
  for kandidat in "$HOME/projekte" "$HOME/Projekte" "$HOME/work" "$HOME/repos" "$HOME/code"; do
    [ -d "$kandidat" ] && ort_liste="${ort_liste}${kandidat}
"
  done
  # Wenn nichts davon da ist, wenigstens das Benutzerverzeichnis ansehen.
  [ -z "$ort_liste" ] && ort_liste="${HOME}
"

  local gesehen=""
  for basis in $ort_liste; do
    [ -d "$basis" ] || continue
    while IFS= read -r ordner; do
      [ -n "$ordner" ] || continue
      command -v git >/dev/null 2>&1 || break
      git -C "$ordner" rev-parse --git-dir >/dev/null 2>&1 || continue
      # Randordner überspringen: Werkzeugkästen, Zwischenspeicher, Bibliotheken.
      # Das sind keine Projekte, an denen man arbeitet.
      case "$ordner" in
        */.nvm/*|*/.cache/*|*/.local/*|*/.vscode*/*|*/.cursor*/*|*/node_modules/*|*/.git/*|*/.npm/*)
          continue ;;
      esac
      # Schon gesehen? Dann überspringen.
      case " $gesehen " in
        *" $ordner "*) continue ;;
      esac
      gesehen="${gesehen} ${ordner}"
      local name zweig offen letzte
      name="$(basename "$ordner")"
      zweig="$(git -C "$ordner" rev-parse --abbrev-ref HEAD 2>/dev/null)"
      offen="$(git -C "$ordner" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      letzte="$(git -C "$ordner" log -1 --format='%h %s' 2>/dev/null)"
      printf '%s|%s|%s|%s|%s\n' "$ordner" "$name" "$zweig" "$offen" "$letzte" >> "${ABLAGE}/projekte.txt"
      gefunden=$((gefunden + 1))
    done < <(find "$basis" -maxdepth 3 -type d -name .git -printf '%h\n' 2>/dev/null | sort -u)
  done

  if [ "$gefunden" -gt 0 ]; then
    gut "$gefunden Projekt(e) erfasst"
    while IFS='|' read -r ordner name zweig offen letzte; do
      if [ "$offen" -gt 0 ]; then
        printf "    %-24s Zweig %-14s %s nicht gesicherte Änderungen\n" "$name" "$zweig" "$offen"
      else
        printf "    %-24s Zweig %-14s alles gesichert\n" "$name" "$zweig"
      fi
    done < "${ABLAGE}/projekte.txt"
  else
    hin "keine Projekte gefunden (erwartet unter ~/projekte)"
  fi

  # --- Laufende Terminals ---
  : > "${ABLAGE}/terminals.txt"
  if command -v tmux >/dev/null 2>&1; then
    tmux list-sessions -F '#{session_name}|#{session_windows}|#{session_attached}' 2>/dev/null \
      > "${ABLAGE}/terminals.txt" || true
    local anzahl
    anzahl="$(wc -l < "${ABLAGE}/terminals.txt" | tr -d ' ')"
    if [ "$anzahl" -gt 0 ]; then
      gut "$anzahl Terminal(s) laufen weiter"
      while IFS='|' read -r sname sfenster sangehaengt; do
        local was
        was="$(tmux list-panes -t "$sname" -F '#{pane_current_command}' 2>/dev/null | tr '\n' ' ')"
        printf "    %-14s %s\n" "$sname" "${was}"
      done < "${ABLAGE}/terminals.txt"
    else
      hin "keine laufenden Terminals"
    fi
  fi

  # --- Einstellungen ---
  einstellungen >/dev/null 2>&1 || true

  date '+%Y-%m-%d %H:%M:%S' > "$LETZTE"
  printf "\n  Gesichert unter: %s\n" "$ABLAGE"
  printf "  Beim nächsten Rechner:  arbeitsstand.sh zeigen\n\n"
}

# ========================================================== 2. ZEIGEN
zeigen() {
  titel "Wo Sie aufgehört haben"

  if [ -f "$LETZTE" ]; then
    hin "zuletzt gesichert: $(cat "$LETZTE")"
  elif [ -s "${ABLAGE}/projekte.txt" ] || [ -s "${ABLAGE}/terminals.txt" ]; then
    hin "Stand vorhanden (kein Zeitstempel – mit 'arbeitsstand.sh merken' erneuern)"
  else
    acht "noch nichts gesichert – einmal 'arbeitsstand.sh merken' ausführen"
  fi

  # --- Projekte ---
  if [ -s "${ABLAGE}/projekte.txt" ]; then
    titel "Projekte"
    while IFS='|' read -r ordner name zweig offen letzte; do
      printf "  ${FETT}%s${AUS}\n" "$name"
      printf "    Ordner:  %s\n" "$ordner"
      printf "    Zweig:   %s\n" "$zweig"
      if [ "$offen" -gt 0 ]; then
        printf "    ${GELB}%s Datei(en) noch nicht gesichert${AUS}\n" "$offen"
      fi
      printf "    Zuletzt: %s\n" "$letzte"
      # Was hat sich seit dem letzten Sichern geändert?
      if [ -d "$ordner/.git" ]; then
        local neu
        neu="$(git -C "$ordner" status --porcelain 2>/dev/null | head -5)"
        if [ -n "$neu" ]; then
          printf "    Seither geändert:\n"
          printf '%s\n' "$neu" | while read -r zeile; do printf "      %s\n" "$zeile"; done
        fi
      fi
    done < "${ABLAGE}/projekte.txt"
  fi

  # --- Terminals ---
  titel "Laufende Terminals"
  if command -v tmux >/dev/null 2>&1; then
    local laufend
    laufend="$(tmux list-sessions -F '#{session_name}' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$laufend" -gt 0 ]; then
      gut "$laufend Terminal(s) laufen noch – mit 'tmux attach -t NAME' hineinsehen"
      tmux list-sessions -F '    #{session_name}: #{session_windows} Fenster' 2>/dev/null
    else
      hin "keine Terminals mehr offen"
    fi
  fi

  # --- Notiz ---
  if [ -s "$NACHRICHT" ]; then
    titel "Ihre Notiz"
    cat "$NACHRICHT"
  fi

  # --- Einstellungen ---
  if [ -d "${ABLAGE}/einstellungen" ]; then
    local n
    n="$(find "${ABLAGE}/einstellungen" -type f 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$n" -gt 0 ]; then
      titel "Einstellungen"
      gut "$n Datei(en) gesichert"
      hin "einsetzen auf diesem Rechner:  arbeitsstand.sh zurueck"
    fi
  fi

  printf "\n"
}

# ================================================== 3. EINSTELLUNGEN
# Cursor synchronisiert Einstellungen nicht zwischen Rechnern (laut
# Cursor-Forum funktioniert die Synchronisation nur in VS Code, nicht in
# Cursor). Deshalb werden sie hier mitgenommen.
einstellungen() {
  local ziel="${ABLAGE}/einstellungen"
  mkdir -p "$ziel"

  local gefunden=0
  for quelle in \
    "$HOME/.config/Cursor/User/settings.json" \
    "$HOME/.config/Cursor/User/keybindings.json" \
    "$HOME/.config/Cursor/User/snippets" \
    "$HOME/Library/Application Support/Cursor/User/settings.json" \
    "$HOME/Library/Application Support/Cursor/User/keybindings.json" \
    "$HOME/Library/Application Support/Cursor/User/snippets" \
    "$APPDATA/Cursor/User/settings.json" \
    "$APPDATA/Cursor/User/keybindings.json" \
    "$APPDATA/Cursor/User/snippets"; do
    [ -e "$quelle" ] || continue
    local name
    name="$(echo "$quelle" | sed 's|.*/User/||; s|/|_|g')"
    cp -r "$quelle" "$ziel/$name" 2>/dev/null && gefunden=$((gefunden + 1))
  done

  # Erweiterungen als Liste
  if command -v cursor >/dev/null 2>&1; then
    cursor --list-extensions > "${ziel}/erweiterungen.txt" 2>/dev/null || true
  elif command -v code >/dev/null 2>&1; then
    code --list-extensions > "${ziel}/erweiterungen.txt" 2>/dev/null || true
  fi
  [ -s "${ziel}/erweiterungen.txt" ] && gefunden=$((gefunden + 1))

  return 0
}

# ================================================ 4. ZURÜCK
zurueck() {
  titel "Einstellungen auf diesem Rechner einsetzen"
  local quelle="${ABLAGE}/einstellungen"
  if [ ! -d "$quelle" ]; then
    acht "keine gesicherten Einstellungen vorhanden"
    hin "auf dem anderen Rechner zuerst 'arbeitsstand.sh einstellungen' ausführen"
    return 1
  fi

  local ziel
  if [ -d "$HOME/Library/Application Support/Cursor" ]; then
    ziel="$HOME/Library/Application Support/Cursor/User"
  else
    ziel="$HOME/.config/Cursor/User"
  fi
  mkdir -p "$ziel"

  local n=0
  while IFS= read -r datei; do
    local name
    name="$(basename "$datei")"
    # Snippets-Ordner und flache Dateien unterscheiden
    if [ -d "$datei" ]; then
      cp -r "$datei"/. "$ziel/snippets/" 2>/dev/null && { gut "Snippets eingesetzt"; n=$((n+1)); }
    else
      local zielname
      zielname="$(echo "$name" | tr '_' '/' | sed 's|.*/||')"
      [ "$zielname" = "erweiterungen.txt" ] && continue
      cp "$datei" "$ziel/$zielname" 2>/dev/null && { gut "$zielname eingesetzt"; n=$((n+1)); }
    fi
  done < <(find "$quelle" -maxdepth 1 -mindepth 1 2>/dev/null)

  if [ -s "${quelle}/erweiterungen.txt" ]; then
    local anzahl
    anzahl="$(wc -l < "${quelle}/erweiterungen.txt" | tr -d ' ')"
    hin "$anzahl Erweiterungen zu installieren – Befehl:"
    printf "    cursor --install-extension <name>   (Namen stehen in %s/erweiterungen.txt)\n" "$quelle"
  fi

  [ "$n" -gt 0 ] && printf "\n  Cursor neu starten, damit die Einstellungen greifen.\n\n"
  return 0
}

# ============================================================ Aufruf
case "${1:-zeigen}" in
  merken)        merken ;;
  zeigen)        zeigen ;;
  einstellungen) einstellungen && gut "Einstellungen gesichert in ${ABLAGE}/einstellungen" ;;
  zurueck)       zurueck ;;
  notiz)
    shift
    if [ $# -gt 0 ]; then
      printf '%s\n' "$*" >> "$NACHRICHT"
      gut "Notiz hinzugefügt: $*"
    else
      [ -s "$NACHRICHT" ] && cat "$NACHRICHT" || hin "noch keine Notiz"
    fi
    ;;
  *)
    cat <<'HILFE'
Arbeitsstand sichern und wiederfinden.

  arbeitsstand.sh merken          Stand jetzt sichern (beim Weggehen)
  arbeitsstand.sh zeigen          Stand anzeigen (beim Ankommen)
  arbeitsstand.sh notiz "Text"    Notiz für später hinterlegen
  arbeitsstand.sh einstellungen   Cursor-Einstellungen mitsichern
  arbeitsstand.sh zurueck         Einstellungen auf diesem Rechner einsetzen
HILFE
    ;;
esac
