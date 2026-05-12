# Jenkins — Guide de mise en place complet

## Prérequis

- Docker installé sur ta machine
- Un compte GitHub avec un repo contenant un `Jenkinsfile`
- Un serveur EC2 AWS (pour le déploiement)

---

## Étape 1 — Démarrer Jenkins en local via Docker

Lance Jenkins dans un container Docker :

```bash
docker run -d \
  --name jenkins \
  -p 8080:8080 \
  -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  jenkins/jenkins:lts
```

| Option | Rôle |
|---|---|
| `-p 8080:8080` | Interface web Jenkins |
| `-p 50000:50000` | Communication avec les agents Jenkins |
| `-v jenkins_home:/var/jenkins_home` | Persistance des données Jenkins |

Accède à Jenkins :
```
http://localhost:8080
```

---

## Étape 2 — Déverrouiller Jenkins

Récupère le mot de passe initial généré au démarrage :

```bash
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

Colle ce mot de passe dans la page Jenkins qui s'affiche.

---

## Étape 3 — Installer les plugins

Sur la page "Customize Jenkins", choisis :

```
Install suggested plugins
```

Attends la fin de l'installation, puis crée ton compte administrateur.

---

## Étape 4 — Installer les plugins supplémentaires

Certains plugins sont nécessaires pour ce projet :

```
Manage Jenkins → Plugins → Available plugins
```

Recherche et installe :

| Plugin | Rôle |
|---|---|
| `GitHub Integration Plugin` | Webhook GitHub → Jenkins |
| `SSH Agent Plugin` | Connexion SSH au serveur EC2 |
| `Credentials Binding Plugin` | Injection sécurisée des secrets |
| `Workspace Cleanup Plugin` | Nettoyage du workspace (`cleanWs()`) |

Redémarre Jenkins après installation :
```bash
docker restart jenkins
```

---

## Étape 5 — Installer Maven dans Jenkins

Maven doit être installé dans le container Jenkins pour pouvoir builder le projet.

```
Manage Jenkins → Tools → Maven installations → Add Maven
```

- **Name** : `Maven`
- **Install automatically** : coché
- **Version** : `3.9.6` (ou la dernière stable)

Clique **Save**.

---

## Étape 6 — Configurer les Credentials

Tous les secrets sont stockés dans Jenkins, jamais dans le code.

```
Manage Jenkins → Credentials → System → Global credentials → Add Credentials
```

### Credential 1 — Token GitHub

| Champ | Valeur |
|---|---|
| Kind | `Secret text` |
| Secret | ton token GitHub (`ghp_xxxxxxxxxxxx`) |
| ID | `github-token-id` |
| Description | `GitHub Token` |

> Génère le token sur GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic) → scope `repo`

---

### Credential 2 — IP du serveur EC2

| Champ | Valeur |
|---|---|
| Kind | `Secret text` |
| Secret | l'IP publique de ton EC2 (ex: `54.123.45.67`) |
| ID | `server-ip-id` |
| Description | `Server IP` |

---

### Credential 3 — Clé PEM AWS

| Champ | Valeur |
|---|---|
| Kind | `SSH Username with private key` |
| ID | `aws-ec2-pem` |
| Username | `ubuntu` |
| Private Key | contenu de ton fichier `.pem` |
| Description | `AWS EC2 PEM Key` |

> Le fichier `.pem` est téléchargé depuis AWS lors de la création de l'instance EC2.

---

## Étape 7 — Configurer le webhook GitHub

Pour que Jenkins se déclenche automatiquement à chaque push :

### Côté GitHub

```
Repo GitHub → Settings → Webhooks → Add webhook
```

| Champ | Valeur |
|---|---|
| Payload URL | `http://<ton-ip-publique>:8080/github-webhook/` |
| Content type | `application/json` |
| Events | `Just the push event` |

> Si Jenkins tourne en local, utilise [ngrok](https://ngrok.com) pour exposer le port 8080 :
> ```bash
> ngrok http 8080
> ```
> Puis utilise l'URL ngrok comme Payload URL.

### Côté Jenkins

```
Manage Jenkins → System → GitHub → Add GitHub Server
```

- **API URL** : `https://api.github.com`
- **Credentials** : sélectionne `github-token-id`

---

## Étape 8 — Créer le Pipeline

```
Dashboard → New Item
```

- **Nom** : `springboot-api`
- **Type** : `Pipeline`
- Clique **OK**

### Configuration du pipeline

**Section "Build Triggers" :**
- Coche `GitHub hook trigger for GITScm polling`

**Section "Pipeline" :**

| Champ | Valeur |
|---|---|
| Definition | `Pipeline script from SCM` |
| SCM | `Git` |
| Repository URL | `https://github.com/<ton-user>/<ton-repo>.git` |
| Credentials | `github-token-id` |
| Branch | `*/main` |
| Script Path | `Jenkinsfile` |

Clique **Save**.

---

## Étape 9 — Premier build

Lance un build manuel pour vérifier que tout fonctionne :

```
Dashboard → springboot-api → Build Now
```

Clique sur le build (`#1`) → **Console Output** pour suivre les logs en temps réel.

---

## Étape 10 — Vérifier le déploiement

Si tout s'est bien passé, l'application est accessible sur le serveur EC2 :

```
http://<SERVER_IP>:8081/swagger-ui/index.html
```

Jenkins vérifie automatiquement cette URL à la fin du pipeline et échoue si elle ne répond pas HTTP 200.

---

## Résumé des credentials Jenkins requis

| ID | Type | Valeur |
|---|---|---|
| `github-token-id` | Secret text | Token GitHub |
| `server-ip-id` | Secret text | IP publique EC2 |
| `aws-ec2-pem` | SSH private key | Contenu du fichier `.pem` |

---

## Commandes Docker utiles

```bash
# Démarrer Jenkins
docker start jenkins

# Arrêter Jenkins
docker stop jenkins

# Voir les logs Jenkins
docker logs -f jenkins

# Accéder au container Jenkins
docker exec -it jenkins bash

# Mot de passe initial
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

---

## Flux complet

```
Push GitHub
    ↓
Webhook → Jenkins
    ↓
Checkout (clone repo avec token GitHub)
    ↓
Build (./mvnw clean package → .jar)
    ↓
Prepare Deployment (génère deploy.sh)
    ↓
Transfer Files (SCP → EC2 via clé PEM)
    ↓
Deploy to Staging (SSH → docker compose restart)
    ↓
Health Check (curl Swagger → HTTP 200 ✓)
    ↓
Clean Workspace
```
