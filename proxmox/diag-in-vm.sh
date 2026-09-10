#!/usr/bin/env bash
#
# SweetHome3D-MCP – Diagnose IN der VM (als root)
#   sudo -i
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/proxmox/diag-in-vm.sh)"
#
# Gibt alles aus, was zur Fehlersuche nötig ist. Output bitte komplett kopieren.
#
echo "===== CLOUD-INIT ====="
cloud-init status --long 2>&1 | head -25
echo ""
echo "===== INSTALL-LOG (letzte 80 Zeilen) ====="
tail -n 80 /var/log/sweethome3d-install.log 2>&1
echo ""
echo "===== CLOUD-INIT RUNCMD SPUREN ====="
grep -i -E 'sweethome|runcmd' /var/log/cloud-init-output.log 2>/dev/null | tail -10 || echo "(kein cloud-init-output.log)"
echo ""
echo "===== SERVICES ====="
systemctl is-active vncserver@1.service novnc.service 2>&1
echo ""
echo "===== PORTS ====="
(ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null) | grep -E ':(6080|5901|9877)' || (ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null)
echo ""
echo "===== PLATTE/RAM ====="
df -h / 2>&1 | tail -2; free -m 2>&1 | head -2
echo ""
echo "===== DATEIEN ====="
ls /opt/ 2>&1; ls /root/.eteks/sweethome3d/plugins/ /root/.sweethome3d/plugins/ 2>&1
echo ""
echo "===== VNC-JOURNAL ====="
journalctl -u vncserver@1 --no-pager -n 30 2>&1 | tail -30
echo ""
echo "===== NOVNC-JOURNAL ====="
journalctl -u novnc --no-pager -n 15 2>&1 | tail -15
