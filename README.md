# Spring Boot API — CI/CD & Infrastructure DevOps

Ce projet est conçu pour mettre en place une chaîne DevOps complète autour d'une API REST Spring Boot. L'objectif n'est pas seulement de faire tourner l'application, mais de couvrir chaque brique de l'infrastructure :

- **Jenkins** — pipeline CI/CD déclenché automatiquement à chaque push GitHub
- **Terraform** — provisionnement automatique d'une instance EC2 sur AWS (Elastic IP, Security Group, clé PEM, bucket S3 + table DynamoDB pour le state)
- **Ansible** — configuration du serveur distant (installation de Docker CE, démarrage automatique, ajout de l'utilisateur au groupe docker)
- **Docker / Docker Compose** — conteneurisation de l'application et de la base PostgreSQL
- **Spring Boot 3.2 / Java 21** — API REST avec gestion des utilisateurs et contacts, sécurisée par clé API

---

## Architecture

```
Push GitHub
    ↓
Jenkins (local via Docker)
    ↓
 ┌──────────────────────────┐
 │  1. Checkout             │
 │  2. Build (Maven → .jar) │
 │  3. Transfer (SCP)       │
 │  4. Deploy (SSH)         │
 │  5. Health check         │
 └──────────────────────────┘
    ↓
EC2 AWS (Ubuntu 22.04)
    ↓
Docker Compose (app + PostgreSQL)
```

---

## Lancer Jenkins en local

Un dossier `jenkins_local/` contient des scripts prêts à l'emploi pour démarrer Jenkins dans Docker sans aucune installation manuelle :

```bash
./jenkins_local/jenkins_start.sh   # démarre Jenkins
./jenkins_local/jenkins_stop.sh    # arrête Jenkins
./jenkins_local/jenkins_logs.sh    # affiche les logs
```

Jenkins sera accessible sur `http://localhost:8080`.

---

## Provisionner l'infrastructure AWS

Tout est dans le dossier `aws/`. Un README dédié (`aws/README.md`) documente chaque étape en détail : ce que Terraform crée, ce qu'Ansible configure, et comment les scripts fonctionnent.

```bash
./aws/setup-infra.sh     # crée toute l'infra from scratch
./aws/destroy-infra.sh   # détruit toute l'infra (avec confirmation)
```

`setup-infra.sh` enchaîne automatiquement : Terraform → copie de la clé PEM → synchronisation de l'IP dans Jenkins → génération de l'inventaire Ansible → attente SSH → playbook Ansible.

---

## Credentials Jenkins requis

| ID Jenkins | Type | Contenu |
|---|---|---|
| `github-token-id` | Secret text | Token GitHub |
| `server-ip-id` | Secret text | IP EC2 (mis à jour automatiquement par `setup-infra.sh`) |
| `aws-ec2-pem` | SSH private key | Clé PEM générée par Terraform |
| `env-file-id` | Secret file | Fichier `.env` de l'application |

---

## Variables d'environnement

Copier `.env.example` en `.env` et remplir les valeurs :

```bash
cp .env.example .env
```

Variables requises : `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `SPRING_DATASOURCE_URL`, `API_KEY`.

---

## Documentation

- `aws/README.md` — infrastructure Terraform + Ansible, scripts setup/destroy, détail de chaque ressource créée
- `JENKINS_SETUP.md` — configuration initiale de Jenkins (plugins, credentials, webhook GitHub)
