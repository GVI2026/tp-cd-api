# Exercice Bonus — Rollback automatique

## Objectif

Si le smoke test du job `deploy` échoue (l'application ne répond pas ou retourne un code d'erreur), la pipeline doit automatiquement redéployer la **version précédente** depuis Verdaccio, sans intervention humaine.

## Compétences testées

- Conditions GitHub Actions (`if: failure()` sur un step)
- Logique de résilience : ne jamais laisser le serveur dans un état inconnu

## Prérequis

Pour que le rollback ait du sens, **deux versions doivent être disponibles dans Verdaccio** : une version de référence déjà déployée, et une nouvelle version qui va échouer.

Suivez le workflow décrit dans [docs/git-et-runners.md](docs/git-et-runners.md) :
1. Pipeline complète initiale → v0.0.1 déployée sur ssh-target
2. Release locale (`npx commit-and-tag-version`) → v0.1.0 dans `package.json`
3. `act -j publish` → v0.1.0 dans Verdaccio

Vous avez maintenant v0.0.1 et v0.1.0 dans Verdaccio, v0.0.1 tournant sur pm2.

## Ce que vous devez réaliser

La difficulté principale du rollback est de **connaître la version précédente** au moment où le smoke test échoue.

### Approche recommandée : sauvegarder la version courante avant le déploiement

Avant d'installer la nouvelle version sur le serveur, demandez à pm2 quelle version tourne actuellement et sauvegardez-la dans un fichier. Si le smoke test échoue, ce fichier sert de référence pour le rollback.

**Dans le script du step de déploiement**, ajoutez en tête :

```bash
# Sauvegarder la version actuellement déployée (pour rollback éventuel)
CURRENT=$(pm2 show tp-cd-api 2>/dev/null \
  | grep -oP '(?<=tp-cd-api@)\d+\.\d+\.\d+' || echo "")
echo "$CURRENT" > ~/app/.previous-version
```

**Step de rollback conditionnel** à ajouter après le smoke test :

```yaml
- name: Rollback si le smoke test échoue
  if: failure()
  uses: appleboy/ssh-action@v0.1.7
  with:
    host: localhost
    port: 2222
    username: deployer
    key: ${{ secrets.SSH_PRIVATE_KEY }}
    script: |
      PREVIOUS=$(cat ~/app/.previous-version 2>/dev/null || echo "")
      if [ -z "$PREVIOUS" ]; then
        echo "Aucune version précédente connue, rollback impossible."
        exit 1
      fi
      echo "Rollback vers tp-cd-api@${PREVIOUS}"
      npm install --prefix ~/app tp-cd-api@${PREVIOUS} --ignore-scripts
      pm2 restart tp-cd-api
```

## Limitations connues de cette approche

### 1. La version précédente doit exister dans Verdaccio

Le rollback réinstalle la version depuis Verdaccio. Si Verdaccio ne contient que la nouvelle version (ex: première publication), le rollback échouera.

**Solution :** S'assurer que la version de référence a bien été publiée. Dans un vrai système, un registre privé conserve toutes les versions indéfiniment.

### 2. `git describe` ne fonctionne pas dans les runners act

L'approche naive `git describe --abbrev=0 --tags HEAD^` pour récupérer la version précédente **ne fonctionne pas ici**. Pourquoi ?

Le runner est éphémère et clone le dépôt tel qu'il est dans votre DevContainer. Les tags créés par le job `release` restent dans le runner qui les a créés — ils ne sont pas dans votre dépôt local. Donc `git tag` et `git describe` ne verront que les tags que vous avez créés localement.

→ C'est pourquoi l'approche "lire la version depuis pm2 avant le déploiement" est plus fiable.

### 3. pm2 peut ne pas connaître la version

Si le processus pm2 a été lancé directement depuis un chemin de fichier (pas via `npm install`), `pm2 show` peut ne pas exposer la version du package. Dans ce cas, `CURRENT` sera vide et le rollback sera impossible.

**Solution de contournement :** écrire explicitement la version dans un fichier lors de chaque déploiement réussi.

## Pour tester le rollback

1. Avoir v0.0.1 et v0.1.0 dans Verdaccio, v0.0.1 déployée sur pm2
2. Modifier temporairement le smoke test pour qu'il échoue (mauvais port) :
   ```yaml
   - name: Smoke test
     run: curl -f http://localhost:9999/health  # port invalide → échec garanti
   ```
3. Lancer `act -j deploy` — le step de déploiement réussit (v0.1.0 installée), le smoke test échoue, le rollback se déclenche
4. Vérifier que le serveur a bien re-déployé v0.0.1 :
   ```bash
   ssh -p 2222 deployer@localhost "pm2 list"
   curl http://localhost:3001/health
   ```
5. Remettre le smoke test correct et vérifier que le rollback ne se déclenche plus
