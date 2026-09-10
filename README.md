# SweetHome3D-MCP-Proxmox-Server

Sweet Home 3D als 24/7 Desktop in einer Proxmox-VM (Ubuntu 24.04 + XFCE + noVNC) inkl. MCP-Plugin für AI-Steuerung via opencode / Claude.

## Was wird installiert?

- Ubuntu 24.04 VM (von dir in Proxmox erstellt, 4 vCPU / 8 GB RAM / 20 GB, später erweiterbar)
- XFCE + TigerVNC (`:5901`) + noVNC Web-Desktop (`:6080`)
- Sweet Home 3D 7.5 (SourceForge, eTeks) nach `/opt/SweetHome3D`
- MCP-Plugin (GitHub `grimashevich/sweethome3d-mcp-server`, latest Release) nach `~/.eteks/sweethome3d/plugins/`
- systemd-Services `sweethome3d-desktop` (Xvnc + XFCE + SH3D-Autostart) + `novnc` Web-Desktop (`:6080`)

## Schnellstart (Proxmox-Host)

Einzeiler auf dem Proxmox-Host als root — erstellt automatisch die VM `3D-Home` mit nächster freier VMID (belegte IDs werden übersprungen):

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/proxmox/create-vm.sh)"
```

Optional mit Wunsch-ID / eigenem Namen (belegt → nächste frei wird genommen):

```bash
VM_ID=200 VM_NAME=3D-Home bash -c "$(wget -qLO - https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/proxmox/create-vm.sh)"
```

## Innen-Setup (in der VM)
1. Als root in der VM:

```bash
curl -fsSL -o sweethome3d-mcp-install.sh https://raw.githubusercontent.com/HatchetMan111/SweetHome3D-MCP-Proxmox-Server/main/install/sweethome3d-mcp-install.sh
chmod +x sweethome3d-mcp-install.sh
bash sweethome3d-mcp-install.sh
# optional mit eigenem Passwort:
# VNCPASS=meinpass bash sweethome3d-mcp-install.sh
```

2. Am Ende zeigt das Script:

```
Weboberfläche (Browser): http://VM-IP:6080/vnc.html
VNC-Client:              VM-IP:5901
MCP-Server:              http://VM-IP:9877/mcp
```

## opencode verbinden

Auf deinem Rechner (nicht in der VM) in `~/.config/opencode/opencode.json`
— Beispiel in `opencode.example.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "sweethome3d-vm": {
      "type": "remote",
      "url": "http://VM-IP:9877/mcp",
      "enabled": true
    }
  }
}
```

Danach opencode neu starten. Erst in SH3D ein Home öffnen/erstellen, dann
per AI steuern (`get_state`, Wände, Möbel, `export_plan_image`, `render_photo`).

> Sicherheit: Der MCP-Port hat keine Auth. Nicht direkt ins Internet!
> Nur via VPN / Tailscale / WireGuard oder SSH-Tunnel:
> `ssh -L 9877:localhost:9877 root@VM-IP` → dann `http://localhost:9877/mcp` nutzen.
> Siehe `SECURITY.md`.

## Quellen / Lizenzen

- Sweet Home 3D © eTeks — Downloads von SourceForge, Lizenz beim Hersteller.
- MCP-Plugin © grimashevich — GPL-2.0, https://github.com/grimashevich/sweethome3d-mcp-server
- Eigene Scripts in diesem Repo: MIT, siehe `LICENSE`. Details in `NOTICE.md`.
