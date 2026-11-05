# FERNACOM NPM GeoIP Brasil

Controle geográfico para **Proxy Hosts selecionados** do Nginx Proxy Manager, usando redes IPv4/IPv6 brasileiras do IPdeny. Projeto independente da **FERNACOM Informática Corporativa**.

> **Versão inicial / teste em homologação obrigatório.** Baseado na implantação da Bluesea Catering (NPM 2.10.3, OpenResty). Ainda não homologado em instalações limpas ou em Docker.

## Política de preservação\n\n- GeoIP **ativo**: manter exatamente como está.\n- GeoIP **comentado**: manter exatamente como está.\n- Sem GeoIP: inserir bloco comentado **somente após autenticação e `--apply`**.\n- O instalador configura apenas as variáveis globais; **não altera os Proxy Hosts automaticamente**.\n- Reexecutar o anotador permite incluir hosts criados posteriormente.\n\n## Instalação

Execute **no ambiente onde o NPM/OpenResty roda**, com root, Bash, Python 3, curl, nginx e acesso a `/data`. Faça backup completo do NPM (`/data`, banco de dados e certificados).

```bash
git clone https://github.com/Fernacom-Sistemas/fernacom-npm-geoip-br.git
cd fernacom-npm-geoip-br
sudo bash scripts/install.sh
```

Em Docker, o script deve rodar **dentro do contêiner**, caso ele tenha as dependências. Não execute no host Docker sem adaptar a instalação. O script **não ativa o bloqueio em nenhum domínio**. Se encontrar regras FERNACOM existentes, interrompe para exigir migração manual.

## Ativação por domínio

NPM → **Hosts → Proxy Hosts → Edit → Advanced**. Preserve as configurações existentes e acrescente **somente no host escolhido**:

```nginx
# FERNACOM - GeoIP Brasil
if ($fernacom_bloquear_geo) {
    return 403;
}
```

Salve, execute `nginx -t` e teste de uma conexão brasileira **externa** (resposta normal) e estrangeira (HTTP 403). Testar no próprio NPM não prova o bloqueio: NAT loopback pode chegar com IP privado.


## Inserir o bloco comentado em todos os Proxy Hosts

O script `scripts/annotate-hosts.py` utiliza a **API administrativa do NPM** para acrescentar o exemplo comentado na aba **Advanced** de todos os Proxy Hosts existentes, sem apagar o conteúdo anterior. Não edita diretamente o banco de dados nem os arquivos gerados pelo NPM.

**Por segurança, esta etapa exige autenticação administrativa e a opção explícita `--apply`**; o instalador básico não modifica os hosts. Não compartilhe senhas nem tokens. Execute no próprio LXC do NPM:

```bash
cd /fernacom-npm-geoip-br
source scripts/auth.sh                    # solicita e-mail e senha sem exibi-los
python3 scripts/annotate-hosts.py          # prévia, somente leitura
python3 scripts/annotate-hosts.py --apply  # somente após conferir a prévia
unset NPM_TOKEN
```

Antes de executar `--apply`, faça backup completo do NPM. O script também grava um JSON dos hosts em `/data/geoip-br/backups/`, com permissão 600. Se a API retornar erro em algum host, interrompe a execução; hosts já alterados não são revertidos automaticamente. Revise o backup e o painel antes de tentar novamente.

O bloco inserido será:

```nginx
# ============================================
# FERNACOM - GEOIP BRASIL (DESATIVADO)
# Remova os # das 3 linhas abaixo para ativar.
# if ($fernacom_bloquear_geo) {
#     return 403;
# }
# ============================================
```

Para ativar em um domínio, remova apenas os `#` das três linhas do `if` e salve. O script ignora hosts que já contêm `$fernacom_bloquear_geo`, **mesmo se o bloqueio estiver ativo**: não comenta, não desativa, não duplica e não altera esses hosts. Para hosts sem GeoIP, adiciona somente um exemplo comentado. **Teste primeiro em um NPM de homologação**: a estrutura da API pode variar conforme a versão.

## Atualização

```bash
sudo bash scripts/update.sh
```

O script busca listas IPv4/IPv6 no IPdeny, valida CIDRs e volume mínimo, cria backup, testa o Nginx e recarrega. Se a validação ou o reload falhar, tenta restaurar a lista anterior.

Depois de homologar, exemplo de agendamento semanal:

```cron
15 4 * * 1 /bin/bash /caminho/absoluto/fernacom-npm-geoip-br/scripts/update.sh >> /var/log/fernacom-geoip.log 2>&1
```

## Arquivos instalados

- `/data/geoip-br/br-allow.conf` — lista brasileira e exceções privadas
- `/data/geoip-br/backups/` — backups
- `/data/nginx/custom/fernacom-geoip-br.conf` — variáveis `geo` e `map`
- `/data/nginx/custom/http_top.conf` — inclui o arquivo gerenciado

## Reversão

1. Remova a regra `if ($fernacom_bloquear_geo) { return 403; }` do **Advanced** de todos os Proxy Hosts e salve.
2. Confirme que nenhum host depende das variáveis.
3. Remova o `include /data/nginx/custom/fernacom-geoip-br.conf;` de `http_top.conf`.
4. Valide `nginx -t` e recarregue `nginx -s reload`. Preserve backups até confirmar estabilidade.

Não edite apenas `/data/nginx/proxy_host/*.conf`, pois o NPM regenera esses arquivos.

## Segurança e limitações

- O filtro usa `$realip_remote_addr`, IP original do socket. **Atrás de CDN, balanceador ou proxy intermediário**, pode classificar o intermediário, não o visitante.
- A classificação geográfica não é infalível. VPNs podem contornar a regra e alguns IPs brasileiros podem ser negados.
- As exceções locais `10/8`, `172.16/12`, `192.168/16`, `127/8`, `::1` são permitidas por padrão; revise a topologia.
- O caminho `/.well-known/acme-challenge/` é isento da regra geográfica. **Teste a renovação real** de certificados; o NPM pode redirecionar HTTP para HTTPS.
- Restringe apenas HTTP/HTTPS dos Proxy Hosts selecionados; não cobre SMTP, IMAP, POP3 ou portas independentes.
- Não substitui MFA, VPN, firewall, atualizações de segurança ou resposta a comprometimento.
- O projeto pressupõe caminhos padrão `/data`; `DATA_DIR` alternativo é recusado.
- A atualização depende das fontes externas IPdeny. Monitore logs do cron e evite atualizações automáticas sem homologação.

## Licença

MIT — © 2026 FERNACOM Informática Corporativa.
