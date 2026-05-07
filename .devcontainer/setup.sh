#!/bin/bash
set -ex

WORKSPACE="/workspaces/tp-cd-api"
SSH_KEY_PATH="$HOME/.ssh/tp_cd_key"

echo "==> Installation des dépendances npm..."
npm ci

echo "==> Création de la base de données SQLite et initialisation des données de démonstration..."
DATABASE_URL="./dev.db" npx ts-node db/seed.ts

echo "==> Génération de la paire de clés SSH pour le déploiement..."
mkdir -p "$HOME/.ssh"
rm -f "$SSH_KEY_PATH" "$SSH_KEY_PATH.pub"
ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "tp-cd-deploy"

echo "==> Injection de la clé publique dans le conteneur SSH-target..."
cp "$SSH_KEY_PATH.pub" "$WORKSPACE/docker/ssh-target/authorized_keys"

echo "==> Création du fichier de secrets pour act..."
cat > "$WORKSPACE/.secrets" <<EOF
SSH_PRIVATE_KEY=$(cat "$SSH_KEY_PATH")
EOF
chmod 600 "$WORKSPACE/.secrets"

echo "==> Configuration SSH locale (évite les prompts de vérification de l'hôte)..."
cat >> "$HOME/.ssh/config" <<EOF

Host localhost
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
  IdentityFile $SSH_KEY_PATH
EOF
chmod 600 "$HOME/.ssh/config"

echo "==> Démarrage des conteneurs Docker (Verdaccio + SSH-target)..."
docker compose -f "$WORKSPACE/docker-compose.yml" up -d --build

echo "==> Attente du démarrage de Verdaccio..."
until curl -sf http://localhost:4873/-/ping > /dev/null 2>&1; do
  echo "   ... Verdaccio pas encore prêt, attente 2s..."
  sleep 2
done
echo "   Verdaccio opérationnel ✓"

echo "==> Attente du démarrage du SSH-target..."
for i in $(seq 1 15); do
  if ssh -i "$SSH_KEY_PATH" -p 2222 -o StrictHostKeyChecking=no -o ConnectTimeout=3 deployer@localhost "echo ok" > /dev/null 2>&1; then
    echo "   SSH-target opérationnel ✓"
    break
  fi
  echo "   ... SSH-target pas encore prêt ($i/15), attente 2s..."
  sleep 2
done

echo "==> Installation de act (exécution locale des GitHub Actions)..."
sudo ln -sf /workspaces/tp-cd-api/bin/act /usr/local/bin/act

echo "==> Pré-téléchargement de l'image Docker pour act..."
docker pull catthehacker/ubuntu:act-24.04

echo "==> Installation de Trivy (scan de sécurité)..."
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin

echo ""
echo "✅ Environnement prêt !"
echo "   - Application      : npm run start:dev  →  http://localhost:3000"
echo "   - Swagger          : http://localhost:3000/api"
echo "   - Tests            : npm test"
echo "   - CI locale        : act"
echo "   - Verdaccio        : http://localhost:4873"
echo "   - SSH target       : ssh -i ~/.ssh/tp_cd_key -p 2222 deployer@localhost"
echo "   - App déployée     : http://localhost:3001 (après le TP)"
