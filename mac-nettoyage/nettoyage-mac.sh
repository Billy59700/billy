#!/bin/bash
# =============================================================================
#  nettoyage-mac.sh — Nettoyage GUIDÉ et prudent d'un Mac
#
#  Chaque étape affiche ce qu'elle va faire et la place en jeu, puis demande
#  confirmation (o/N). Si tu appuies juste sur Entrée, rien n'est fait.
#
#  • Captures d'écran et installeurs : DÉPLACÉS (pas supprimés) dans un dossier
#    « A_SUPPRIMER_<date> » sur le Bureau. Tu vérifies, puis ça part à la corbeille.
#  • Caches (npm, Homebrew, Xcode, Docker, ~/Library/Caches) et node_modules de
#    projets inactifs : SUPPRIMÉS, car ils se régénèrent tout seuls.
#  • Ne touche JAMAIS : documents, photos, rushes, projets DaVinci, applications,
#    conteneurs et volumes Docker (donc tes données n8n).
#
#  Usage :  bash nettoyage-mac.sh [jours]
#           jours = âge minimum des captures à ranger (défaut : 90)
# =============================================================================

export LC_ALL=C
shopt -s nullglob dotglob

JOURS="${1:-90}"
case "$JOURS" in ''|*[!0-9]*) echo "Usage : bash nettoyage-mac.sh [jours]   (ex. : bash nettoyage-mac.sh 60)"; exit 1 ;; esac
JOURS_INSTALLEURS=30     # .dmg/.pkg/.iso de Téléchargements plus vieux que ça
JOURS_PROJETS=90         # node_modules : projets sans aucune modification depuis N jours
SEUIL_CACHE_KO=204800    # ~/Library/Caches : on ne propose que les dossiers > 200 Mo

[ "$(uname)" = Darwin ] || { echo "Ce script est prévu pour macOS."; exit 1; }

STAGE="$HOME/Desktop/A_SUPPRIMER_$(date +%Y-%m-%d)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/nettoyage.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# ----------------------------------------------------------------- utilitaires

h() { awk -v k="${1:-0}" 'BEGIN{b=k*1024; if(b>=1e9) printf "%.1f Go", b/1e9; else if(b>=1e6) printf "%.0f Mo", b/1e6; else printf "%.0f Ko", b/1e3}'; }
kb() { [ $# -gt 0 ] || { echo 0; return; }; du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%.0f", s}'; }
short() { case "$1" in "$HOME"*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
paths0() { printf '%s\0' "$@"; }
count0() { tr -cd '\000' | wc -c | tr -d ' '; }
sum_kb0() { local p t=0 k; while IFS= read -r -d '' p; do k=$(kb "$p"); t=$((t + k)); done; echo "$t"; }
free_kb() { df -k / | awk 'NR==2{print $4}'; }
titre() { printf '\n──────────────────────────────────────────────────────────────\n %s\n──────────────────────────────────────────────────────────────\n' "$1"; }

ask() {
  local r
  printf '\n👉 %s (o/N) ' "$1"
  read -r r
  case "$r" in o|O|oui|OUI|y|Y) return 0 ;; *) echo "  ⏭  ignoré"; return 1 ;; esac
}

# Affiche quelques exemples d'une liste NUL
exemples() { tr '\000' '\n' < "$1" | head -n "${2:-5}" | while IFS= read -r p; do echo "    • $(short "$p")"; done; }

# Déplace les chemins (NUL, sur stdin) vers $1, sans jamais écraser un fichier
move0() {
  local dest="$1" p ok=0 ko=0
  mkdir -p "$dest" || return 1
  while IFS= read -r -d '' p; do
    [ -e "$p" ] || continue
    if mv -n "$p" "$dest/" 2>/dev/null && [ ! -e "$p" ]; then ok=$((ok + 1)); else ko=$((ko + 1)); fi
  done
  echo "  ✅ $ok élément(s) déplacé(s) dans $(short "$dest")"
  [ "$ko" -gt 0 ] && echo "  ⚠️  $ko laissé(s) en place (même nom déjà présent, ou droits insuffisants)"
}

# Vide le contenu d'un dossier situé dans le dossier perso (garde le dossier lui-même)
vider() {
  local d="$1"
  case "$d" in "$HOME"/?*) ;; *) return 1 ;; esac
  [ -d "$d" ] || return 0
  find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + 2>/dev/null
}

# propose "libellé" taille_Ko commande…   (silencieux sous 50 Mo)
FAIT=0
propose() {
  local label="$1" k="${2:-0}"; shift 2
  [ "$k" -ge 51200 ] || return 0
  FAIT=1
  echo "  • $label : $(h "$k")"
  if ask "Nettoyer « $label » ?"; then "$@" >/dev/null 2>&1; echo "  ✅ fait"; fi
}

shot_dir() {
  local loc
  loc=$(defaults read com.apple.screencapture location 2>/dev/null) || return 0
  case "$loc" in "~"*) loc="$HOME${loc#\~}" ;; esac
  loc="${loc%/}"
  [ -d "$loc" ] && printf '%s' "$loc"
}

SHOT_EXPR=( \( -iname 'Capture d*cran*' -o -iname 'Screenshot*' -o -iname 'Screen Shot*'
               -o -iname 'Enregistrement de l*cran*' -o -iname 'Screen Recording*' -o -iname 'CleanShot*'
               -o -name 'スクリーンショット*' -o -name '画面収録*' \) )

# --------------------------------------------------------------------- étapes

etape_captures() {
  titre "1/7 — Captures et enregistrements d'écran de plus de $JOURS jours"
  local roots=() r custom dup n k
  for r in Desktop Documents Downloads Pictures Movies; do [ -d "$HOME/$r" ] && roots+=("$HOME/$r"); done
  custom=$(shot_dir)
  if [ -n "$custom" ]; then
    dup=0; for r in "${roots[@]}"; do [ "$r" = "$custom" ] && dup=1; done
    [ "$dup" -eq 0 ] && roots+=("$custom")
  fi
  [ ${#roots[@]} -gt 0 ] || { echo "  Aucun dossier à analyser."; return; }
  echo "  Regardé (fichiers en vrac, PAS les sous-dossiers que tu as organisés) :"
  for r in "${roots[@]}"; do echo "    $(short "$r")"; done

  find "${roots[@]}" -maxdepth 1 -type f "${SHOT_EXPR[@]}" -mtime +"$JOURS" -print0 2>/dev/null > "$TMP/shots"
  n=$(count0 < "$TMP/shots")
  [ "$n" -gt 0 ] || { echo "  Rien à ranger ✅"; return; }
  k=$(sum_kb0 < "$TMP/shots")
  echo
  echo "  $n fichier(s) — $(h "$k"). Exemples :"
  exemples "$TMP/shots"
  ask "Les déplacer dans $(short "$STAGE")/Captures ?" && move0 "$STAGE/Captures" < "$TMP/shots"
}

etape_installeurs() {
  titre "2/7 — Installeurs (.dmg .pkg .iso) de plus de $JOURS_INSTALLEURS jours dans Téléchargements"
  local n k
  [ -d "$HOME/Downloads" ] || { echo "  Pas de dossier Téléchargements."; return; }
  find "$HOME/Downloads" -maxdepth 1 \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.iso' \) \
       -mtime +"$JOURS_INSTALLEURS" -print0 2>/dev/null > "$TMP/inst"
  n=$(count0 < "$TMP/inst")
  [ "$n" -gt 0 ] || { echo "  Rien à ranger ✅"; return; }
  k=$(sum_kb0 < "$TMP/inst")
  echo "  $n installeur(s) — $(h "$k") (l'app est déjà installée, l'installeur ne sert plus) :"
  exemples "$TMP/inst" 10
  ask "Les déplacer dans $(short "$STAGE")/Installeurs ?" && move0 "$STAGE/Installeurs" < "$TMP/inst"
}

etape_dev() {
  titre "3/7 — Caches de développement (se régénèrent tout seuls)"
  FAIT=0
  local d
  if command -v npm >/dev/null 2>&1; then
    propose "Cache npm" "$(kb "$HOME/.npm/_cacache")" npm cache clean --force
  fi
  if command -v yarn >/dev/null 2>&1; then
    d=$(yarn cache dir 2>/dev/null)
    [ -n "$d" ] && propose "Cache Yarn" "$(kb "$d")" yarn cache clean
  fi
  if command -v pnpm >/dev/null 2>&1; then
    d=$(pnpm store path 2>/dev/null)
    [ -n "$d" ] && propose "Store pnpm (paquets orphelins)" "$(kb "$d")" pnpm store prune
  fi
  if command -v brew >/dev/null 2>&1; then
    propose "Cache Homebrew" "$(kb "$(brew --cache 2>/dev/null)")" brew cleanup --prune=all
  fi
  propose "Cache pip" "$(kb "$HOME/Library/Caches/pip")" vider "$HOME/Library/Caches/pip"
  propose "Xcode DerivedData" "$(kb "$HOME/Library/Developer/Xcode/DerivedData")" vider "$HOME/Library/Developer/Xcode/DerivedData"
  [ "$FAIT" -eq 1 ] || echo "  Rien de significatif ✅"
}

etape_node_modules() {
  titre "4/7 — node_modules des projets inactifs depuis $JOURS_PROJETS jours"
  echo "  (un simple « npm install » les recrée le jour où tu reprends le projet)"
  local nm proj recent n k
  # On ignore ~/Library et tous les dossiers cachés (.n8n, .nvm… : jamais touchés)
  find "$HOME" \( -path "$HOME/Library" -o -path "$HOME/Applications" -o -name '.*' -o -name '*.photoslibrary' \) -prune -o \
       -type d -name node_modules -prune -print0 2>/dev/null > "$TMP/nm_all"
  while IFS= read -r -d '' nm; do
    proj=$(dirname "$nm")
    recent=$(find "$proj" \( -name node_modules -o -name .git \) -prune -o -type f -mtime -"$JOURS_PROJETS" -print 2>/dev/null | head -n 1)
    [ -z "$recent" ] && printf '%s\0' "$nm"
  done < "$TMP/nm_all" > "$TMP/nm_old"
  n=$(count0 < "$TMP/nm_old")
  [ "$n" -gt 0 ] || { echo "  Rien à supprimer ✅"; return; }
  while IFS= read -r -d '' nm; do printf '%s\t%s\n' "$(kb "$nm")" "$nm"; done < "$TMP/nm_old" | sort -rn > "$TMP/nm_list"
  k=$(awk -F'\t' '{s+=$1} END{printf "%.0f", s}' "$TMP/nm_list")
  echo
  echo "  $n dossier(s) — $(h "$k") :"
  head -n 15 "$TMP/nm_list" | while IFS=$'\t' read -r s p; do printf '    %10s  %s\n' "$(h "$s")" "$(short "$p")"; done
  [ "$n" -gt 15 ] && echo "    … et $((n - 15)) autre(s)"
  if ask "Supprimer ces node_modules ?"; then
    while IFS= read -r -d '' nm; do [ "$(basename "$nm")" = node_modules ] && rm -rf "$nm"; done < "$TMP/nm_old"
    echo "  ✅ fait"
  fi
}

etape_docker() {
  titre "5/7 — Docker (images et cache de build inutilisés)"
  if ! command -v docker >/dev/null 2>&1; then echo "  Docker n'est pas installé ✅"; return; fi
  if ! docker info >/dev/null 2>&1; then
    echo "  Docker est installé mais pas lancé (disque Docker : $(h "$(kb "$HOME/Library/Containers/com.docker.docker")"))."
    echo "  → Ouvre Docker Desktop puis relance le script si tu veux faire cette étape."
    return
  fi
  docker system df 2>/dev/null | sed 's/^/    /'
  echo
  echo "  Proposé   : cache de build + images qui ne servent à aucun conteneur."
  echo "  NON touché : les conteneurs (même arrêtés) et les volumes → tes données n8n restent intactes."
  if ask "Nettoyer Docker ?"; then
    docker builder prune -af >/dev/null 2>&1
    docker image prune -af >/dev/null 2>&1
    echo "  ✅ fait (l'espace peut mettre quelques minutes à revenir côté macOS)"
  fi
}

etape_caches() {
  titre "6/7 — Caches d'applications (~/Library/Caches, dossiers > $(h "$SEUIL_CACHE_KO"))"
  echo "  Conseil : quitte d'abord tes applis (navigateurs, DaVinci, Slack, Spotify…)."
  echo "  Les caches internes d'Apple (com.apple.*) ne sont pas touchés."
  local p k name
  paths0 "$HOME/Library/Caches"/* | while IFS= read -r -d '' p; do
    name=$(basename "$p")
    case "$name" in com.apple.*|CloudKit|Homebrew|Yarn|pip) continue ;; esac
    [ -d "$p" ] || continue
    k=$(kb "$p")
    [ "$k" -ge "$SEUIL_CACHE_KO" ] && printf '%s\t%s\n' "$k" "$p"
  done | sort -rn > "$TMP/caches"
  [ -s "$TMP/caches" ] || { echo "  Rien de significatif ✅"; return; }
  k=$(awk -F'\t' '{s+=$1} END{printf "%.0f", s}' "$TMP/caches")
  echo
  while IFS=$'\t' read -r s p; do printf '    %10s  %s\n' "$(h "$s")" "$(basename "$p")"; done < "$TMP/caches"
  echo "    ──────────"
  printf '    %10s  au total\n' "$(h "$k")"
  if ask "Vider ces caches ?"; then
    while IFS=$'\t' read -r s p; do vider "$p"; done < "$TMP/caches"
    echo "  ✅ fait"
  fi
}

etape_final() {
  titre "7/7 — Vérification puis corbeille"
  if [ -d "$STAGE" ]; then
    echo "  Le dossier $(short "$STAGE") ($(h "$(kb "$STAGE")")) va s'ouvrir dans le Finder."
    echo "  Jette un œil (barre espace = aperçu rapide) et sors ce que tu veux garder."
    echo "  (si macOS demande d'autoriser le Terminal à contrôler le Finder : accepte)"
    open "$STAGE" 2>/dev/null
    if ask "C'est bon ? Mettre ce dossier à la corbeille ?"; then
      if osascript -e 'on run argv' -e 'tell application "Finder" to delete (POSIX file (item 1 of argv) as alias)' -e 'end run' "$STAGE" >/dev/null 2>&1; then
        echo "  ✅ dossier mis à la corbeille"
      else
        echo "  ⚠️  Impossible via le script : glisse le dossier dans la corbeille à la main."
      fi
    fi
  fi
  echo
  echo "  ⚠️  Vider la corbeille est DÉFINITIF (tout ce qu'elle contient, pas seulement ce script)."
  if ask "Vider la corbeille maintenant ?"; then
    if osascript -e 'tell application "Finder" to empty trash' >/dev/null 2>&1; then
      echo "  ✅ corbeille vidée"
    else
      echo "  ⚠️  Impossible via le script : clic droit sur la corbeille → « Vider la corbeille »."
    fi
  fi
}

# --------------------------------------------------------------------- départ

AVANT=$(free_kb)
echo "Nettoyage guidé — espace libre actuel : $(h "$AVANT")"
echo "Rien n'est fait sans ton « o ». Entrée = passer l'étape."

etape_captures
etape_installeurs
etape_dev
etape_node_modules
etape_docker
etape_caches
etape_final

APRES=$(free_kb)
titre "Terminé"
echo "  Espace libre avant : $(h "$AVANT")"
echo "  Espace libre après : $(h "$APRES")   (gain : $(h $((APRES > AVANT ? APRES - AVANT : 0))))"
echo
echo "  Pas encore fait (à la main, voir GUIDE.md étape 5) : cache DaVinci, rushes,"
echo "  sauvegardes iPhone, applications inutiles, Messages/WhatsApp, Photos."
