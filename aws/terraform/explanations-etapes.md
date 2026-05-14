# Terraform — Explications et étapes

## Qu'est-ce que Terraform ?

Terraform est un outil d'**Infrastructure as Code (IaC)** — au lieu de créer manuellement
des ressources sur AWS via la console, on les décrit dans des fichiers `.tf` et Terraform
les crée, modifie ou détruit automatiquement.

Avantages :
- L'infra est versionnée dans Git comme du code
- Reproductible : même config = même infra, à chaque fois
- Destruction propre : `terraform destroy` supprime tout ce qui a été créé

---

## Structure des fichiers

```
aws/terraform/
├── backend-setup/            ← Étape 1 : crée le bucket S3
│   ├── main.tf
│   └── variables.tf
├── main.tf                   ← Étape 2 : infra principale
├── variables.tf              ← Variables configurables
├── outputs.tf                ← Valeurs affichées après apply
├── terraform.tfvars.example  ← Template à copier
└── explanations-etapes.md    ← Ce fichier
```

---

## Le fichier `terraform.tfstate` — La mémoire de Terraform

C'est le fichier le plus important. Terraform le génère automatiquement après chaque `apply`.
Il contient la photo exacte de tout ce qui existe sur AWS :

```json
{
  "resources": [
    {
      "type": "aws_instance",
      "attributes": {
        "id": "i-0a1b2c3d4e5f",
        "public_ip": "54.123.45.67",
        "instance_type": "t2.micro"
      }
    },
    {
      "type": "tls_private_key",
      "attributes": {
        "private_key_pem": "-----BEGIN RSA PRIVATE KEY-----\nMIIE...",
        "public_key_openssh": "ssh-rsa AAAAB3..."
      }
    }
  ]
}
```

**Ce qu'il contient :**
- IDs de toutes les ressources AWS créées
- IP publique du serveur
- Clé SSH privée en clair
- Toutes les configurations de chaque ressource

**Terraform l'utilise pour :**
- Savoir ce qui existe déjà sur AWS
- Calculer ce qui doit être créé, modifié ou supprimé
- Faire `terraform destroy` proprement

**Sans ce fichier**, Terraform est aveugle — il ne peut plus gérer l'infra qu'il a créée.

---

## Pourquoi stocker le tfstate dans S3

Par défaut le tfstate est local sur ta machine. C'est dangereux :

| Problème | Conséquence |
|---|---|
| Tu supprimes le fichier par accident | Infra orpheline, impossible à détruire |
| Tu travailles en équipe | Chacun a un state différent → conflits |
| La clé SSH est dans le fichier en clair | Risque de sécurité sur le disque local |
| Deux `apply` en même temps | Corruption du state |

### La solution : Backend S3 avec verrou natif

```
terraform apply
    ↓
1. Pose un verrou dans S3 (.tflock)
2. Lit le state depuis S3
3. Crée/modifie les ressources AWS
4. Écrit le nouveau state dans S3
5. Libère le verrou (.tflock supprimé)
```

**Le state n'est jamais stocké sur ta machine** — il vit dans S3, chiffré AES-256.
Le verrou natif S3 (`use_lockfile`) empêche deux `apply` simultanés — plus besoin de DynamoDB depuis Terraform 1.10.
Le versioning S3 permet de récupérer un ancien state en cas de corruption.

**La mise à jour est automatique** — à chaque `terraform apply` réussi, S3 est mis à jour
sans aucune action manuelle.

---

## Ce que fait chaque fichier

### `variables.tf`

Déclare toutes les variables configurables du projet. Aucune valeur sensible n'y est écrite —
il définit juste le type et les valeurs par défaut.

```hcl
variable "my_ip" {
  type = string   # pas de default → obligatoire
}

variable "ssh_port" {
  type    = number
  default = 22    # configurable, pas hardcodé
}
```

Règle de sécurité respectée : aucune IP, aucun secret, aucune valeur sensible en dur.

---

### `main.tf`

Contient toutes les ressources AWS créées. Voici ce que crée chaque bloc :

#### Backend S3
```hcl
backend "s3" {
  bucket       = "springboot-api-tfstate"
  encrypt      = true
  use_lockfile = true
}
```
Connecte Terraform au bucket S3 pour stocker le state à distance.

#### AMI Ubuntu dynamique
```hcl
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical (éditeur officiel Ubuntu)
}
```
Récupère automatiquement la dernière Ubuntu 22.04 officielle selon la région.
Plus besoin de hardcoder un ID d'AMI qui change selon les régions.

#### Paire de clés SSH
```hcl
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096   # 4096 bits, plus sécurisé que 2048
}
```
Génère une clé RSA 4096 bits. La clé publique va sur AWS, la privée est sauvegardée
localement avec les permissions `0600` (lecture uniquement par ton user).

#### Security Group (Firewall)
```hcl
ingress {
  from_port   = var.ssh_port
  cidr_blocks = [var.my_ip]   # uniquement ton IP, pas 0.0.0.0/0
}
```

| Port | Accès | Raison |
|---|---|---|
| SSH | Ton IP uniquement | Seul toi peux te connecter |
| 8081 | Public | L'API doit être accessible |
| 80/443 | Public | HTTP/HTTPS |

Règle de sécurité respectée : SSH restreint à ton IP via `var.my_ip` (pas hardcodée).

#### Instance EC2
```hcl
resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id   # AMI dynamique
  instance_type = var.instance_type        # configurable
  key_name      = aws_key_pair.deployer.key_name
}
```

#### Elastic IP
IP publique fixe attachée à l'instance.
Sans ça, l'IP change à chaque redémarrage — Jenkins ne saurait plus où déployer.

---

### `outputs.tf`

Après `terraform apply`, affiche automatiquement :

```
elastic_ip      = "54.123.45.67"
ssh_connection  = "ssh -i springboot-api.pem -p 22 ubuntu@54.123.45.67"
app_url         = "http://54.123.45.67:8081/swagger-ui/index.html"
```

Zéro recherche manuelle dans la console AWS.

---

### `terraform.tfvars.example`

Commité dans Git avec des placeholders. Le vrai `terraform.tfvars` (avec les vraies valeurs)
est dans le `.gitignore` — jamais dans Git.

Workflow :
```bash
cp terraform.tfvars.example terraform.tfvars
# éditer terraform.tfvars avec les vraies valeurs
```

---

### `backend-setup/`

Dossier séparé car il y a un problème de démarrage (chicken-and-egg) :
- Le bucket S3 doit exister avant de configurer le backend S3
- Mais on ne peut pas créer le bucket avec Terraform si le backend n'existe pas encore

Solution : créer le bucket S3 avec un Terraform séparé, sans backend,
puis utiliser ce bucket comme backend pour l'infra principale.

**`backend-setup/main.tf` crée :**
- Bucket S3 avec accès public bloqué, chiffrement AES-256, versioning activé

---

## Audit de sécurité

| Sévérité | Problème | Statut |
|---|---|---|
| CRITIQUE | Credentials AWS en clair | ✅ Aucun credential dans le code |
| CRITIQUE | IP hardcodée dans le Security Group | ✅ Corrigé → `var.my_ip` |
| ÉLEVÉ | Port SSH hardcodé | ✅ Corrigé → `var.ssh_port` |
| ÉLEVÉ | `terraform apply -auto-approve` | ✅ Absent — confirmation manuelle |
| ÉLEVÉ | Pas de `.gitignore` | ✅ Créé avec tous les fichiers sensibles |
| ÉLEVÉ | tfstate local | ✅ Corrigé → backend S3 chiffré |
| MOYEN | Clé privée dans le tfstate | ✅ Atténué → S3 chiffré AES-256 |

---

## Ordre de déploiement

### Étape 1 — Prérequis

Installer Terraform :
```bash
sudo apt install terraform
```

Configurer AWS CLI :
```bash
aws configure
# AWS Access Key ID : ...
# AWS Secret Access Key : ...
# Default region : eu-west-3
```

### Étape 2 — Créer le bucket S3

```bash
cd aws/terraform/backend-setup
terraform init
terraform apply
```

### Étape 3 — Configurer les variables

```bash
cd aws/terraform
cp terraform.tfvars.example terraform.tfvars
```

Récupérer ton IP publique :
```bash
curl ifconfig.me
```

Remplir `terraform.tfvars` avec tes valeurs réelles.

### Étape 4 — Déployer l'infra

```bash
terraform init    # se connecte au bucket S3
terraform plan    # affiche ce qui va être créé
terraform apply   # crée l'infra
```

### Étape 5 — Récupérer les outputs

Après `apply`, Terraform affiche :
```
elastic_ip      = "54.x.x.x"
ssh_connection  = "ssh -i springboot-api.pem -p 22 ubuntu@54.x.x.x"
app_url         = "http://54.x.x.x:8081/swagger-ui/index.html"
```

Copie l'Elastic IP dans Jenkins comme credential `server-ip-id`.

### Étape 6 — Détruire l'infra (quand tu n'en as plus besoin)

```bash
terraform destroy
```

Supprime toutes les ressources AWS proprement pour éviter des frais inutiles.
