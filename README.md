# Project Overview

This project is a simple RESTful API created using Spring Boot.


## CI/CD with Jenkins
This project includes a Jenkins pipeline for CI/CD. The pipeline performs the following tasks:
1. Checks out the code from the Git repository.
2. Builds the project using Maven.
3. Runs unit tests.
4. Deploys the application to the specified environment.


### Setting Up Jenkins
1. Install Jenkins from the official website.
2. Install the necessary plugins:
   - Git Plugin
   - Maven Integration Plugin
3. Configure Jenkins with your Git repository and Maven settings.

### Creating a Pipeline
1. Create a new pipeline in Jenkins.
2. Configure the pipeline script to point to your Jenkinsfile.


GitHub/GitLab
     ↓
Jenkins (local Docker)
     ↓
 ┌───┴────────────────┐
 │  1. Build Java     │  (Maven/Gradle)
 │  2. Tests          │
 │  3. Terraform      │  (provisionner l'infra cloud)
 │  4. Ansible        │  (configurer + déployer l'API)
 └────────────────────┘

## Jenkinsfile — Pipeline détaillé

Voici le `Jenkinsfile` complet utilisé dans ce projet, avec l'explication de chaque bloc.

```groovy
pipeline {
    agent any

    environment {
        SERVER_IP_CRED_ID = 'server-ip-id'
        GITHUB_TOKEN_CRED_ID = 'github-token-id'
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Checkout') {
            steps {
                withCredentials([string(credentialsId: "${GITHUB_TOKEN_CRED_ID}", variable: 'GITHUB_TOKEN')]) {
                    sh 'git config --global credential.helper store'
                    sh 'echo "https://${GITHUB_TOKEN}:@github.com" > ~/.git-credentials'
                    git url: "https://github.com/dwididit/springboot-simple-restful-api-jenkins.git", branch: 'master'
                }
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean package'
            }
        }

        stage('Prepare Deployment') {
            steps {
                writeFile file: 'deploy.sh', text: '''#!/bin/bash
cd /home/ubuntu/
docker compose down
docker compose up -d
'''
                sh 'chmod +x deploy.sh'
            }
        }

        stage('Transfer Files') {
            steps {
                script {
                    withCredentials([string(credentialsId: "${SERVER_IP_CRED_ID}", variable: 'SERVER_IP')]) {
                        sshagent(credentials: ['aws-ec2-pem']) {
                            sh '''
                            scp -o StrictHostKeyChecking=no target/store-0.0.1-SNAPSHOT.jar ubuntu@$SERVER_IP:/home/ubuntu/
                            scp -o StrictHostKeyChecking=no docker-compose.yml ubuntu@$SERVER_IP:/home/ubuntu/
                            scp -o StrictHostKeyChecking=no deploy.sh ubuntu@$SERVER_IP:/home/ubuntu/
                            '''
                        }
                    }
                }
            }
        }

        stage('Deploy to Staging') {
            steps {
                script {
                    withCredentials([string(credentialsId: "${SERVER_IP_CRED_ID}", variable: 'SERVER_IP')]) {
                        sshagent(credentials: ['aws-ec2-pem']) {
                            sh '''
                            ssh -o StrictHostKeyChecking=no ubuntu@$SERVER_IP "/home/ubuntu/deploy.sh"
                            '''
                            sh '''
                            sleep 30
                            url="http://$SERVER_IP:8081/swagger-ui/index.html"
                            response=$(curl -s -o /dev/null -w "%{http_code}" $url)
                            echo "Response code: $response"
                            if [ "$response" -eq 200 ]; then
                                echo "Visit to $url was successful"
                            else
                                echo "Visit to $url failed with status code: $response"
                                exit 1
                            fi
                            '''
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
```

---

### `agent any`
Jenkins peut utiliser n'importe quel agent/nœud disponible pour exécuter ce pipeline.

---

### `environment`
Déclare deux variables qui référencent des **identifiants Jenkins** (credentials) — les vraies valeurs sont stockées de façon sécurisée dans Jenkins et jamais écrites en dur.

| Variable | Credential Jenkins | Rôle |
|---|---|---|
| `SERVER_IP_CRED_ID` | `server-ip-id` | IP du serveur EC2 cible |
| `GITHUB_TOKEN_CRED_ID` | `github-token-id` | Token d'accès GitHub |

---

### `triggers { githubPush() }`
Le pipeline se déclenche **automatiquement à chaque push** sur GitHub via un webhook. Aucune intervention manuelle n'est nécessaire.

---

### Stage `Checkout`
Clone le dépôt GitHub en utilisant le token d'authentification stocké dans Jenkins. Le token est injecté via `withCredentials` pour ne jamais apparaître dans les logs.

---

### Stage `Build`
Compile le projet et génère le fichier `.jar` avec Maven :
```bash
mvn clean package
```
- `clean` : supprime les anciens artefacts
- `package` : compile le code et produit `target/store-0.0.1-SNAPSHOT.jar`

---

### Stage `Prepare Deployment`
Génère dynamiquement un script `deploy.sh` sur l'agent Jenkins. Ce script sera ensuite transféré et exécuté sur le serveur distant. Il effectue :
1. `docker compose down` — arrête les containers existants
2. `docker compose up -d` — redémarre avec la nouvelle version

---

### Stage `Transfer Files`
Transfère via **SCP** (SSH Copy) trois fichiers vers le serveur EC2 :

| Fichier | Destination |
|---|---|
| `store-0.0.1-SNAPSHOT.jar` | Le binaire de l'application |
| `docker-compose.yml` | La configuration Docker |
| `deploy.sh` | Le script de redémarrage |

La clé PEM AWS (`aws-ec2-pem`) est gérée par `sshagent` — elle n'est jamais exposée en clair.

---

### Stage `Deploy to Staging`
1. Exécute `deploy.sh` à distance via SSH sur le serveur EC2
2. Attend 30 secondes que l'application démarre
3. Vérifie que Swagger UI répond bien avec un **HTTP 200** :
```
http://<SERVER_IP>:8081/swagger-ui/index.html
```
Si le code de retour n'est pas 200, le pipeline échoue (`exit 1`).

---

### `post { always { cleanWs() } }`
Après chaque exécution (succès ou échec), Jenkins **nettoie l'espace de travail** pour éviter que des fichiers résiduels (JAR, credentials temporaires) ne s'accumulent sur l'agent.

---

### Flux complet

```
Push GitHub
    ↓
Checkout (clone repo)
    ↓
Build (mvn clean package → .jar)
    ↓
Prepare Deployment (génère deploy.sh)
    ↓
Transfer Files (SCP → EC2)
    ↓
Deploy to Staging (SSH → docker compose restart)
    ↓
Health Check (curl Swagger → HTTP 200 ✓)
    ↓
Clean Workspace
```