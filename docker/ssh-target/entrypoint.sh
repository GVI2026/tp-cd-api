#!/bin/bash
set -e

# Corriger les permissions sur authorized_keys (monté en volume)
if [ -f /home/deployer/.ssh/authorized_keys ]; then
  chmod 600 /home/deployer/.ssh/authorized_keys
  chown deployer:deployer /home/deployer/.ssh/authorized_keys
fi

exec /usr/sbin/sshd -D -e
