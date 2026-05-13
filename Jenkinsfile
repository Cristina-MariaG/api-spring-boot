pipeline {
    agent any

    environment {
        SERVER_IP_CRED_ID = 'server-ip-id'
    }

    triggers {
        githubPush()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
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
                            mkdir -p ~/.ssh && chmod 700 ~/.ssh
                            ssh-keyscan -H $SERVER_IP >> ~/.ssh/known_hosts
                            ssh ubuntu@$SERVER_IP "mkdir -p /home/ubuntu/target"
                            scp target/store-0.0.1-SNAPSHOT.jar ubuntu@$SERVER_IP:/home/ubuntu/target/
                            scp docker-compose.yml ubuntu@$SERVER_IP:/home/ubuntu/
                            scp Dockerfile ubuntu@$SERVER_IP:/home/ubuntu/
                            scp deploy.sh ubuntu@$SERVER_IP:/home/ubuntu/
                            ssh ubuntu@$SERVER_IP "rm -f /home/ubuntu/.env"
                            scp $ENV_FILE ubuntu@$SERVER_IP:/home/ubuntu/.env
                            ssh ubuntu@$SERVER_IP "sed -i 's/\r//' /home/ubuntu/.env"
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
                            url="http://$SERVER_IP:8081/actuator/health"
                            response=$(curl -s -o /dev/null -w "%{http_code}" $url)
                            echo "Response code: $response"
                            if [ "$response" -eq 200 ]; then
                                echo "App is up at http://$SERVER_IP:8081"
                            else
                                echo "Health check failed with status code: $response"
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
