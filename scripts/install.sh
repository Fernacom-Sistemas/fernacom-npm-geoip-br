#!/usr/bin/env bash
set -Eeuo pipefail
# Execute no mesmo ambiente do NPM/OpenResty; caminhos padrão /data.
if [[ "${DATA_DIR:-/data}" != "/data" ]]; then
  echo "ERRO: DATA_DIR alternativo não é suportado nesta versão." >&2; exit 1
fi
GEO_DIR=/data/geoip-br
CUSTOM_DIR=/data/nginx/custom
CONF="$CUSTOM_DIR/http_top.conf"
MANAGED="$CUSTOM_DIR/fernacom-geoip-br.conf"
BACKUP_DIR="$GEO_DIR/backups"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
for cmd in nginx curl python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERRO: falta $cmd" >&2; exit 1; }
done
[[ -d /data/nginx ]] || { echo "ERRO: /data/nginx não encontrado; execute dentro do NPM." >&2; exit 1; }
[[ ! -e "$MANAGED" ]] || { echo "ERRO: configuração gerenciada já existe; instalação interrompida." >&2; exit 1; }
if [[ -f "$CONF" ]] && grep -Eq 'fernacom_ip_brasil|fernacom_bloquear_geo|fernacom-geoip-br.conf' "$CONF"; then
  echo "ERRO: regras GeoIP existentes; migração manual necessária." >&2; exit 1
fi
nginx -t
mkdir -p "$GEO_DIR" "$CUSTOM_DIR" "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
HAD_CONF=0
if [[ -f "$CONF" ]]; then
  cp -p "$CONF" "$BACKUP_DIR/http_top.conf.$STAMP"
  HAD_CONF=1
fi
rollback() {
  if (( HAD_CONF )); then
    cp -p "$BACKUP_DIR/http_top.conf.$STAMP" "$CONF"
  else
    rm -f "$CONF"
  fi
  rm -f "$MANAGED"
  nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1 || true
}
"$SCRIPT_DIR/update.sh" --initial
cat > "$MANAGED" <<'NGINX'
# FERNACOM - GeoIP Brasil: contexto http
# IP original do socket; CDN e proxies intermediários requerem avaliação.
geo $realip_remote_addr $fernacom_ip_brasil {
    default 0;
    include /data/geoip-br/br-allow.conf;
}
map "$fernacom_ip_brasil:$uri" $fernacom_bloquear_geo {
    default 1;
    ~^1: 0;
    ~^0:/\.well-known/acme-challenge/ 0;
}
NGINX
printf '\n# FERNACOM - GeoIP Brasil (gerenciado)\ninclude /data/nginx/custom/fernacom-geoip-br.conf;\n' >> "$CONF"
if ! nginx -t || ! nginx -s reload; then
  echo "ERRO: validação ou reload falhou; revertendo configuração." >&2
  rollback
  exit 1
fi
echo "Instalação concluída. Nenhum Proxy Host foi bloqueado automaticamente."
echo 'No Advanced do host escolhido: if ($fernacom_bloquear_geo) { return 403; }'
