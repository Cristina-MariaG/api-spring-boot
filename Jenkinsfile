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
                    git url: "https://github.com/Cristina-MariaG/api-spring-boot.git", branch: 'main'
                }
            }
        }

        stage('Build') {
            steps {
                sh 'chmod +x mvnw && sed -i "s/\r//" mvnw && ./mvnw clean package -DskipTests'
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
                    withCredentials([
                        string(credentialsId: "${SERVER_IP_CRED_ID}", variable: 'SERVER_IP'),
                        file(credentialsId: 'env-file-id', variable: 'ENV_FILE')
                    ]) {
                        sshagent(credentials: ['aws-ec2-pem']) {
                            sh '''
                            ssh-keyscan -H $SERVER_IP >> ~/.ssh/known_hosts
                            scp target/store-0.0.1-SNAPSHOT.jar ubuntu@$SERVER_IP:/home/ubuntu/
                            scp docker-compose.yml ubuntu@$SERVER_IP:/home/ubuntu/
                            scp deploy.sh ubuntu@$SERVER_IP:/home/ubuntu/
                            scp $ENV_FILE ubuntu@$SERVER_IP:/home/ubuntu/.env
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
                            ssh ubuntu@$SERVER_IP "/home/ubuntu/deploy.sh"
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
