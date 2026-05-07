# Exercice Bonus — Rollback automatique

## Objectif

Si le smoke test du job `deploy` échoue (l'application ne répond pas ou retourne un code d'erreur), la pipeline doit automatiquement redéployer la **version précédente** depuis Verdaccio, sans intervention humaine.

## Compétences testées

- Conditions GitHub Actions (`if: failure()` sur un step)
- Récupérer le tag Git précédent depuis l'historique
- Logique de résilience : ne jamais laisser le serveur dans un état inconnu

## Ce que vous devez réaliser

Dans votre job `deploy`, après le step de smoke test, ajouter un step de rollback conditionnel :

```yaml
- name: Rollback si le smoke test échoue
  if: failure()
  run: |
    PREVIOUS_VERSION=$(git describe --abbrev=0 --tags HEAD^ | sed 's/^v//')
    echo "Rollback vers la version $PREVIOUS_VERSION"
    echo "${{ secrets.SSH_PRIVATE_KEY }}" > /tmp/deploy_key
    chmod 600 /tmp/deploy_key
    ssh -i /tmp/deploy_key -p 2222 -o StrictHostKeyChecking=no deployer@localhost \
      "npm install -g tp-cd-api@${PREVIOUS_VERSION} --registry http://verdaccio:4873 \
       && pm2 restart tp-cd-api"
    rm /tmp/deploy_key
```

## Pour tester le rollback

1. S'assurer d'avoir au moins deux versions publiées dans Verdaccio (`v1.0.0` et `v1.1.0`)
2. Modifier le smoke test pour qu'il échoue volontairement (utiliser un mauvais port)
3. Vérifier que le rollback se déclenche automatiquement
4. Remettre le smoke test correct et vérifier que le rollback ne se déclenche plus

## Contrainte

Ce bonus n'utilise que des primitives GitHub Actions déjà vues dans le cours (conditions `if:`, variables, commandes shell). Pas d'outil externe requis.
