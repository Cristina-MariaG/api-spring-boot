#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"

# ─── Confirmation ─────────────────────────────────────────────────────────────
read -p "⚠️  Supprimer toute l'infra AWS ? (yes/no) : " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Annulé."
    exit 0
fi

# ─── 1. Terraform destroy (EC2, SG, EIP, key pair) ───────────────────────────
echo "==> Terraform plan destroy..."
cd "$TF_DIR"
terraform plan -destroy -out=destroy.plan
echo ""
terraform show destroy.plan
echo ""
read -p "Confirmer la destruction des ressources ci-dessus ? (yes/no) : " CONFIRM2
if [ "$CONFIRM2" != "yes" ]; then
    echo "Annulé."
    rm -f destroy.plan
    exit 0
fi
terraform apply destroy.plan
rm -f destroy.plan

# ─── 2. Backend destroy (S3 + DynamoDB) ──────────────────────────────────────
echo "==> Destruction du backend (S3 + DynamoDB)..."
cd "$TF_DIR/backend-setup"
terraform plan -destroy -out=destroy-backend.plan
terraform show destroy-backend.plan
echo ""
read -p "Confirmer la destruction du backend S3/DynamoDB ? (yes/no) : " CONFIRM3
if [ "$CONFIRM3" != "yes" ]; then
    echo "Backend conservé."
    rm -f destroy-backend.plan
    exit 0
fi
terraform apply destroy-backend.plan
rm -f destroy-backend.plan

# ─── 3. Nettoyage local ───────────────────────────────────────────────────────
echo "==> Nettoyage des fichiers locaux..."
rm -f "$SCRIPT_DIR/../springboot-api.pem"
rm -f "$HOME/springboot-api.pem"
rm -f "$SCRIPT_DIR/ansible/inventory.ini"

echo ""
echo "✓ Infra détruite et fichiers locaux supprimés."
