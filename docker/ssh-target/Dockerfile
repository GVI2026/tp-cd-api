FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Installer Node.js 24
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Installer pm2 globalement
RUN npm install -g pm2

# Créer l'utilisateur deployer
RUN useradd -m -s /bin/bash deployer

# Configurer le répertoire SSH pour deployer
RUN mkdir -p /home/deployer/.ssh \
    && chmod 700 /home/deployer/.ssh \
    && chown deployer:deployer /home/deployer/.ssh

# Configurer le serveur SSH
RUN mkdir /run/sshd
RUN echo 'PubkeyAuthentication yes' >> /etc/ssh/sshd_config \
    && echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config \
    && echo 'PermitRootLogin no' >> /etc/ssh/sshd_config \
    && echo 'AllowUsers deployer' >> /etc/ssh/sshd_config \
    && ssh-keygen -A

# Répertoire de déploiement
RUN mkdir -p /home/deployer/app \
    && chown deployer:deployer /home/deployer/app

# Fichier .npmrc pour pointer vers Verdaccio (sur le réseau Docker Compose)
RUN echo 'registry=http://verdaccio:4873' > /home/deployer/.npmrc \
    && chown deployer:deployer /home/deployer/.npmrc

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22 3000

ENTRYPOINT ["/entrypoint.sh"]
