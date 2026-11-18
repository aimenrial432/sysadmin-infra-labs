#!/usr/bin/env bash
# Script de auditoría rápida de bastionado SSH, UFW y Fail2Ban (Lab 01)
set -euo pipefail

echo "=========================================="
echo "  AUDITORÍA DE SEGURIDAD SSH & FIREWALL"
echo "=========================================="

echo -e "\n[1] Estado del servicio SSH:"
systemctl is-active ssh >/dev/null 2>&1 && echo "  -> ssh: ACTIVO" || echo "  -> ssh: INACTIVO"

echo -e "\n[2] Directivas críticas efectivas (sshd -T):"
if command -v sshd >/dev/null 2>&1; then
    sshd -T 2>/dev/null | grep -E "^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|maxauthtries|x11forwarding) " | sed 's/^/  -> /'
else
    echo "  -> sshd no encontrado en PATH"
fi

echo -e "\n[3] Estado y reglas de UFW:"
if command -v ufw >/dev/null 2>&1; then
    ufw status verbose | sed 's/^/  -> /'
else
    echo "  -> UFW no instalado"
fi

echo -e "\n[4] Estado de Fail2Ban (jail sshd):"
if command -v fail2ban-client >/dev/null 2>&1; then
    fail2ban-client status sshd 2>/dev/null | sed 's/^/  -> /' || echo "  -> Jail sshd no activa"
else
    echo "  -> Fail2Ban no instalado"
fi

echo -e "\n=========================================="
echo "  Auditoría finalizada."
echo "=========================================="
