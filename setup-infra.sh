#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/aws/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/aws/ansible"
PEM_FILE="$SCRIPT_DIR/springboot-api.pem"

# ─── Config Jenkins ───────────────────────────────────────────────────────────
if [ ! -f "$SCRIPT_DIR/aws/.env.infra" ]; then
    echo "Erreur : aws/.env.infra introuvable. Copie aws/.env.infra.example et remplis les valeurs."
    exit 1
fi
source "$SCRIPT_DIR/aws/.env.infra"

# ─── 1. Backend setup (S3 + DynamoDB) ───────────────────────────────────────
echo "==> Backend setup (S3 + DynamoDB)..."
cd "$TF_DIR/backend-setup"
terraform init
terraform apply -auto-approve

# ─── 2. Terraform ────────────────────────────────────────────────────────────
echo "==> Terraform init..."
cd "$TF_DIR"
terraform init

echo "==> Terraform apply..."
terraform apply -auto-approve

# ─── 3. Récupération de l'IP ─────────────────────────────────────────────────
echo "==> Récupération de l'Elastic IP..."
EC2_IP=$(terraform output -raw elastic_ip)
echo "    IP: $EC2_IP"

# ─── 4. Mise à jour du credential Jenkins ────────────────────────────────────
echo "==> Mise à jour du credential Jenkins (server-ip-id)..."
CRUMB=$(curl -s "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" \
    --user "$JENKINS_USER:$JENKINS_TOKEN")

curl -s -X POST "$JENKINS_URL/credentials/store/system/domain/_/credential/server-ip-id/updateSubmit" \
    --user "$JENKINS_USER:$JENKINS_TOKEN" \
    -H "$CRUMB" \
    --data-urlencode "json={
        \"\": \"0\",
        \"credentials\": {
            \"scope\": \"GLOBAL\",
            \"id\": \"server-ip-id\",
            \"secret\": \"$EC2_IP\",
            \"\$class\": \"org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl\"
        }
    }" > /dev/null
echo "    credential mis à jour !"

# ─── 5. Génération de l'inventory Ansible ────────────────────────────────────
echo "==> Génération de ansible/inventory.ini..."
cat > "$ANSIBLE_DIR/inventory.ini" <<EOF
[ec2]
$EC2_IP ansible_user=ubuntu ansible_ssh_private_key_file=$PEM_FILE
EOF

# ─── 6. Attente que le serveur soit prêt ─────────────────────────────────────
echo "==> Attente que le serveur SSH soit disponible..."
until ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$PEM_FILE" ubuntu@"$EC2_IP" exit 2>/dev/null; do
    echo "    pas encore prêt, on réessaie dans 10s..."
    sleep 10
done
echo "    serveur prêt !"

# ─── 7. Ansible ──────────────────────────────────────────────────────────────
echo "==> Lancement du playbook Ansible..."
cd "$SCRIPT_DIR"
ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/install.yml"

# ─── 8. Résumé ───────────────────────────────────────────────────────────────
echo ""
echo "✓ Infra prête !"
echo "  SSH    : ssh -i springboot-api.pem ubuntu@$EC2_IP"
echo "  App    : http://$EC2_IP:8081/swagger-ui/index.html"
