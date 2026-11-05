#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "${DATA_DIR:-/data}" != "/data" ]]; then
  echo "ERRO: DATA_DIR alternativo não é suportado nesta versão." >&2; exit 1
fi
GEO_DIR=/data/geoip-br
DEST="$GEO_DIR/br-allow.conf"
INITIAL=0
if [[ "${1:-}" == "--initial" ]]; then INITIAL=1
elif [[ $# -ne 0 ]]; then echo "Uso: $0 [--initial]" >&2; exit 2
fi
for cmd in curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERRO: falta $cmd" >&2; exit 1; }
done
if (( ! INITIAL )); then
  command -v nginx >/dev/null 2>&1 || { echo "ERRO: nginx ausente" >&2; exit 1; }
  [[ -f /data/nginx/custom/fernacom-geoip-br.conf ]] || {
    echo "ERRO: GeoIP ainda não instalado." >&2; exit 1;
  }
fi
mkdir -p "$GEO_DIR/backups"
TMP="$(mktemp -d "$GEO_DIR/.update.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT
curl -fSL --retry 3 --connect-timeout 15 --max-time 120 \
  'https://www.ipdeny.com/ipblocks/data/aggregated/br-aggregated.zone' -o "$TMP/ipv4"
curl -fSL --retry 3 --connect-timeout 15 --max-time 120 \
  'https://www.ipdeny.com/ipv6/ipaddresses/aggregated/br-aggregated.zone' -o "$TMP/ipv6"
python3 - "$TMP/ipv4" "$TMP/ipv6" "$TMP/output" <<'PY'
import ipaddress, sys
v4, v6, out = sys.argv[1:]
items=[]
counts={4:0,6:0}
for path, version in ((v4,4),(v6,6)):
    with open(path, encoding="utf-8") as f:
        for line in f:
            line=line.strip()
            if not line or line.startswith("#"): continue
            net=ipaddress.ip_network(line, strict=False)
            if net.version != version:
                raise ValueError(f"Versão IP inesperada: {line}")
            items.append(net)
            counts[version]+=1
if counts[4] < 1000 or counts[6] < 10:
    raise SystemExit(f"ERRO: listas suspeitas: IPv4={counts[4]}, IPv6={counts[6]}")
exceptions=["10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","127.0.0.0/8","::1/128"]
with open(out,"w",encoding="utf-8") as f:
    f.write("# FERNACOM - gerado automaticamente; não editar.\n")
    for net in exceptions: f.write(f"{net} 1;\n")
    for net in sorted(set(items),key=lambda n:(n.version,int(n.network_address),n.prefixlen)):
        f.write(f"{net} 1;\n")
print(f"IPv4: {counts[4]} | IPv6: {counts[6]} | exceções: {len(exceptions)}")
PY
if [[ -f "$DEST" ]] && cmp -s "$TMP/output" "$DEST"; then
  echo "GeoIP sem alterações."; exit 0
fi
STAMP="$(date +%Y%m%d-%H%M%S)"
OLD=0
if [[ -f "$DEST" ]]; then
  cp -p "$DEST" "$GEO_DIR/backups/br-allow.conf.$STAMP"
  OLD=1
fi
cp "$TMP/output" "$DEST"
if (( INITIAL )); then
  echo "Lista inicial instalada; nenhum bloqueio ativado."; exit 0
fi
restore() {
  if (( OLD )); then
    cp -p "$GEO_DIR/backups/br-allow.conf.$STAMP" "$DEST"
  else
    rm -f "$DEST"
  fi
}
if ! nginx -t; then
  restore
  echo "ERRO: nginx -t falhou; lista anterior restaurada." >&2; exit 1
fi
if ! nginx -s reload; then
  restore
  nginx -t && nginx -s reload || true
  echo "ERRO: reload falhou; lista anterior restaurada." >&2; exit 1
fi
echo "Lista atualizada e OpenResty recarregado."
