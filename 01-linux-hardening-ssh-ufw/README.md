# Lab 01: Bastionado de Servidor Linux (SSH + UFW + Fail2Ban) y Auditoría Bash

## 1. Objetivo
Desplegar una configuración base segura (*hardening*) para el acceso administrativo remoto de un servidor Linux en producción, eliminando vectores habituales de intrusión (acceso `root` directo, fuerza bruta por contraseña, exposición innecesaria de puertos y desactualización de parches críticos) y automatizando la verificación del cumplimiento mediante un script en Bash.

---

## 2. Arquitectura y Topología del Entorno

* **Hipervisor y Red:** VMware Workstation (Red NAT `192.168.164.0/24`)
* **Servidor Objetivo:** Ubuntu 22.04.5 LTS (`admin-ddbb`) — IP: `192.168.164.129/24`
* **Estación de Administración:** Archcraft Linux — IP: `192.168.164.139/24`
* **Usuario Administrador:** `sysadmin` (con privilegios `sudo`)
* **Política de Acceso:** Autenticación exclusiva mediante clave criptográfica **Ed25519** en puerto no estándar (`TCP/2222`), aviso legal pre-autenticación y parcheo automático de seguridad.

---

## 3. Setup Inicial y Prerrequisitos (Servidor Ubuntu)

Antes de aplicar el bastionado, se prepara el sistema base instalando los servicios necesarios y creando una cuenta administrativa dedicada para evitar el uso cotidiano de `root`:

```bash
# 1. Actualización de repositorios e instalación de servicios
sudo apt update && sudo apt install -y openssh-server ufw fail2ban unattended-upgrades
sudo systemctl enable --now ssh

# 2. Creación de usuario administrativo dedicado con privilegios sudo
sudo adduser sysadmin
sudo usermod -aG sudo sysadmin
```

---

## 4. Implementación Paso a Paso

### 4.1. Generación de clave Ed25519 y perfil de cliente (Desde Archcraft)
En la estación cliente (`192.168.164.139`) se genera un par de claves **Ed25519**, se transfiere la clave pública al servidor objetivo y se configura un alias de acceso en `~/.ssh/config`:

```bash
ssh-keygen -t ed25519 -C "sysadmin@archcraft-lab"
ssh-copy-id -i ~/.ssh/id_ed25519.pub sysadmin@192.168.164.129

mkdir -p ~/.ssh && chmod 700 ~/.ssh
printf "Host lab-ubuntu\n    HostName 192.168.164.129\n    Port 2222\n    User sysadmin\n    IdentityFile ~/.ssh/id_ed25519\n    IdentitiesOnly yes\n" > ~/.ssh/config
chmod 600 ~/.ssh/config
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

### 4.3. Banner Legal y Bastionado del servicio OpenSSH
Se configura un banner legal de acceso restringido en `/etc/issue.net` y se aplica el fichero modular `/etc/ssh/sshd_config.d/99-hardening.conf` (recogido en [`configs/sshd_config.hardened`](./configs/sshd_config.hardened)):

```bash
sudo tee /etc/issue.net > /dev/null << 'EOF'
***************************************************************************
  ACCESO RESTRINGIDO - SISTEMA MONITORIZADO
  El acceso no autorizado está prohibido y será registrado y auditado.
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

# Validación de sintaxis antes de reiniciar el servicio
sudo sshd -t && sudo systemctl restart ssh
```

### 4.4. Protección activa frente a fuerza bruta (Fail2Ban)
Se configura una *jail* específica en `/etc/fail2ban/jail.local` monitorizando el puerto `2222` con bloqueo de 1 hora (`3600s`) tras 3 intentos fallidos:

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

### 4.5. Actualizaciones automáticas de seguridad (`unattended-upgrades`)
Se habilita la instalación automática diaria de parches críticos de seguridad y sus temporizadores en `systemd`:

```bash
sudo dpkg-reconfigure -plow unattended-upgrades
sudo systemctl enable --now unattended-upgrades
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
```

---

## 5. Validación y Auditoría Automatizada

### 5.1. Pruebas de conectividad, rechazo y bloqueo activo (Fail2Ban)
Desde la estación cliente (`192.168.164.139`):
* **Acceso autorizado mediante alias:** `ssh lab-ubuntu` -> Muestra el banner legal pre-autenticación y concede sesión directa sin contraseña mediante clave Ed25519[cite: 9].
* **Acceso privilegiado bloqueado:** `ssh -p 2222 root@192.168.164.129` -> Rechazado (`Permission denied (publickey)`).
* **Simulación de ataque y desbaneo controlado:** Tras provocar 3 intentos fallidos consecutivos, Fail2Ban añade la IP atacante al bloqueo perimetral. Para revertirlo desde consola administrativa:
  ```bash
  sudo fail2ban-client status sshd
  sudo fail2ban-client set sshd unbanip 192.168.164.139
  ```

### 5.2. Ejecución del script de auditoría (`scripts/audit_ssh.sh`)
Se ejecuta el script automatizado en el servidor para verificar el servicio, las directivas efectivas en memoria (`sshd -T`), las reglas de `UFW` y el estado de `Fail2Ban`:

```bash
chmod +x scripts/audit_ssh.sh
sudo ./scripts/audit_ssh.sh
```

---

## 6. Troubleshooting e Incidencias Resueltas

* **Bloqueo previo en UFW durante el despliegue inicial:** Al intentar ejecutar `ssh-copy-id` hacia `192.168.164.129`, la conexión devolvió `Connection timed out`. El diagnóstico mediante `ufw status` y `ss -tlnp` reveló que `sshd` escuchaba correctamente, pero existía una regla residual `DENY` de un laboratorio anterior bloqueando la IP del cliente (`192.168.164.139`). Se resolvió eliminando dicha regla (`ufw delete deny from 192.168.164.139`) y habilitando temporalmente el puerto `22/tcp` hasta completar la migración al `2222/tcp`.
* **Autobloqueo durante pruebas de Fail2Ban:** Al generar 3 fallos de autenticación desde la propia estación de administración, Fail2Ban cortó el tráfico TCP de la sesión SSH activa. Se operó desde la consola local del hipervisor para ejecutar `fail2ban-client set sshd unbanip 192.168.164.139` y restablecer el acceso.
* **Contención de caché `dpkg` por `unattended-upgrades` en segundo plano:** Al ejecutar `apt` inmediatamente tras el arranque, el proceso automático `unattended-upgrade` mantenía `/var/lib/dpkg/lock-frontend` en bucle de cálculo de dependencias sin procesos `dpkg` hijos activos. Se finalizó el proceso de forma controlada, se limpiaron los ficheros `.lock` huérfanos y se validó la integridad del gestor de paquetes con `sudo dpkg --configure -a` y `sudo apt-get check`.

---

## 7. Evidencia de Ejecución

### 7.1. Salida del script de auditoría (`./scripts/audit_ssh.sh`)
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

### 7.2. Evidencia de detección y bloqueo activo en Fail2Ban
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
