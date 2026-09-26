# Libérer de l'espace sur ton Mac — objectif 250–300 Go

## 0. D'abord, soyons réalistes

- **Les captures d'écran ne te feront pas gagner 100 Go.** Une capture pèse 0,3 à 3 Mo : même 3 000 captures ne font que 1 à 9 Go. Les **enregistrements d'écran** (`.mov`) sont différents : une seule vidéo peut peser plusieurs Go. Le rapport les compte à part.
- **Les vrais gros postes sont presque toujours ailleurs** : rushes et exports vidéo, cache DaVinci, sauvegardes iPhone, Docker (si ton n8n tourne dessus), `node_modules`, modèles IA locaux (Ollama), pièces jointes Messages/WhatsApp.
- **« Revenir à 250–300 Go », c'est utilisé ou libre ?** Le rapport calcule les deux. Pour du montage DaVinci, garde **au moins 15–20 % de disque libre**, sinon le Mac et le cache ralentissent.
- **Si tes rushes sont le problème, supprimer ne suffira pas longtemps.** Une journée de tournage 4K, c'est facilement 30 à 100 Go. La solution durable pour un créateur nomade : un **SSD externe** (1–2 To) sur lequel tu montes directement. Et **une 2ᵉ copie** (cloud ou 2ᵉ disque) des rushes importants : un SSD seul, ça se perd ou ça tombe en panne.

---

## 1. Récupérer les scripts sur ton Mac

**Option A (simple)** : sur GitHub, ouvre le repo `billy`, choisis la branche `claude/epic-cerf-tb6quo`, puis **Code → Download ZIP**. Dézippe-le dans Téléchargements.

**Option B (git)** :
```bash
cd ~/Downloads
git clone -b claude/epic-cerf-tb6quo https://github.com/billy59700/billy.git
```

Ensuite, dans le **Terminal** (Cmd+Espace → « Terminal ») :
```bash
cd ~/Downloads/billy*/mac-nettoyage
```

## 2. Donner l'« Accès complet au disque » au Terminal (temporaire)

Sans ça, macOS cache la Corbeille, Mail, Messages et les sauvegardes iPhone : l'audit les compterait à 0.

1. **Réglages Système → Confidentialité et sécurité → Accès complet au disque**
2. Active **Terminal** (bouton `+` s'il n'est pas dans la liste)
3. **Quitte le Terminal (Cmd+Q) et rouvre-le**

Tu pourras retirer cet accès une fois le ménage fini.

## 3. L'audit (ne supprime RIEN)

```bash
bash audit-espace.sh
```

- Il faut compter 5 à 15 minutes.
- Le rapport est enregistré sur ton **Bureau** (`rapport-espace-mac-….txt`).
- **Envoie-le-moi** (copier-coller) et je te dirai précisément quoi supprimer, dans quel ordre, et combien tu vas gagner. Il contient des noms de fichiers : efface les lignes que tu ne veux pas partager.

Contenu du rapport : disque, plus gros dossiers, captures par âge, Téléchargements, vidéo/DaVinci, dev/n8n/IA, `~/Library`, **applications triées par taille avec leur dernière ouverture**, les 30 plus gros fichiers, puis un récap des gains possibles.

## 4. Le nettoyage guidé (demande confirmation à chaque étape)

```bash
bash nettoyage-mac.sh        # captures de plus de 90 jours
bash nettoyage-mac.sh 30     # … ou de plus de 30 jours
```

| Étape | Ce qui se passe | Réversible ? |
|---|---|---|
| 1. Captures & enregistrements d'écran « en vrac » plus vieux que N jours | **Déplacés** dans `Bureau/A_SUPPRIMER_<date>/Captures` | ✅ Oui |
| 2. Installeurs `.dmg/.pkg/.iso` de plus de 30 jours (Téléchargements) | **Déplacés** dans `A_SUPPRIMER_<date>/Installeurs` | ✅ Oui |
| 3. Caches npm / Yarn / pnpm / Homebrew / pip / Xcode | Supprimés | Se régénèrent |
| 4. `node_modules` des projets **inactifs depuis 90 jours** | Supprimés | `npm install` |
| 5. Docker : cache de build + images inutilisées | Supprimés | Re-téléchargées si besoin |
| 6. Caches d'apps > 200 Mo (`~/Library/Caches`, sauf Apple) | Vidés | Se régénèrent |
| 7. Ouvre `A_SUPPRIMER_…` → tu vérifies → corbeille → vider | Définitif **seulement** après ta 2ᵉ confirmation | — |

Le script ne touche **jamais** à :
- tes documents et tes photos ;
- les captures rangées dans des sous-dossiers (souvent des captures de projets clients) ;
- tes rushes et tes projets DaVinci ;
- tes applications ;
- les conteneurs et volumes Docker, donc tes données n8n ;
- les dossiers cachés comme `.n8n` et `.nvm`.

## 5. Les gros postes à faire à la main (par gain probable)

### Vidéo — souvent le plus gros levier
- **Cache DaVinci** : dans Resolve, **Lecture (Playback) → Supprimer le cache de rendu (Delete Render Cache) → Tout (All)**. Autre méthode : ferme Resolve, puis supprime les dossiers `CacheClip`, `OptimizedMedia` et `ProxyMedia` repérés par l'audit. Ils se recréent, et les proxies se régénèrent depuis les originaux.
- **Déplacer le cache sur le SSD** : Paramètres du projet → Master Settings → Working Folders → emplacement du cache. Fais la même chose dans Préférences → Media Storage.
- **Fichiers `.LRV` / `.LRF` / `.THM`** (GoPro, DJI, Insta360) : ce sont des proxies de la caméra, inutiles sur Mac. Tu peux tous les supprimer.
- **Exports** : garde l'export final publié, supprime les `v1`, `v2` et `final_final2`.
- **Rushes de vidéos déjà publiées** : archive-les sur SSD ou dans le cloud, puis supprime-les du Mac. Le rapport liste les dossiers vidéo pas modifiés depuis 6 mois.

### Sauvegardes iPhone
Finder → clique sur ton iPhone → **Gérer les sauvegardes…** Tu peux aussi passer par **Réglages Système → Général → Stockage → Fichiers iOS (ⓘ)**. Une vieille sauvegarde fait souvent 20 à 100 Go. Si ton iPhone est sauvegardé sur iCloud, les sauvegardes locales ne servent à rien.

### Docker / n8n
- Si n8n tourne en local, sa base grossit avec l'historique des exécutions. Ajoute ces variables d'environnement (docker-compose ou `.env`) :
  `EXECUTIONS_DATA_PRUNE=true`, `EXECUTIONS_DATA_MAX_AGE=168` (7 jours, en heures) et `DB_SQLITE_VACUUM_ON_STARTUP=true` (SQLite).
- Docker Desktop → Settings → Resources : réduis la limite de disque si elle est bien plus grande que ce que tu utilises.

### Messages, WhatsApp, Telegram
- **Réglages Système → Général → Stockage → Messages (ⓘ)** pour supprimer les grosses pièces jointes. Dans l'app Messages → Réglages : **Conserver les messages : 1 an**.
- Telegram → Paramètres → Données et stockage → Utilisation du stockage → **Vider le cache**.

### iCloud, Photos, Corbeille
- **Réglages Système → [ton nom] → iCloud** → active **Optimiser le stockage du Mac** (iCloud Drive et Photos). Les fichiers restent dans le cloud, seule la copie locale part.
- Finder → Réglages → Avancés → **Supprimer les éléments de la corbeille après 30 jours**.

### « Données système » énormes ?
Redémarre le Mac : ça vide le swap et les fichiers temporaires. Les instantanés Time Machine locaux sont « purgeables » : macOS les efface tout seul quand il manque de place.

## 6. Les applications inutiles

Dans la section 8 du rapport, les apps sont triées par taille. ⚠️ = pas ouverte depuis plus de 6 mois.

**Ma règle** : pas ouverte depuis 6 mois **et** remplaçable (version web, autre app que tu utilises déjà) → dehors.

Candidats fréquents dans ton cas :
- **GarageBand** avec ses boucles : 2 à 10 Go.
- **iMovie** : tu montes sur DaVinci.
- **Pages / Numbers / Keynote** si tu ne t'en sers pas.
- Des apps d'essai oubliées.
- Plusieurs navigateurs.
- D'anciennes versions d'outils (ex. deux versions de DaVinci ou d'Adobe).

Comment supprimer proprement :
- Utilise **AppCleaner** (gratuit, freemacsoft.net). Glisse l'app dedans : il supprime aussi ses fichiers cachés dans `~/Library`. Un simple glisser vers la corbeille laisse souvent des centaines de Mo derrière.
- Autre option : **Réglages Système → Général → Stockage → Applications**.
- Avant de supprimer une app **payante**, note sa clé de licence.

## 7. Pour ne plus jamais y revenir

- **Captures dans le presse-papiers** : **Cmd+Ctrl+Maj+4** copie la capture sans créer de fichier. C'est parfait pour les captures qu'on colle une fois dans un chat ou un doc.
- **Un dossier dédié aux captures** : **Cmd+Maj+5 → Options → Enregistrer dans → Autre emplacement…** (ex. `Images/Captures`). Ton Bureau reste propre, et tu lances `bash nettoyage-mac.sh 30` une fois par mois.
- **Workflow vidéo** : rushes et cache DaVinci sur le SSD, et après publication tu archives et tu vides.
- **Une fois par mois** : `bash audit-espace.sh` pour voir ce qui a regrossi.

---

*Ces scripts ont été testés sur une simulation de Mac, pas sur ton Mac réel. L'audit est en lecture seule, donc sans risque. Le nettoyage demande confirmation avant chaque action. Si une étape affiche une erreur, envoie-la-moi.*
