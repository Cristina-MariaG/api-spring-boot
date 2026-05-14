#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
ANSIBLE_DIR="$SCRIPT_DIR/ansible"
PEM_FILE="$HOME/.ssh/springboot-api.pem"

# ─── Config Jenkins ───────────────────────────────────────────────────────────
if [ ! -f "$SCRIPT_DIR/.env.infra" ]; then
    echo "Erreur : aws/.env.infra introuvable. Copie aws/.env.infra.example et remplis les valeurs."
    exit 1
fi
source "$SCRIPT_DIR/.env.infra"

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

# ─── 3. Copie et sécurisation de la clé PEM ─────────────────────────────────
cp "$SCRIPT_DIR/../springboot-api.pem" "$PEM_FILE"
chmod 600 "$PEM_FILE"

# ─── 4. Récupération de l'IP ─────────────────────────────────────────────────
echo "==> Récupération de l'Elastic IP..."
EC2_IP=$(terraform output -raw elastic_ip)
echo "    IP: $EC2_IP"

# ─── 4. Création ou mise à jour du credential Jenkins (server-ip-id) ─────────
echo "==> Synchronisation du credential Jenkins (server-ip-id)..."
CRUMB=$(curl -s "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" \
    --user "$JENKINS_USER:$JENKINS_TOKEN")

CREDENTIAL_XML="<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>server-ip-id</id>
  <description>EC2 Server IP</description>
  <secret>$EC2_IP</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>"

# Vérifie si le credential existe déjà
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --user "$JENKINS_USER:$JENKINS_TOKEN" \
    "$JENKINS_URL/credentials/store/system/domain/_/credential/server-ip-id/")

if [ "$STATUS" = "200" ]; then
    # Mise à jour
    curl -s -X POST "$JENKINS_URL/credentials/store/system/domain/_/credential/server-ip-id/config.xml" \
        --user "$JENKINS_USER:$JENKINS_TOKEN" \
        -H "$CRUMB" \
        -H "Content-Type: application/xml" \
        -d "$CREDENTIAL_XML"
    echo "    credential mis à jour !"
else
    # Création
    curl -s -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
        --user "$JENKINS_USER:$JENKINS_TOKEN" \
        -H "$CRUMB" \
        -H "Content-Type: application/xml" \
        -d "$CREDENTIAL_XML"
    echo "    credential créé !"
fi

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

echo "==> Enregistrement de la clé SSH du serveur dans known_hosts..."
ssh-keyscan -H "$EC2_IP" >> ~/.ssh/known_hosts

# ─── 7. Ansible ──────────────────────────────────────────────────────────────
echo "==> Lancement du playbook Ansible..."
cd "$SCRIPT_DIR"
ansible-playbook -i "$ANSIBLE_DIR/inventory.ini" "$ANSIBLE_DIR/install.yml"

# ─── 8. Résumé ───────────────────────────────────────────────────────────────
echo ""
echo "✓ Infra prête !"
echo "  SSH    : ssh -i ~/.ssh/springboot-api.pem ubuntu@$EC2_IP"
echo "  App    : http://$EC2_IP:8081/swagger-ui/index.html"
