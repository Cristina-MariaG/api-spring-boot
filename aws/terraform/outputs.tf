output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.app.id
}

output "elastic_ip" {
  description = "Elastic IP publique de l'instance"
  value       = aws_eip.app_eip.public_ip
}

output "ssh_connection" {
  description = "Commande SSH pour se connecter à l'instance"
  value       = "ssh -i ${var.project_name}.pem -p ${var.ssh_port} ubuntu@${aws_eip.app_eip.public_ip}"
}

output "app_url" {
  description = "URL de l'application"
  value       = "http://${aws_eip.app_eip.public_ip}:${var.app_port}/swagger-ui/index.html"
}

output "ami_used" {
  description = "AMI Ubuntu utilisée"
  value       = data.aws_ami.ubuntu.id
}
