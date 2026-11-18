# Lab 01: Bastionado de Servidor Linux (SSH + UFW + Fail2Ban) y Auditoría Bash

## 1. Objetivo
Desplegar una configuración base segura (*hardening*) para el acceso administrativo remoto de un servidor Linux en producción, eliminando vectores habituales de intrusión (acceso `root` directo, fuerza bruta por contraseña y exposición innecesaria de puertos) y automatizando la verificación del cumplimiento mediante un script en Bash.

---

## 2. Arquitectura y Topología del Entorno

* **Servidor Objetivo:** VM Linux (Ubuntu Escritorio) — IP: `192.168.164.129/24`
* **Equipo de Administración:** Estación cliente — Subred autorizada: `192.168.164.139/24`
* **Usuario Administrador:** `sysadmin` (con privilegios `sudo`)
* **Política de Acceso:** Autenticación exclusiva mediante clave criptográfica **Ed25519** en puerto no estándar (`TCP/2222`).

---

## 3. Implementación

### 3.1. Creación de usuario administrativo y despliegue de clave Ed25519
En el equipo cliente se genera el par de claves y se transfiere la clave pública al servidor:
```bash
ssh-keygen -t ed25519 -C "sysadmin@infra-lab"
ssh-copy-id -i ~/.ssh/id_ed25519.pub sysadmin@192.168.10.20
