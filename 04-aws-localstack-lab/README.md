# ☁️ Lab 04: IAM Automation & Local Cloud Environment with LocalStack

Standard Operating Procedure (SOP) for deploying a simulated local AWS environment using **Docker Compose** and **LocalStack**, leveraging *Lifecycle Hooks* (`ready.d` and `shutdown.d`) to automatically provision IAM identities, service roles, and security audits without relying on persistent state.

---

## 🎯 1. Context & Technical Motivation (The Why)

In local learning and rapid prototyping environments using **LocalStack** (*Freemium/Community* tier), IAM resource state lives in volatile RAM: every time the container or host machine restarts, all users, groups, policies, and roles are wiped.

To avoid manually reconfiguring the entire identity baseline before every lab session and to enforce **AWS IAM (SAA-C03)** best practices from day one, this automated setup was designed around three core principles:

1. **Immutability & Reproducibility (Automated Bootstrap):** Once the container reaches the `READY` state, a Bash hook rebuilds the core IAM baseline from scratch in under 10 seconds and exports fresh credentials to a local Git-ignored directory (`output/`).
2. **Privilege Separation (Admin vs. Test / Role Assumption):**
   - The administrator user (`aimenrial432`) inherits full permissions through an **IAM Group** (`admin`), never via inline or direct user policies.
   - The testing user (`aws_test`) holds zero direct service permissions; instead, it is granted minimal authorization (`sts:AssumeRole`) to assume temporary **IAM Roles** (`DemoRole*`), mirroring how AWS services (such as EC2 instances) consume permissions without exposing static credentials.
3. **Continuous Auditing on Shutdown (Teardown Hook):** Before stopping the container gracefully, a shutdown hook (`shutdown.d`) automatically exports the **IAM Credential Report** (CSV) and **IAM Access Advisor** telemetry (JSON) to audit credential usage and enforce the Principle of Least Privilege.

---

## 🏗️ 2. Lab Architecture

```text
04-aws-localstack-lab/
├── docker-compose.yml              # LocalStack container orchestration & volume mounts
├── hooks/
│   ├── ready.d/
│   │   └── 01-init-iam.sh          # Automated startup provisioning (Users, Group, Roles)
│   └── shutdown.d/
│       └── 99-audit-iam.sh       # Automated audit report extraction on shutdown
├── .env                            # [Local / Git-ignored] Freemium activation token (create manually)
└── output/                         # [Auto-generated / Git-ignored] Runtime artifacts created on startup/shutdown
    ├── iam-credentials.json        # Access Keys generated during bootstrap
    ├── credential-report.csv       # Account-wide credential report on teardown
    └── access-advisor-*.json       # Service last-accessed telemetry per user

```

### Automated Execution Flow

| Phase | Trigger | Script | Executed Actions |
| :--- | :--- | :--- | :--- |
| **1. Startup** | `ready.d` | `01-init-iam.sh` | • Cleans up artifacts from previous sessions in `output/`.<br>• Creates the `admin` group (`AdministratorAccess`), account alias `aimenrial-cloud-lab`, and user `aimenrial432`.<br>• Creates user `aws_test` and generates *Access Keys* for both users into `output/iam-credentials.json`.<br>• Creates `DemoRoleForEC2` (`IAMReadOnlyAccess`) along with its *Instance Profile*, and authorizes `aws_test` to assume any `DemoRole*`. |
| **2. Operation** | Manual (CLI) | `aws` / `awslocal` | • Architecture testing, CLI profile switching (`--profile`), and temporary role assumption via `sts:AssumeRole`. |
| **3. Shutdown** | `shutdown.d` | `99-audit-iam.sh` | • Generates and Base64-decodes the **IAM Credential Report** into CSV.<br>• Triggers asynchronous **IAM Access Advisor** jobs for `aimenrial432` and `aws_test` and saves the output as JSON. |

---

## ⚙️ 3. Deployment & Usage (SOP)

### Prerequisites
- **Docker Desktop** running.
- **AWS CLI v2** installed on the host.
- Free LocalStack token (`LOCALSTACK_AUTH_TOKEN`) stored in `.env`:

```env
LOCALSTACK_AUTH_TOKEN=ls-xxxxxxxxxxxxxxxxxxxx
```

### Start the Environment

```powershell
cd 04-aws-localstack-lab
docker compose up -d
docker logs -f localstack-aws-lab
```

> **Validation:** Confirm `[INIT-IAM] Bootstrap IAM completed successfully.` in the container logs and verify that `output/iam-credentials.json` has been generated.

### Configure AWS CLI Profiles (Windows Host)
Using the keys exported to `output/iam-credentials.json`, register both profiles in `~/.aws/credentials`:

```powershell
aws configure --profile aimenrial432
aws configure --profile aws_test
```

### Stop the Environment & Generate Audit Reports

```powershell
docker compose down
```

> **Validation:** After a graceful shutdown, verify that `credential-report.csv`, `access-advisor-aimenrial432.json`, and `access-advisor-aws_test.json` appear inside `output/`.

---

## 🛠️ 4. Documented Troubleshooting

- **`exit code 55 (License activation failed)` on startup:** Recent LocalStack images require a valid `LOCALSTACK_AUTH_TOKEN` even on the free (*Freemium*) tier. Resolved by injecting the variable from `.env` inside `docker-compose.yml`.
- **`/bin/bash^M: bad interpreter` on Windows:** Shell scripts edited on Windows default to `CRLF` line endings. Before mounting hooks, ensure files are saved as **UTF-8 without BOM** with Unix (**`LF`**) line endings.
- **`awslocal` deprecation warnings in logs:** To eliminate verbose deprecation banners on every CLI call inside hooks, scripts use a lightweight wrapper directly targeting `aws --endpoint-url=http://localhost:4566`.
