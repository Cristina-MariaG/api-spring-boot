#!/bin/bash

CONTAINER_NAME="jenkins"

echo "🔍 Vérification du container Jenkins..."

if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "⚠️  Aucun container '$CONTAINER_NAME' trouvé."
  exit 0
fi

STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME")

if [ "$STATUS" = "running" ]; then
  echo "⏹️  Arrêt de Jenkins..."
  docker stop "$CONTAINER_NAME"
  echo "✅ Jenkins arrêté. Tes données sont conservées dans le volume."
else
  echo "⚠️  Jenkins n'est pas en cours d'exécution (statut : $STATUS)."
fi