#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/aws/terraform"

# ─── Confirmation ─────────────────────────────────────────────────────────────
read -p "⚠️  Supprimer toute l'infra AWS ? (yes/no) : " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Annulé."
    exit 0
fi

# ─── 1. Terraform destroy (EC2, SG, EIP, key pair) ───────────────────────────
echo "==> Terraform destroy..."
cd "$TF_DIR"
terraform destroy -auto-approve

# ─── 2. Backend destroy (S3 + DynamoDB) ──────────────────────────────────────
echo "==> Destruction du backend (S3 + DynamoDB)..."
cd "$TF_DIR/backend-setup"
terraform destroy -auto-approve

# ─── 3. Nettoyage local ───────────────────────────────────────────────────────
echo "==> Nettoyage des fichiers locaux..."
rm -f "$SCRIPT_DIR/springboot-api.pem"
rm -f "$SCRIPT_DIR/aws/ansible/inventory.ini"

echo ""
echo "✓ Infra détruite et fichiers locaux supprimés."
