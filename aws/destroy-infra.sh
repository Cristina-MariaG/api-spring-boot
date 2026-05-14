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

# ─── 2. Vidage du bucket S3 (versioning) ─────────────────────────────────────
echo "==> Vidage du bucket S3 (objets + versions)..."
BUCKET="springboot-api-tfstate"
aws s3 rm s3://$BUCKET --recursive 2>/dev/null || true
VERSIONS=$(aws s3api list-object-versions --bucket $BUCKET 2>/dev/null)
OBJECTS=$(echo "$VERSIONS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
objs = [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in data.get('Versions', [])]
objs += [{'Key': v['Key'], 'VersionId': v['VersionId']} for v in data.get('DeleteMarkers', [])]
if objs:
    print(json.dumps({'Objects': objs}))
" 2>/dev/null)
if [ -n "$OBJECTS" ]; then
    aws s3api delete-objects --bucket $BUCKET --delete "$OBJECTS" > /dev/null
fi
echo "    bucket vidé !"

# ─── 3. Backend destroy (S3) ─────────────────────────────────────────────────
echo "==> Destruction du backend (S3)..."
cd "$TF_DIR/backend-setup"
terraform plan -destroy -out=destroy-backend.plan
terraform show destroy-backend.plan
echo ""
read -p "Confirmer la destruction du backend S3 ? (yes/no) : " CONFIRM4
if [ "$CONFIRM4" != "yes" ]; then
    echo "Backend conservé."
    rm -f destroy-backend.plan
    exit 0
fi
terraform apply destroy-backend.plan
rm -f destroy-backend.plan

# ─── 3. Nettoyage local ───────────────────────────────────────────────────────
echo "==> Nettoyage des fichiers locaux..."
rm -f "$SCRIPT_DIR/springboot-api.pem"
rm -f "$HOME/.ssh/springboot-api.pem"
rm -f "$SCRIPT_DIR/ansible/inventory.ini"

echo ""
echo "✓ Infra détruite et fichiers locaux supprimés."
