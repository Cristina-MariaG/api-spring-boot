#!/bin/bash

CONTAINER_NAME="jenkins"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "❌ Le container '$CONTAINER_NAME' n'est pas démarré."
  exit 1
fi

echo "📋 Logs de Jenkins (Ctrl+C pour quitter)..."
docker logs -f "$CONTAINER_NAME"
