# Lab 01: Bastionado de Servidor Linux (SSH + UFW + Fail2Ban) y Auditoría Bash

## 1. Objetivo
Desplegar una configuración base segura (*hardening*) para el acceso administrativo remoto de un servidor Linux en producción, eliminando vectores habituales de intrusión (acceso `root` directo, fuerza bruta por contraseña y exposición innecesaria de puertos) y automatizando la verificación del cumplimiento mediante un script en Bash.

---

## 2. Arquitectura y Topología del Entorno

* **Hipervisor y Red:** VMware Workstation (Red NAT `192.168.164.0/24`)
* **Servidor Objetivo:** Ubuntu 22.04.5 LTS (`admin-ddbb`) — IP: `192.168.164.129/24`
* **Estación de Administración:** Archcraft Linux — IP: `192.168.164.139/24`
* **Usuario Administrador:** `sysadmin` (con privilegios `sudo`)
* **Política de Acceso:** Autenticación exclusiva mediante clave criptográfica **Ed25519** en puerto no estándar (`TCP/2222`).

---

## 3. Setup Inicial y Prerrequisitos (Servidor Ubuntu)

Antes de aplicar el bastionado, se prepara el sistema base instalando los servicios necesarios y creando una cuenta administrativa dedicada para evitar el uso cotidiano de `root`:

```bash
# 1. Actualización de repositorios e instalación de servicios
sudo apt update && sudo apt install -y openssh-server ufw fail2ban
sudo systemctl enable --now ssh

# 2. Creación de usuario administrativo dedicado con privilegios sudo
sudo adduser sysadmin
sudo usermod -aG sudo sysadmin
```

---

## 4. Implementación Paso a Paso

### 4.1. Generación y despliegue de clave Ed25519 (Desde Cliente Archcraft)
En la estación cliente (`192.168.164.139`) se genera un par de claves **Ed25519** y se transfiere la clave pública al servidor objetivo:

```bash
ssh-keygen -t ed25519 -C "sysadmin@archcraft-lab"
ssh-copy-id -i ~/.ssh/id_ed25519.pub sysadmin@192.168.164.129
```

### 4.2. Configuración de Firewall Perimetral (UFW)
Se aplica política restrictiva por defecto para tráfico entrante, habilitando el nuevo puerto administrativo `2222/tcp` únicamente para la subred de gestión y revocando el puerto estándar `22/tcp`:

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.164.0/24 to any port 2222 proto tcp
sudo ufw delete allow from 192.168.164.0/24 to any port 22 proto tcp
sudo ufw enable
```

### 4.3. Bastionado del servicio OpenSSH (`/etc/ssh/sshd_config.d/99-hardening.conf`)
Se aplica un fichero modular de configuración segura (recogido en [`configs/sshd_config.hardened`](./configs/sshd_config.hardened)) para no alterar la plantilla base del sistema:

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'EOF'
Port 2222
PermitRootLogin no
AllowUsers sysadmin
PasswordAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
MaxAuthTries 3
X11Forwarding no
EOF

# Validación de sintaxis antes de reiniciar el servicio
sudo sshd -t && sudo systemctl restart ssh
```

### 4.4. Protección activa frente a fuerza bruta (Fail2Ban)
Se configura una *jail* específica en `/etc/fail2ban/jail.local` monitorizando el nuevo puerto `2222`:

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

---

## 5. Validación y Auditoría Automatizada

### 5.1. Prueba de conectividad y rechazo
Desde la estación cliente (`192.168.164.139`):
* **Acceso autorizado:** `ssh -p 2222 sysadmin@192.168.164.129` -> Conexión directa sin contraseña mediante clave Ed25519.
* **Acceso privilegiado bloqueado:** `ssh -p 2222 root@192.168.164.129` -> Rechazado (`Permission denied (publickey)`).

### 5.2. Ejecución del script de auditoría (`scripts/audit_ssh.sh`)
Se ejecuta el script automatizado en el servidor para verificar el servicio, las directivas efectivas en memoria (`sshd -T`), las reglas de `UFW` y el estado de `Fail2Ban`:

```bash
chmod +x scripts/audit_ssh.sh
sudo ./scripts/audit_ssh.sh
```

---

## 6. Troubleshooting e Incidencias Resueltas

* **Bloqueo previo en UFW durante el despliegue inicial:** Al intentar ejecutar `ssh-copy-id` hacia `192.168.164.129`, la conexión devolvió `Connection timed out`. El diagnóstico mediante `ufw status` y `ss -tlnp` reveló que `sshd` escuchaba correctamente, pero existía una regla residual `DENY` de un laboratorio anterior bloqueando la IP del cliente (`192.168.164.139`). Se resolvió eliminando dicha regla (`ufw delete deny from 192.168.164.139`) y habilitando temporalmente el puerto `22/tcp` hasta completar la migración al `2222/tcp`.
* **Orden crítico de ejecución:** Siempre se debe habilitar el nuevo puerto en `UFW` y verificar el acceso con clave SSH en una segunda terminal **antes** de cerrar la sesión activa o deshabilitar `PasswordAuthentication`, evitando perder conectividad remota con el servidor.

---

## 7. Evidencia de Ejecución

Salida obtenida tras ejecutar `./scripts/audit_ssh.sh` sobre `admin-ddbb` (`192.168.164.129`):

```text
==========================================
  AUDITORÍA DE SEGURIDAD SSH & FIREWALL
==========================================

[1] Estado del servicio SSH:
  -> ssh: ACTIVO

[2] Directivas críticas efectivas (sshd -T):
  -> port 2222
  -> maxauthtries 3
  -> permitrootlogin no
  -> pubkeyauthentication yes
  -> passwordauthentication no
  -> x11forwarding no

[3] Estado y reglas de UFW:
  -> Estado: activo
  -> Acceso: on (low)
  -> Predeterminado: deny (entrantes), allow (salientes), deny (enrutados)
  -> Perfiles nuevos: skip
  -> 
  -> Hasta                      Acción      Desde
  -> -----                      ------      -----
  -> 2222/tcp                   ALLOW IN    192.168.164.0/24          
  -> 

[4] Estado de Fail2Ban (jail sshd):
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
  Auditoría finalizada.
==========================================
```
