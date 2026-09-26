#!/bin/bash
# =============================================================================
#  audit-espace.sh — Audit de l'espace disque d'un Mac (LECTURE SEULE)
#
#  Ne supprime et ne déplace RIEN. Mesure ce qui prend de la place et écrit un
#  rapport sur le Bureau : rapport-espace-mac-AAAAMMJJ-HHMM.txt
#
#  Usage   : bash audit-espace.sh
#  Durée   : 5 à 15 minutes selon la quantité de fichiers.
#  Conseil : donne d'abord l'« Accès complet au disque » au Terminal (GUIDE.md),
#            sinon Corbeille, Mail, Messages, sauvegardes iPhone… comptent 0.
# =============================================================================

export LC_ALL=C
shopt -s nullglob dotglob

NOW=$(date +%s)
RAPPORT="$HOME/Desktop/rapport-espace-mac-$(date +%Y%m%d-%H%M).txt"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/audit-espace.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

# ----------------------------------------------------------------- utilitaires

AWK_HB='function hb(b){ if(b>=1e9) return sprintf("%.1f Go", b/1e9); if(b>=1e6) return sprintf("%.0f Mo", b/1e6); return sprintf("%.0f Ko", b/1e3) }'
hb() { awk -v b="${1:-0}" "$AWK_HB"' BEGIN{ printf "%s", hb(b) }'; }      # octets -> texte
h()  { awk -v k="${1:-0}" "$AWK_HB"' BEGIN{ printf "%s", hb(k*1024) }'; } # Ko -> texte (Go décimaux, comme le Finder)

# Taille réelle sur disque, en Ko, d'un ou plusieurs chemins (0 si absent)
kb() { [ $# -gt 0 ] || { echo 0; return; }; du -sk "$@" 2>/dev/null | awk '{s+=$1} END{printf "%.0f", s}'; }

short() { case "$1" in "$HOME"*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }
paths0() { printf '%s\0' "$@"; }
count0() { tr -cd '\000' | wc -c | tr -d ' '; }
sum_kb0() { local p t=0 k; while IFS= read -r -d '' p; do k=$(kb "$p"); t=$((t + k)); done; echo "$t"; }
row() { printf '  %10s  %s\n' "$(h "$1")" "$2"; }
section() { printf '\n==================================================================\n  %s\n==================================================================\n' "$1"; }
step() { printf '⏳ %s…\n' "$1" >&2; }
recap_add() { printf '%s\t%s\n' "${1:-0}" "$2" >> "$TMP/recap"; }

# Lit des chemins (séparés par NUL) et affiche les N plus gros au-dessus d'un seuil (Ko)
top_sizes() {
  local n="${1:-15}" min="${2:-0}" p k
  while IFS= read -r -d '' p; do
    [ -e "$p" ] || continue
    k=$(kb "$p")
    [ "$k" -ge "$min" ] && printf '%s\t%s\n' "$k" "$p"
  done | sort -rn | head -n "$n" | while IFS=$'\t' read -r k p; do row "$k" "$(short "$p")"; done
}

# stat portable -> "octets_sur_disque|epoch|AAAA-MM-JJ|chemin" (macOS/BSD, sinon GNU)
if stat -f '%b' / >/dev/null 2>&1; then
  STAT_ARGS=(-f '%b|%m|%Sm|%N' -t '%Y-%m-%d')
else
  STAT_ARGS=(-c '%b|%Y|%y|%n')
fi
stat0() {
  xargs -0 stat "${STAT_ARGS[@]}" 2>/dev/null |
    awk -F'|' 'BEGIN{OFS="|"} { $1 = sprintf("%.0f", $1*512); $3 = substr($3,1,10); print }'
}

# Dossier où macOS range les captures (vide = Bureau par défaut)
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
PRUNE_EXPR=( \( -name '*.photoslibrary' -o -name '*.fcpbundle' -o -name '*.imovielibrary'
                -o -name node_modules -o -name .git -o -name 'A_SUPPRIMER_*' \) -prune -o )

# ------------------------------------------------------------------- sections

disk_overview() {
  step "Disque"
  section "1. DISQUE"
  if command -v diskutil >/dev/null 2>&1; then
    diskutil info / 2>/dev/null | grep -E 'Container Total Space|Container Free Space' | sed 's/^ */  /'
  fi
  local size avail used c x
  size=$(df -k / | awk 'NR==2{print $2}')
  avail=$(df -k / | awk 'NR==2{print $4}')
  used=$((size - avail))
  echo
  echo "  Taille du disque  : $(h "$size")"
  echo "  Utilisé (approx.) : $(h "$used")"
  echo "  Libre             : $(h "$avail")"
  echo
  for c in 300 250; do
    x=$(awk -v u="$used" -v c="$c" 'BEGIN{x=u*1024/1e9-c; if(x<0)x=0; printf "%.0f", x}')
    echo "  → Pour descendre à $c Go UTILISÉS : libérer ~$x Go"
  done
  for c in 250 300; do
    x=$(awk -v a="$avail" -v c="$c" 'BEGIN{x=c-a*1024/1e9; if(x<0)x=0; printf "%.0f", x}')
    echo "  → Pour avoir $c Go LIBRES        : libérer ~$x Go"
  done
  if command -v tmutil >/dev/null 2>&1; then
    echo
    echo "  Instantanés Time Machine locaux : $(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple')"
    echo "  (espace « purgeable » : macOS les efface tout seul quand il manque de place)"
  fi
}

home_overview() {
  step "Dossier perso"
  section "2. TON DOSSIER PERSO — les plus gros dossiers"
  paths0 "$HOME"/* | top_sizes 25 10240
}

screenshots() {
  step "Captures d'écran"
  section "3. CAPTURES D'ÉCRAN & ENREGISTREMENTS D'ÉCRAN"
  local roots=() r custom
  for r in Desktop Documents Downloads Pictures Movies; do [ -d "$HOME/$r" ] && roots+=("$HOME/$r"); done
  custom=$(shot_dir)
  if [ -n "$custom" ]; then
    echo "  Les nouvelles captures sont rangées dans : $(short "$custom")"
    case "$custom/" in
      "$HOME/Desktop/"*|"$HOME/Documents/"*|"$HOME/Downloads/"*|"$HOME/Pictures/"*|"$HOME/Movies/"*) ;;
      *) roots+=("$custom") ;;
    esac
  else
    echo "  Les nouvelles captures sont rangées sur : le Bureau (réglage par défaut)"
  fi
  [ ${#roots[@]} -gt 0 ] || { echo "  (aucun dossier à analyser)"; return; }
  echo

  find "${roots[@]}" "${PRUNE_EXPR[@]}" -type f "${SHOT_EXPR[@]}" -print0 2>/dev/null | stat0 > "$TMP/shots"
  if [ ! -s "$TMP/shots" ]; then echo "  Aucune capture trouvée."; return; fi

  awk -F'|' -v now="$NOW" -v roots="$(printf '%s\n' "${roots[@]}")" "$AWK_HB"'
    BEGIN{ n=split(roots,R,"\n"); for(i=1;i<=n;i++) top[R[i]]=1 }
    { sz=$1; age=(now-$2)/86400; p=$0; sub(/^[^|]*\|[^|]*\|[^|]*\|/,"",p); d=p; sub(/\/[^\/]*$/,"",d)
      c++; s+=sz
      if(age>30){c30++; s30+=sz} if(age>90){c90++; s90+=sz} if(age>365){c365++; s365+=sz}
      if(d in top){cl++; sl+=sz}
      if(tolower(p) ~ /\.(mov|mp4)$/){cv++; sv+=sz}
    }
    END{
      printf "  Total                          : %6d fichiers  %s\n", c, hb(s)
      printf "  ... de plus de 30 jours        : %6d fichiers  %s\n", c30, hb(s30)
      printf "  ... de plus de 90 jours        : %6d fichiers  %s\n", c90, hb(s90)
      printf "  ... de plus d un an            : %6d fichiers  %s\n", c365, hb(s365)
      printf "  ... dont enregistrements video : %6d fichiers  %s\n", cv, hb(sv)
      printf "  En vrac (hors sous-dossiers)   : %6d fichiers  %s\n", cl, hb(sl)
    }' "$TMP/shots"

  recap_add "$(awk -F'|' -v now="$NOW" '(now-$2)/86400>90{s+=$1} END{printf "%.0f", s/1024}' "$TMP/shots")" \
    "Captures / enregistrements d'écran de plus de 90 jours"

  echo
  echo "  Où elles sont (top 10 des dossiers) :"
  awk -F'|' '{p=$0; sub(/^[^|]*\|[^|]*\|[^|]*\|/,"",p); d=p; sub(/\/[^\/]*$/,"",d); s[d]+=$1; c[d]++}
             END{for(d in s) printf "%.0f\t%d\t%s\n", s[d], c[d], d}' "$TMP/shots" |
    sort -rn | head -10 | while IFS=$'\t' read -r b c d; do
      printf '  %10s  %6d fichiers  %s\n' "$(hb "$b")" "$c" "$(short "$d")"
    done
  echo
  echo "  Les 10 plus lourdes :"
  sort -t'|' -k1,1 -rn "$TMP/shots" | head -10 | while IFS='|' read -r b e d p; do
    printf '  %10s  %s  %s\n' "$(hb "$b")" "$d" "$(short "$p")"
  done
}

downloads() {
  step "Téléchargements"
  section "4. TÉLÉCHARGEMENTS"
  local dl="$HOME/Downloads" k
  [ -d "$dl" ] || { echo "  (dossier absent)"; return; }
  echo "  Taille totale                 : $(h "$(kb "$dl")")"
  k=$(find "$dl" -mindepth 1 -maxdepth 1 -mtime +30 -print0 2>/dev/null | sum_kb0)
  echo "  Éléments de plus de 30 jours  : $(h "$k")"
  k=$(find "$dl" -mindepth 1 -maxdepth 1 -mtime +90 -print0 2>/dev/null | sum_kb0)
  echo "  Éléments de plus de 90 jours  : $(h "$k")"
  recap_add "$k" "Téléchargements de plus de 90 jours (à trier)"
  k=$(find "$dl" \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.iso' \) -prune -print0 2>/dev/null | sum_kb0)
  echo "  Installeurs (.dmg .pkg .iso)  : $(h "$k")"
  recap_add "$k" "Installeurs .dmg/.pkg/.iso dans Téléchargements"
  k=$(find "$dl" -iname '*.zip' -print0 2>/dev/null | sum_kb0)
  echo "  Archives .zip                 : $(h "$k")"
  echo
  echo "  Les plus gros éléments (> 50 Mo) :"
  paths0 "$dl"/* | top_sizes 15 51200
}

video() {
  step "Vidéo & montage"
  section "5. VIDÉO & MONTAGE (DaVinci, CapCut, rushes…)"
  echo "  Dossier Vidéos (~/Movies), éléments > 100 Mo :"
  paths0 "$HOME/Movies"/* | top_sizes 15 102400

  echo
  echo "  Caches et médias générés (se régénèrent, à vider depuis le logiciel) :"
  find "$HOME" \( -path "$HOME/Library" -o -name '*.photoslibrary' -o -name node_modules -o -name .git \) -prune -o \
       -type d \( -name CacheClip -o -name ProxyMedia -o -name 'Proxy Media' -o -name OptimizedMedia \
                  -o -name 'Optimized Media' -o -name 'Render Files' -o -name 'Transcoded Media' \) -prune -print0 \
       2>/dev/null > "$TMP/vcache"
  if [ -s "$TMP/vcache" ]; then top_sizes 20 10240 < "$TMP/vcache"; else echo "    (aucun trouvé dans ton dossier perso)"; fi
  recap_add "$(sum_kb0 < "$TMP/vcache")" "Caches vidéo (CacheClip, Proxy, Optimized, Render Files…)"

  local k
  k=$(kb "$HOME/Library/Application Support/Blackmagic Design")
  [ "$k" -gt 0 ] && row "$k" "DaVinci Resolve — bases de projets (NE PAS supprimer à la main)"
  k=$(kb "$HOME/Library/Containers/com.lemon.lvoverseas" "$HOME/Movies/CapCut")
  [ "$k" -gt 0 ] && row "$k" "CapCut (projets + cache)"
  k=$(kb "$HOME/Library/Application Support/Adobe/Common")
  [ "$k" -gt 0 ] && row "$k" "Adobe — Media Cache"

  echo
  step "Recherche des fichiers vidéo"
  find "$HOME" \( -path "$HOME/Library" -o -path "$HOME/.Trash" -o -name '*.photoslibrary' -o -name node_modules -o -name .git \) -prune -o \
       -type f \( -iname '*.mov' -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mxf' -o -iname '*.braw' \
                  -o -iname '*.r3d' -o -iname '*.mkv' -o -iname '*.avi' -o -iname '*.mts' -o -iname '*.insv' \
                  -o -iname '*.360' -o -iname '*.webm' -o -iname '*.lrv' -o -iname '*.lrf' -o -iname '*.thm' \) \
       -print0 2>/dev/null | stat0 > "$TMP/videos"

  awk -F'|' -v now="$NOW" "$AWK_HB"'
    { p=tolower($0); if(p ~ /\.(lrv|lrf|thm)$/){cp++; sp+=$1; next}
      c++; s+=$1; if((now-$2)/86400>180){co++; so+=$1} }
    END{
      printf "  Fichiers vidéo (rushes, exports…)       : %6d fichiers  %s\n", c, hb(s)
      printf "  ... non modifiés depuis plus de 6 mois  : %6d fichiers  %s\n", co, hb(so)
      printf "  Proxies caméra .LRV/.LRF/.THM (inutiles): %6d fichiers  %s\n", cp, hb(sp)
    }' "$TMP/videos"
  recap_add "$(awk -F'|' 'tolower($0) ~ /\.(lrv|lrf|thm)$/{s+=$1} END{printf "%.0f", s/1024}' "$TMP/videos")" \
    "Proxies caméra .LRV/.LRF/.THM (GoPro, DJI, Insta360)"
  recap_add "$(awk -F'|' -v now="$NOW" 'tolower($0) !~ /\.(lrv|lrf|thm)$/ && (now-$2)/86400>180{s+=$1} END{printf "%.0f", s/1024}' "$TMP/videos")" \
    "Vidéos non modifiées depuis 6 mois (→ archiver sur SSD externe)"

  echo
  echo "  Dossiers qui contiennent le plus de vidéo :"
  awk -F'|' '{p=$0; sub(/^[^|]*\|[^|]*\|[^|]*\|/,"",p); d=p; sub(/\/[^\/]*$/,"",d); s[d]+=$1}
             END{for(d in s) printf "%.0f\t%s\n", s[d], d}' "$TMP/videos" |
    sort -rn | head -15 | while IFS=$'\t' read -r b d; do printf '  %10s  %s\n' "$(hb "$b")" "$(short "$d")"; done
}

dev() {
  step "Développement"
  section "6. DÉVELOPPEMENT & IA (web, SaaS, n8n, modèles locaux)"
  find "$HOME" \( -path "$HOME/Library" -o -path "$HOME/.Trash" -o -name '*.photoslibrary' \) -prune -o \
       -type d -name node_modules -prune -print0 2>/dev/null > "$TMP/nm"
  local k n
  n=$(count0 < "$TMP/nm")
  k=$(sum_kb0 < "$TMP/nm")
  echo "  node_modules : $n dossiers, $(h "$k") au total (réinstallables avec npm install)"
  recap_add "$k" "node_modules (tous projets confondus)"
  top_sizes 15 51200 < "$TMP/nm"

  echo
  echo "  Caches, outils et modèles (> 10 Mo) :"
  paths0 "$HOME/.npm" "$HOME/.cache" "$HOME/.pnpm-store" "$HOME/Library/pnpm" "$HOME/Library/Caches/Yarn" \
         "$HOME/Library/Caches/pip" "$HOME/Library/Caches/Homebrew" "$HOME/.bun" "$HOME/.nvm" "$HOME/.cargo" \
         "$HOME/.gradle" "$HOME/.m2" "$HOME/.docker" "$HOME/.colima" "$HOME/.ollama" "$HOME/.lmstudio" "$HOME/.n8n" \
         "$HOME/Library/Developer/Xcode/DerivedData" "$HOME/Library/Developer/Xcode/iOS DeviceSupport" \
         "$HOME/Library/Developer/Xcode/Archives" "$HOME/Library/Developer/CoreSimulator" \
         "$HOME/Library/Containers/com.docker.docker" "$HOME/Library/Group Containers/HUAQ24HBR6.dev.orbstack" |
    top_sizes 30 10240
  recap_add "$(kb "$HOME/.npm" "$HOME/Library/Caches/Yarn" "$HOME/Library/Caches/pip" "$HOME/Library/Caches/Homebrew" \
                  "$HOME/Library/Developer/Xcode/DerivedData")" "Caches dev (npm, Yarn, pip, Homebrew, Xcode)"
  recap_add "$(kb "$HOME/Library/Containers/com.docker.docker")" "Docker Desktop (images, cache de build…)"
  recap_add "$(kb "$HOME/.ollama" "$HOME/.lmstudio")" "Modèles IA locaux (Ollama, LM Studio)"

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo
    echo "  docker system df :"
    docker system df 2>/dev/null | sed 's/^/    /'
  fi
  if [ -f "$HOME/.n8n/database.sqlite" ]; then
    echo
    echo "  Base n8n locale : $(h "$(kb "$HOME/.n8n/database.sqlite")") (grossit avec l'historique des exécutions, voir GUIDE.md)"
  fi
}

library() {
  step "Bibliothèque (~/Library)"
  section "7. BIBLIOTHÈQUE (~/Library) — caches, données d'apps, sauvegardes"
  local lib="$HOME/Library" k
  k=$(kb "$lib/Caches")
  echo "  Caches d'applications : $(h "$k") au total — les plus gros (> 100 Mo) :"
  recap_add "$k" "Caches d'applications (~/Library/Caches)"
  paths0 "$lib/Caches"/* | top_sizes 10 102400
  echo
  echo "  Données d'applications (Application Support, > 200 Mo) :"
  paths0 "$lib/Application Support"/* | top_sizes 15 204800
  echo
  echo "  Conteneurs d'apps (Containers, > 200 Mo) :"
  paths0 "$lib/Containers"/* | top_sizes 10 204800
  echo
  echo "  Group Containers (WhatsApp, Telegram, Office…, > 200 Mo) :"
  paths0 "$lib/Group Containers"/* | top_sizes 10 204800

  echo
  echo "  Postes connus :"
  known() { local label="$1" k; shift; k=$(kb "$@"); [ "$k" -gt 0 ] && row "$k" "$label"; }
  known "Sauvegardes iPhone / iPad"            "$lib/Application Support/MobileSync/Backup"
  known "Pièces jointes Messages"              "$lib/Messages/Attachments"
  known "Mail"                                 "$lib/Mail"
  known "iCloud Drive (copie locale)"          "$lib/Mobile Documents"
  known "Google Drive / Dropbox / OneDrive"    "$lib/CloudStorage"
  known "Photos (bibliothèque)"                "$HOME/Pictures"/*.photoslibrary
  known "Musique"                              "$HOME/Music"
  known "Corbeille"                            "$HOME/.Trash"
  known "Boucles GarageBand / Logic (système)" "/Library/Application Support/GarageBand" "/Library/Audio/Apple Loops"
  known "Dossier partagé (/Users/Shared)"      "/Users/Shared"
  recap_add "$(kb "$lib/Application Support/MobileSync/Backup")" "Sauvegardes iPhone / iPad"
  recap_add "$(kb "$lib/Messages/Attachments")" "Pièces jointes Messages"
  recap_add "$(kb "$HOME/.Trash")" "Corbeille"
  recap_add "$(kb /Library/Application\ Support/GarageBand /Library/Audio/Apple\ Loops)" "Boucles GarageBand / Logic"
  for k in "$HOME"/Desktop/A_SUPPRIMER_*; do recap_add "$(kb "$k")" "Dossier $(short "$k") (déjà trié, à mettre à la corbeille)"; done
}

apps() {
  step "Applications"
  section "8. APPLICATIONS (taille + dernière ouverture)"
  echo "  ⚠️  = pas ouverte depuis plus de 6 mois    ?  = date inconnue (jamais ouverte, ou Spotlight désactivé)"
  echo
  local a k lu ts days flag when
  paths0 /Applications/*.app /Applications/*/*.app "$HOME/Applications"/*.app | while IFS= read -r -d '' a; do
    [ -e "$a" ] || continue
    k=$(kb "$a"); days="?"
    if command -v mdls >/dev/null 2>&1; then
      lu=$(mdls -name kMDItemLastUsedDate -raw "$a" 2>/dev/null)
      if [ -n "$lu" ] && [ "$lu" != "(null)" ]; then
        ts=$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$lu" +%s 2>/dev/null) && days=$(( (NOW - ts) / 86400 ))
      fi
    fi
    printf '%s\t%s\t%s\n' "$k" "$days" "$a"
  done | sort -rn > "$TMP/apps"

  while IFS=$'\t' read -r k days a; do
    if [ "$days" = "?" ]; then flag="?  "; when="inconnue"
    elif [ "$days" -gt 180 ]; then flag="⚠️ "; when="il y a $days j"
    else flag="   "; when="il y a $days j"; fi
    printf '  %10s  %s%-16s  %s\n' "$(h "$k")" "$flag" "$when" "$(basename "$a" .app)"
  done < "$TMP/apps"
  recap_add "$(awk -F'\t' '$2!="?" && $2>180{s+=$1} END{printf "%.0f", s}' "$TMP/apps")" \
    "Applications pas ouvertes depuis 6 mois"
}

bigfiles() {
  step "Gros fichiers"
  section "9. LES 30 PLUS GROS FICHIERS (> 1 Go) DE TON DOSSIER PERSO"
  echo "  (taille réelle sur le disque : un fichier iCloud/Drive resté dans le cloud n'apparaît pas)"
  find "$HOME" \( -name '*.photoslibrary' -o -path "$HOME/.Trash" \) -prune -o -type f -size +1G -print0 2>/dev/null |
    stat0 | awk -F'|' '$1>=5e8' | sort -t'|' -k1,1 -rn | head -30 |
    while IFS='|' read -r b e d p; do printf '  %10s  modifié le %s  %s\n' "$(hb "$b")" "$d" "$(short "$p")"; done
}

recap() {
  section "RÉCAP — où sont les gains possibles (du plus gros au plus petit)"
  echo "  (certaines lignes se recoupent : ne les additionne pas bêtement)"
  echo
  sort -rn "$TMP/recap" | awk -F'\t' '$1>=10240' | while IFS=$'\t' read -r k label; do row "$k" "$label"; done
  echo
  echo "  Étape suivante : envoie ce rapport à Claude pour savoir exactement quoi supprimer,"
  echo "  ou lance le nettoyage guidé : bash nettoyage-mac.sh"
}

main() {
  echo "RAPPORT D'ESPACE DISQUE — $(date '+%d/%m/%Y %H:%M') — macOS $(sw_vers -productVersion 2>/dev/null || uname -s)"
  if [ "$FDA" = non ]; then
    echo "⚠️  Terminal sans « Accès complet au disque » : certains dossiers sont sous-estimés."
  fi
  : > "$TMP/recap"
  disk_overview
  home_overview
  screenshots
  downloads
  video
  dev
  library
  apps
  bigfiles
  recap
}

# --------------------------------------------------------------------- départ

FDA=oui
if [ "$(uname)" = Darwin ] && ! ls "$HOME/.Trash" >/dev/null 2>&1; then
  FDA=non
  echo "⚠️  Le Terminal n'a pas l'« Accès complet au disque »."
  echo "   → Corbeille, Mail, Messages, sauvegardes iPhone seront comptés à 0,"
  echo "     et macOS risque d'afficher des fenêtres d'autorisation (tu peux refuser)."
  echo "   → Pour l'activer : voir GUIDE.md, étape 2."
  printf '   Continuer quand même ? (o/N) '
  read -r rep
  case "$rep" in o|O|oui|OUI|y|Y) ;; *) exit 0 ;; esac
fi

echo "Audit en cours (lecture seule, rien n'est supprimé). Compte 5 à 15 minutes."
main | tee "$RAPPORT"
echo
echo "✅ Rapport enregistré : $(short "$RAPPORT")"
