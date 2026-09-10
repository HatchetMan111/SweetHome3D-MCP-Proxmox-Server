# Security

## MCP-Port hat keine Authentifizierung

Der Sweet Home 3D MCP-Server auf Port `9877` spricht unverschlüsseltes
HTTP ohne Login. Stelle ihn **niemals** direkt ins Internet.

Empfohlen:

1. Proxmox-Firewall / VM-Firewall: nur LAN/VPN erlauben.
2. Fernzugriff via VPN (WireGuard/Tailscale) oder SSH-Tunnel:

```bash
ssh -L 9877:localhost:9877 root@VM-IP
# dann in opencode: http://localhost:9877/mcp
```

3. noVNC (`6080`) ebenfalls nicht öffentlich ohne Schutz lassen —
   starkes VNC-Passwort setzen (`VNCPASS=...`), ggf. hinter Reverse-Proxy
   mit Basic-Auth.

## Token-Hygiene

Keine Personal-Access-Tokens in Issues, Logs oder Scripts committen.
Falls ein Token versehentlich öffentlich wurde: sofort auf GitHub
(Settings → Developer settings → Personal access tokens) widerrufen
und neu erstellen.
