# Lab 01: Linux Server Hardening (SSH + UFW + Fail2Ban) & Bash Auditing

## 1. Objective
Deploy a secure baseline configuration (*hardening*) for remote administrative access on a production Linux server, eliminating common intrusion vectors (direct `root` login, password brute-force attacks, unnecessary port exposure, and unpatched critical vulnerabilities) and automating compliance verification via a Bash script.

---

## 2. Environment Architecture & Topology

- **Hypervisor & Network:** VMware Workstation (NAT Network `192.168.164.0/24`)
- **Target Server:** Ubuntu 22.04.5 LTS (`admin-ddbb`) — IP: `192.168.164.129/24`
- **Management Workstation:** Archcraft Linux — IP: `192.168.164.139/24`
- **Administrative User:** `sysadmin` (with `sudo` privileges)
- **Access Policy:** Exclusive cryptographic **Ed25519** key authentication on a non-standard port (`TCP/2222`), pre-authentication legal banner, and automated security patching.

---

## 3. Initial Setup & Prerequisites (Ubuntu Server)

Before applying hardening measures, the base system is prepared by installing the required services and creating a dedicated administrative account to avoid daily `root` usage:

```bash
# 1. Update repositories and install required services
sudo apt update && sudo apt install -y openssh-server ufw fail2ban unattended-upgrades
sudo systemctl enable --now ssh

# 2. Create a dedicated administrative user with sudo privileges
sudo adduser sysadmin
sudo usermod -aG sudo sysadmin
```

---

## 4. Step-by-Step Implementation

### 4.1. Ed25519 Key Generation & Client Profile (From Archcraft)
On the client workstation (`192.168.164.139`), an **Ed25519** key pair is generated, the public key is copied to the target server, and a connection alias is configured in `~/.ssh/config`:

```bash
ssh-keygen -t ed25519 -C "sysadmin@archcraft-lab"
ssh-copy-id -i ~/.ssh/id_ed25519.pub sysadmin@192.168.164.129

mkdir -p ~/.ssh && chmod 700 ~/.ssh
printf "Host lab-ubuntu\n    HostName 192.168.164.129\n    Port 2222\n    User sysadmin\n    IdentityFile ~/.ssh/id_ed25519\n    IdentitiesOnly yes\n" > ~/.ssh/config
chmod 600 ~/.ssh/config
```

### 4.2. Perimeter Firewall Configuration (UFW)
A default-deny policy is enforced for incoming traffic, allowing the new administrative port `2222/tcp` exclusively from the management subnet and revoking the standard `22/tcp` port:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.164.0/24 to any port 2222 proto tcp
sudo ufw delete allow from 192.168.164.0/24 to any port 22 proto tcp
sudo ufw enable
```

### 4.3. Legal Banner & OpenSSH Service Hardening
A restricted-access legal banner is configured in `/etc/issue.net`, and the modular drop-in file `/etc/ssh/sshd_config.d/99-hardening.conf` (stored in [`configs/sshd_config.hardened`](./configs/sshd_config.hardened)) is applied:

```bash
sudo tee /etc/issue.net > /dev/null << 'EOF'
***************************************************************************
  RESTRICTED ACCESS - MONITORED SYSTEM
  Unauthorized access is prohibited and will be logged and audited.
***************************************************************************
EOF

sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'EOF'
Port 2222
PermitRootLogin no
AllowUsers sysadmin
PasswordAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
Banner /etc/issue.net
EOF

# Validate syntax before restarting the service
sudo sshd -t && sudo systemctl restart ssh
```

### 4.4. Active Brute-Force Protection (Fail2Ban)
A dedicated *jail* is configured in `/etc/fail2ban/jail.local` monitoring port `2222` with a 1-hour ban (`3600s`) after 3 failed attempts:

```bash
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[sshd]
enabled = true
port = 2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
EOF

sudo systemctl enable --now fail2ban && sudo systemctl restart fail2ban
```

### 4.5. Automatic Security Updates (`unattended-upgrades`)
Daily automatic installation of critical security patches and their corresponding `systemd` timers are enabled:

```bash
sudo dpkg-reconfigure -plow unattended-upgrades
sudo systemctl enable --now unattended-upgrades
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
```

---

## 5. Validation & Automated Auditing

### 5.1. Connectivity, Rejection & Active Blocking Tests (Fail2Ban)
From the client workstation (`192.168.164.139`):
- **Authorized access via alias:** `ssh lab-ubuntu` -> Displays the pre-authentication legal banner and grants a passwordless session via the Ed25519 key.
- **Blocked privileged login:** `ssh -p 2222 root@192.168.164.129` -> Rejected (`Permission denied (publickey)`).
- **Attack simulation & controlled unban:** After triggering 3 consecutive failed login attempts, Fail2Ban blocks the offending IP at the firewall level. To revert it from an administrative console:
  ```bash
  sudo fail2ban-client status sshd
  sudo fail2ban-client set sshd unbanip 192.168.164.139
  ```

### 5.2. Audit Script Execution (`scripts/audit_ssh.sh`)
The automated script is executed on the server to verify the service status, effective runtime directives in memory (`sshd -T`), `UFW` rules, and `Fail2Ban` jail status:

```bash
chmod +x scripts/audit_ssh.sh
sudo ./scripts/audit_ssh.sh
```

---

## 6. Troubleshooting & Resolved Incidents

- **Pre-existing UFW block during initial deployment:** When attempting to run `ssh-copy-id` toward `192.168.164.129`, the connection returned `Connection timed out`. Diagnostics via `ufw status` and `ss -tlnp` revealed that `sshd` was listening properly, but a leftover `DENY` rule from a previous lab was blocking the client IP (`192.168.164.139`). Resolved by removing that rule (`ufw delete deny from 192.168.164.139`) and temporarily allowing port `22/tcp` until the migration to `2222/tcp` was completed.
- **Self-lockout during Fail2Ban testing:** Generating 3 failed authentication attempts from the management workstation itself caused Fail2Ban to drop the active SSH session's TCP traffic. Used the hypervisor's local console to run `fail2ban-client set sshd unbanip 192.168.164.139` and restore access.
- **`dpkg` lock contention by background `unattended-upgrades`:** Running `apt` immediately after boot hit a lock on `/var/lib/dpkg/lock-frontend` because the automatic `unattended-upgrade` process was stuck in a dependency calculation loop without active child `dpkg` processes. Controlled termination of the stuck process, cleanup of orphaned `.lock` files, and package manager verification via `sudo dpkg --configure -a` and `sudo apt-get check` resolved the contention cleanly.

---

## 7. Execution Evidence

### 7.1. Audit Script Output (`./scripts/audit_ssh.sh`)
```text
==========================================
  SSH & FIREWALL SECURITY AUDIT
==========================================

[1] SSH Service Status:
  -> ssh: ACTIVE

[2] Critical Effective Directives (sshd -T):
  -> port 2222
  -> maxauthtries 3
  -> permitrootlogin no
  -> pubkeyauthentication yes
  -> passwordauthentication no
  -> x11forwarding no

[3] UFW Status & Rules:
  -> Status: active
  -> Logging: on (low)
  -> Default: deny (incoming), allow (outgoing), deny (routed)
  -> New profiles: skip
  -> 
  -> To                         Action      From
  -> --                         ------      ----
  -> 2222/tcp                   ALLOW IN    192.168.164.0/24          
  -> 

[4] Fail2Ban Status (jail sshd):
  -> Status for the jail: sshd
  -> |- Filter
  -> |  |- Currently failed:	0
  -> |  |- Total failed:	0
  -> |  `- File list:	/var/log/auth.log
  -> `- Actions
  ->    |- Currently banned:	0
  ->    |- Total banned:	0
  ->    `- Banned IP list:	

==========================================
  Audit completed.
==========================================
```

### 7.2. Active Detection & Ban Evidence in Fail2Ban
```text
root@admin-ddbb:/home/admin432# sudo fail2ban-client status sshd
Status for the jail: sshd
|- Filter
|  |- Currently failed:	0
|  |- Total failed:	3
|  `- File list:	/var/log/auth.log
`- Actions
   |- Currently banned:	1
   |- Total banned:	1
   `- Banned IP list:	192.168.164.139
```

---

## 8. Conclusions & Key Takeaways

- **Defense in Depth:**
  - **Network (`UFW`):** Restricts exposure exclusively to port `2222/tcp` and the management subnet.
  - **Identity (`OpenSSH`):** Eliminates password brute-force vectors and direct `root` access by enforcing `Ed25519` keys.
  - **Active Response (`Fail2Ban`):** Automates perimeter blocking upon detecting intrusion patterns in `/var/log/auth.log`.
  - **Maintenance (`unattended-upgrades`):** Ensures continuous application of critical security patches without manual intervention.

- **Safe Operations & Lockout Prevention:**
  - Using modular drop-in files inside `/etc/ssh/sshd_config.d/` keeps the base configuration clean across future package upgrades.
  - Always validating with `sshd -t` and keeping an active session (or hypervisor console) open prevents remote lockouts when applying restrictive rules.

- **Auditing Effective Runtime State:**
  - Inspecting configuration files on disk does not guarantee changes are active in memory; tools like `sshd -T`, `ufw status verbose`, and `fail2ban-client status` validate the live runtime state and allow automated Bash auditing.

- **Real-World Incident Resolution:**
  - Diagnosing residual firewall rules, self-bans during intrusion testing, and `dpkg` lock contention enables targeted recovery without compromising system integrity.
