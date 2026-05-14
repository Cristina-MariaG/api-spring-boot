#!/bin/bash

VOLUME_NAME="jenkins-data"
CONTAINER_NAME="jenkins"
IMAGE="jenkins/jenkins:lts"

echo "🔍 Vérification que Docker est démarré..."
if ! docker info > /dev/null 2>&1; then
  echo "⚠️  Docker ne répond pas. Tentative de démarrage de Docker Desktop..."

  DOCKER_DESKTOP="/mnt/c/Program Files/Docker/Docker/Docker Desktop.exe"
  if [ -f "$DOCKER_DESKTOP" ]; then
    "$DOCKER_DESKTOP" &
    echo "⏳ Attente du démarrage de Docker Desktop (30s max)..."
    for i in $(seq 1 30); do
      sleep 2
      if docker info > /dev/null 2>&1; then
        echo "✅ Docker est prêt."
        break
      fi
      if [ "$i" -eq 30 ]; then
        echo "❌ Docker Desktop ne répond pas après 60s."
        echo "   Lance Docker Desktop manuellement puis relance ce script."
        exit 1
      fi
    done
  else
    echo "❌ Docker Desktop introuvable."
    echo "   Lance Docker Desktop manuellement puis relance ce script."
    exit 1
  fi
else
  echo "✅ Docker est déjà démarré."
fi

echo ""
echo "🔍 Vérification du volume Jenkins..."
if ! docker volume inspect "$VOLUME_NAME" > /dev/null 2>&1; then
  echo "📦 Volume '$VOLUME_NAME' introuvable, création en cours..."
  docker volume create "$VOLUME_NAME"
  echo "✅ Volume créé."
else
  echo "✅ Volume '$VOLUME_NAME' déjà existant."
fi

echo ""
echo "🔍 Vérification du container Jenkins..."

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER_NAME")

  if [ "$STATUS" = "running" ]; then
    echo "✅ Jenkins tourne déjà sur http://localhost:8080"
    exit 0
  else
    echo "▶️  Container existant mais arrêté, redémarrage..."
    docker start "$CONTAINER_NAME"
    echo "✅ Jenkins redémarré sur http://localhost:8080"
    exit 0
  fi
fi

echo "🚀 Démarrage de Jenkins..."
docker run -d \
  --name "$CONTAINER_NAME" \
  -p 8080:8080 \
  -p 50000:50000 \
  -v "$VOLUME_NAME":/var/jenkins_home \
  "$IMAGE"

echo ""
echo "⏳ Attente du démarrage de Jenkins..."
sleep 5

echo ""
echo "✅ Jenkins lancé sur http://localhost:8080"
echo ""
echo "🔑 Mot de passe initial :"
docker exec "$CONTAINER_NAME" cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null || echo "   (déjà configuré, pas besoin de mot de passe initial)"