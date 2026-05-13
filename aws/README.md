# AWS Infrastructure

Ce dossier contient tout ce qui est nécessaire pour provisionner et configurer l'infrastructure AWS du projet.

## Prérequis

- [Terraform](https://developer.hashicorp.com/terraform/install) installé localement
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) installé localement
- AWS CLI configuré (`aws configure`) avec un compte ayant les droits EC2, S3, DynamoDB, IAM
- Fichier `aws/.env.infra` rempli (copier depuis `aws/.env.infra.example`)
- Fichier `aws/terraform/terraform.tfvars` rempli (copier depuis `aws/terraform/terraform.tfvars.example`)

---

## Scripts

### `setup-infra.sh` — Construire l'infra from scratch

Lance toute la chaîne dans l'ordre :

```bash
./aws/setup-infra.sh
```

**Ce qu'il fait, étape par étape :**

| Étape | Action |
|-------|--------|
| 1 | `terraform apply` sur `backend-setup` → crée le bucket S3 et la table DynamoDB |
| 2 | `terraform apply` sur `main` → crée l'EC2, l'Elastic IP, le Security Group et la clé PEM |
| 3 | Copie la clé PEM dans `~/springboot-api.pem` et applique `chmod 600` |
| 4 | Récupère l'Elastic IP via `terraform output` |
| 5 | Crée ou met à jour le credential `server-ip-id` dans Jenkins via l'API REST |
| 6 | Génère `aws/ansible/inventory.ini` avec l'IP et le chemin vers le `.pem` |
| 7 | Attend que le port SSH soit disponible sur l'instance (boucle toutes les 10s) |
| 8 | Lance `ansible-playbook install.yml` pour configurer Docker sur le serveur |

> Le backend-setup est idempotent : si le bucket et la table DynamoDB existent déjà, Terraform ne fait rien.

---

### `destroy-infra.sh` — Détruire toute l'infra

```bash
./aws/destroy-infra.sh
```

Demande une confirmation (`yes`) avant de procéder.

**Ce qu'il fait :**

| Étape | Action |
|-------|--------|
| 1 | `terraform destroy` sur `main` → supprime EC2, EIP, Security Group, key pair |
| 2 | `terraform destroy` sur `backend-setup` → supprime le bucket S3 et la table DynamoDB |
| 3 | Supprime `springboot-api.pem` localement |
| 4 | Supprime `aws/ansible/inventory.ini` |

> ⚠️ Détruire le bucket S3 supprime le Terraform state. Cette opération est irréversible.

---

## Ce que Terraform construit

### `backend-setup/` — Infrastructure Terraform

Crée les ressources nécessaires au stockage sécurisé du state Terraform :

- **S3 Bucket** `springboot-api-tfstate`
  - Versioning activé (récupération d'un ancien state en cas de corruption)
  - Chiffrement AES-256
  - Accès public totalement bloqué

- **Table DynamoDB** `springboot-api-tf-lock`
  - Verrou d'état : empêche deux `terraform apply` simultanés

### `main.tf` — Infrastructure applicative

| Ressource | Détail |
|-----------|--------|
| **EC2 Instance** | Ubuntu 22.04 LTS (AMI dynamique Canonical), type `t2.micro` |
| **Security Group** | SSH:22 (ton IP uniquement via `my_ip`), :8081 (app, ouvert) |
| **Elastic IP** | IP publique fixe attachée à l'instance |
| **Key Pair RSA 4096** | Générée par Terraform, sauvegardée en tant que `springboot-api.pem` à la racine |

La clé PEM est générée automatiquement. Le script `setup-infra.sh` la copie dans `~/springboot-api.pem` (répertoire Linux home) et applique `chmod 600` — nécessaire car `chmod` ne fonctionne pas sur `/mnt/c/` (NTFS via WSL).

> Le port SSH (22) est restreint à ton IP (`my_ip` dans `terraform.tfvars`). Les ports 80 et 443 ne sont pas ouverts — seul le port applicatif 8081 est accessible publiquement.

---

## Ce qu'Ansible configure

Le playbook `ansible/install.yml` se connecte en SSH à l'EC2 et effectue :

1. **Ajout du repo officiel Docker** (GPG key + apt source)
2. **Installation de Docker CE** (`docker-ce`, `docker-ce-cli`, `containerd.io`)
3. **Installation du Compose plugin** (`docker-compose-plugin`) — requis pour `docker compose` v2
4. **Démarrage de Docker** au boot via systemd
5. **Ajout de l'user `ubuntu`** au groupe `docker` — pour lancer Docker sans `sudo`

Une fois Ansible terminé, le serveur est prêt à recevoir les déploiements Jenkins (`docker compose up`).
