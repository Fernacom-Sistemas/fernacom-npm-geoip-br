#!/usr/bin/env python3
"""Add a commented GeoIP example to NPM Proxy Hosts via the administrative API.

Default: read-only preview. --apply writes only when explicitly requested.
Set NPM_TOKEN in environment. Requires NPM_API_URL (default http://127.0.0.1:81).
"""
import argparse
import json
import os
import pathlib
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone

MARKER = "# FERNACOM - GEOIP BRASIL (DESATIVADO)"
BLOCK = """# ============================================
# FERNACOM - GEOIP BRASIL (DESATIVADO)
# Remova os # das 3 linhas abaixo para ativar.
# if ($fernacom_bloquear_geo) {
#     return 403;
# }
# ============================================"""
FIELDS = (
    "domain_names", "forward_scheme", "forward_host", "forward_port",
    "access_list_id", "certificate_id", "ssl_forced", "caching_enabled",
    "block_exploits", "allow_websocket_upgrade", "http2_support",
    "hsts_enabled", "hsts_subdomains", "enabled", "locations", "meta",
)
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Write via NPM API; default is preview")
    parser.add_argument("--backup-dir", default="/data/geoip-br/backups")
    args = parser.parse_args()
    os.umask(0o077)
    token = os.environ.get("NPM_TOKEN")
    if not token:
        sys.exit("ERRO: defina NPM_TOKEN (token administrativo obtido no NPM).")
    base = os.environ.get("NPM_API_URL", "http://127.0.0.1:81").rstrip("/")
    if not (base.startswith("http://127.0.0.1:") or base.startswith("http://localhost:") or base.startswith("https://")):
        sys.exit("ERRO: use endpoint local ou HTTPS para não expor o token.")
    def request(method, path, data=None):
        url = base + "/api" + path
        payload = None if data is None else json.dumps(data).encode("utf-8")
        headers = {"Authorization": "Bearer " + token, "Accept": "application/json"}
        if payload is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=payload, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=20) as response:
            return json.load(response)
    hosts = request("GET", "/nginx/proxy-hosts")
    if not isinstance(hosts, list):
        sys.exit("ERRO: resposta inesperada da API; nenhuma alteração.")
    candidates = []
    for host in hosts:
        if not isinstance(host, dict) or "id" not in host:
            sys.exit("ERRO: host inesperado; nenhuma alteração.")
        advanced = host.get("advanced_config") or ""
        if not isinstance(advanced, str):
            sys.exit("ERRO: advanced_config inesperado; nenhuma alteração.")
        if MARKER in advanced or "$fernacom_bloquear_geo" in advanced:
            print(f"Host {host['id']}: já contém GeoIP; ignorado")
            continue
        missing = [field for field in FIELDS[:4] if field not in host]
        if missing:
            sys.exit(f"ERRO: host {host['id']} sem campos {missing}; nenhuma alteração.")
        candidates.append(host)
        print(f"Host {host['id']} ({', '.join(host.get('domain_names', []))}): {'aplicar' if args.apply else 'prévia'}")
    print(f"Hosts a atualizar: {len(candidates)}")
    if not args.apply or not candidates:
        print("Nenhuma alteração realizada. Use --apply após revisar a prévia.")
        return
    directory = pathlib.Path(args.backup_dir)
    directory.mkdir(parents=True, exist_ok=True)
    backup = directory / ("npm-proxy-hosts-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ".json")
    with backup.open("x", encoding="utf-8") as file:
        json.dump(hosts, file, ensure_ascii=False, indent=2)
    os.chmod(backup, 0o600)
    print(f"Backup dos dados originais: {backup}")
    for host in candidates:
        host_id = int(host["id"])
        current = request("GET", f"/nginx/proxy-hosts/{host_id}")
        if current.get("advanced_config") != host.get("advanced_config") or current.get("domain_names") != host.get("domain_names"):
            sys.exit(f"ERRO: host {host_id} alterado desde a prévia; interrompendo.")
        if "$fernacom_bloquear_geo" in (current.get("advanced_config") or ""):
            print(f"Host {host_id}: GeoIP já presente; preservado")
            continue
        # Explicit allowlist: do not send id, owner, created_on, modified_on,
        # certificate object or other read-only fields back to the API.
        payload = {key: current[key] for key in FIELDS if key in current}
        advanced = current.get("advanced_config") or ""
        payload["advanced_config"] = advanced.rstrip() + ("\n\n" if advanced.strip() else "") + BLOCK + "\n"
        request("PUT", f"/nginx/proxy-hosts/{host_id}", payload)
        check = request("GET", f"/nginx/proxy-hosts/{host_id}")
        if check.get("advanced_config") != payload["advanced_config"]:
            sys.exit(f"ERRO: API não confirmou atualização do host {host_id}.")
        print(f"Host {host_id}: bloco comentado inserido e confirmado")
    print("Concluído. Hosts com GeoIP preexistente foram preservados; novos blocos estão comentados.")
if __name__ == "__main__":
    try:
        main()
    except (urllib.error.URLError, ValueError, KeyError) as error:
        sys.exit(f"ERRO: {error}")
