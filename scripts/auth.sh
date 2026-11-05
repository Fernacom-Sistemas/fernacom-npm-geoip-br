#!/usr/bin/env bash
# Use: source scripts/auth.sh
# Token fica apenas na sessão atual; não imprime credenciais.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Use: source scripts/auth.sh" >&2
  exit 1
fi
if [[ -z "${BASH_VERSION:-}" ]]; then
  echo "ERRO: execute em Bash." >&2
  return 1
fi
local_api="${NPM_API_URL:-http://127.0.0.1:81}"
case "$local_api" in
  http://127.0.0.1:*|http://localhost:*|https://*) ;;
  *) echo "ERRO: API remota exige HTTPS." >&2; return 1 ;;
esac
read -r -p "Email administrador NPM: " _npm_email
read -r -s -p "Senha administrador NPM: " _npm_password
printf '\n'
export _npm_email _npm_password local_api
_npm_token="$(python3 - <<'PY'
import json, os, sys, urllib.request
try:
    url=os.environ["local_api"].rstrip("/")+"/api/tokens"
    payload=json.dumps({"identity":os.environ["_npm_email"],"secret":os.environ["_npm_password"]}).encode()
    req=urllib.request.Request(url,data=payload,headers={"Content-Type":"application/json"},method="POST")
    with urllib.request.urlopen(req,timeout=20) as resp:
        token=json.load(resp).get("token")
    if not isinstance(token,str) or not token:
        raise ValueError("Resposta sem token")
    print(token)
except Exception as exc:
    print(f"Falha de autenticação: {type(exc).__name__}",file=sys.stderr)
    sys.exit(1)
PY
)"
_npm_status=$?
unset _npm_email _npm_password
if (( _npm_status != 0 )) || [[ -z "$_npm_token" ]]; then
  unset _npm_token local_api _npm_status
  return 1
fi
export NPM_API_URL="$local_api"
export NPM_TOKEN="$_npm_token"
unset _npm_token local_api _npm_status
echo "AUTENTICACAO: SUCESSO (token não exibido)"
