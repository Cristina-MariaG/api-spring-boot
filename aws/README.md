# AWS Infrastructure

This folder contains everything needed to provision and configure the AWS infrastructure for this project.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) installed locally
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) installed locally
- AWS CLI configured (`aws configure`) with an account that has EC2, S3, DynamoDB, and IAM permissions
- `aws/.env.infra` filled in (copy from `aws/.env.infra.example`)
- `aws/terraform/terraform.tfvars` filled in (copy from `aws/terraform/terraform.tfvars.example`)

---

## Scripts

### `setup-infra.sh` — Provision the infrastructure from scratch

Runs the full chain in order:

```bash
./aws/setup-infra.sh
```

**What it does, step by step:**

| Step | Action |
|------|--------|
| 1 | `terraform apply` on `backend-setup` → creates the S3 bucket and DynamoDB table |
| 2 | `terraform apply` on `main` → creates the EC2 instance, Elastic IP, Security Group, and PEM key |
| 3 | Copies the PEM key to `~/springboot-api.pem` and applies `chmod 600` |
| 4 | Retrieves the Elastic IP via `terraform output` |
| 5 | Creates or updates the `server-ip-id` credential in Jenkins via the REST API |
| 6 | Generates `aws/ansible/inventory.ini` with the IP and PEM path |
| 7 | Waits for SSH to be available on the instance (polls every 10s) |
| 8 | Runs `ansible-playbook install.yml` to configure Docker on the server |

> The backend-setup is idempotent: if the S3 bucket and DynamoDB table already exist, Terraform does nothing.

---

### `destroy-infra.sh` — Tear down all infrastructure

```bash
./aws/destroy-infra.sh
```

Prompts for confirmation (`yes`) before proceeding.

**What it does:**

| Step | Action |
|------|--------|
| 1 | `terraform destroy` on `main` → removes EC2, EIP, Security Group, key pair |
| 2 | `terraform destroy` on `backend-setup` → removes the S3 bucket and DynamoDB table |
| 3 | Deletes `springboot-api.pem` locally |
| 4 | Deletes `aws/ansible/inventory.ini` |

> ⚠️ Destroying the S3 bucket deletes the Terraform state. This operation is irreversible.

---

## What Terraform provisions

### `backend-setup/` — Terraform remote backend

Creates the resources needed to store the Terraform state securely:

- **S3 Bucket** `springboot-api-tfstate`
  - Versioning enabled (allows rollback to a previous state if corrupted)
  - AES-256 encryption at rest
  - Public access fully blocked

- **DynamoDB Table** `springboot-api-tf-lock`
  - State lock: prevents two concurrent `terraform apply` runs

---

## Why S3 + DynamoDB for Terraform state?

When Terraform creates resources, it needs to remember what it created. It records everything in a **state file** (`terraform.tfstate`): which EC2 instance exists, what its ID is, which Security Group is attached, etc. Without this file, Terraform has no idea what is already deployed and would try to create everything again from scratch.

By default, this file is stored locally on your machine. That works for experimenting, but creates real problems as soon as more than one person (or process) touches the infrastructure:

- If the file is lost (disk failure, accidental deletion), Terraform loses track of all existing resources — you can no longer update or destroy them cleanly
- If two `terraform apply` commands run at the same time (two terminals, two CI jobs), they can both read the state before either has written back their changes, leading to conflicts and corrupted state

The solution is a **remote backend**: store the state file somewhere reliable and add a lock so only one operation can run at a time.

**S3 — remote storage for the state file**

S3 stores the `terraform.tfstate` file remotely instead of on your local disk. The bucket is configured with:
- **Versioning enabled** — every `terraform apply` creates a new version of the state file. If a deployment corrupts the state, you can roll back to any previous version.
- **AES-256 encryption at rest** — the state file can contain sensitive values (resource IDs, outputs). Encryption ensures they are not stored in plaintext.
- **Public access fully blocked** — the bucket is not accessible from the internet under any circumstances.

**DynamoDB — distributed lock**

S3 alone is not enough. S3 is eventually consistent, which means two processes could read the same state file at nearly the same time, each make changes, and then both write back — overwriting each other's work.

DynamoDB solves this with a **lock table**. Before any `terraform apply` or `terraform plan` can proceed, Terraform writes a lock entry to DynamoDB. If another process tries to run at the same time and finds the lock already held, it waits (or fails with a clear error). Once the first operation finishes, it releases the lock and the next process can proceed.

The two work together like this:

```
terraform apply
      │
      ├─ 1. Acquire lock          → write to DynamoDB
      │        └─ if lock exists  → wait or abort
      │
      ├─ 2. Read current state    → download from S3
      │
      ├─ 3. Plan + apply changes  → create/update/destroy resources
      │
      ├─ 4. Write new state       → upload to S3 (new version created)
      │
      └─ 5. Release lock          → delete from DynamoDB
```

This is the standard pattern recommended by HashiCorp for any Terraform project beyond a single developer experimenting locally. Even when working alone, it protects against accidental concurrent runs and gives you a versioned history of every infrastructure change.

In this project, the backend infrastructure (S3 bucket + DynamoDB table) is provisioned first, in a separate Terraform module (`aws/terraform/backend-setup/`), before the main infrastructure is applied. This is intentional: the backend must exist before Terraform can use it to store the state of the main module.

### `main.tf` — Application infrastructure

| Resource | Details |
|----------|---------|
| **EC2 Instance** | Ubuntu 22.04 LTS (dynamic Canonical AMI), type `t2.micro` |
| **Security Group** | SSH:22 (your IP only via `my_ip`), :8081 (app, open) |
| **Elastic IP** | Fixed public IP attached to the instance |
| **RSA 4096 Key Pair** | Generated by Terraform, saved as `springboot-api.pem` |

The PEM key is generated automatically. `setup-infra.sh` copies it to `~/springboot-api.pem` (Linux home directory) and applies `chmod 600` — required because `chmod` does not work on `/mnt/c/` (NTFS via WSL).

> SSH (port 22) is restricted to your IP (`my_ip` in `terraform.tfvars`). Ports 80 and 443 are not open — only the application port 8081 is publicly accessible.

---

## What Ansible configures

The `ansible/install.yml` playbook connects via SSH to the EC2 instance and:

1. **Adds the official Docker repository** (GPG key + apt source)
2. **Installs Docker CE** (`docker-ce`, `docker-ce-cli`, `containerd.io`)
3. **Installs the Compose plugin** (`docker-compose-plugin`) — required for `docker compose` v2
4. **Enables Docker at boot** via systemd
5. **Adds the `ubuntu` user** to the `docker` group — to run Docker without `sudo`

Once Ansible finishes, the server is ready to receive Jenkins deployments (`docker compose up`).
