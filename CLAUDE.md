# CLAUDE.md — SMCR_HA

## Regra de paridade obrigatória

**Tudo que for alterado no SMCR_HA DEVE ser replicado no SMCR_CLOUD e vice-versa.**
Única exceção: features exclusivas do Home Assistant (Ingress, db_migrate.sh, portas do addon).

---

## Estrutura do projeto

- Código PHP: `smcr_cloud_ha/app/`
- Config do addon: `smcr_cloud_ha/config.yaml`
- Migrations de banco: `smcr_cloud_ha/rootfs/usr/local/bin/db_migrate.sh`
- Porta HTTP (Ingress): **2082** | Porta HTTPS direto Apache: **2083**

---

## Regra crítica: db_migrate.sh

**Toda coluna nova adicionada ao schema.sql DEVE ter uma entrada `ADD COLUMN IF NOT EXISTS`
no `db_migrate.sh`.** Sem isso, instalações existentes do addon não recebem a coluna e
os INSERTs falham silenciosamente.

```bash
ALTER TABLE device_config ADD COLUMN IF NOT EXISTS nova_coluna TIPO DEFAULT valor;
```

**Por quê:** O schema.sql só é usado em instalações novas. Addons existentes só executam
db_migrate.sh no boot — se a migration não estiver lá, a coluna nunca é criada.

---

## Decisões arquiteturais — NÃO REVERTER

(As mesmas do SMCR_CLOUD — ver detalhes lá. Resumo dos pontos críticos:)

### `api/get_config.php` — campos cloud omitidos
`cloud_url`, `cloud_port`, `cloud_use_https` **não são retornados**.
Retorná-los sobrescreveria os valores corretos do ESP e quebraria a conexão.

### `api/register.php` — ativo=0 para novos devices
Novo device → `ativo=0`. Dispositivo existente → preserva `ativo` atual.
Com ativo=1, o próximo sync enviaria config zerada para o ESP.

### `api/register.php` — importa config completa do payload
Importa `cloud_port`, `cloud_use_https`, sync/heartbeat, `pins`, `actions`, `intermod_modules`.
O ESP (firmware v2.3.39+) envia tudo no registro — o servidor deve salvar tudo.

### `api/status.php` — ativo=0 retorna ignored
```json
{"ok": true, "ignored": true}
```
Não retornar 403 — o ESP não deve ver erro no heartbeat de um device inativo.

### `api/sync_device.php` — porta via COALESCE
```sql
COALESCE(ds.port, dc.web_server_port, 8080)
```
`device_status.port` (do heartbeat) tem prioridade sobre `web_server_port` (do cadastro).

---

## HA Ingress — padrão obrigatório de URLs

**hrefs, actions, redirects PHP:** usar `BASE` como prefixo.
**fetch() e URLs em JavaScript:** usar `BASE_PATH` como prefixo.

**Por quê:** O HA Ingress adiciona um prefixo dinâmico à URL (ex: `/api/hassio_ingress/xxx/`).
Sem o prefixo, todas as requisições resultam em 404 dentro do HA.

---

## Portas do addon

| Porta | Protocolo | Uso |
|-------|-----------|-----|
| 2082 | HTTP | Ingress do HA / acesso normal |
| 2083 | HTTPS | Acesso direto do ESP32 (certificado autoassinado) |

`cloud_port` default no schema.sql e db_migrate.sh: **2082**.

---

## Processo de release do addon

1. Editar código em `smcr_cloud_ha/app/`
2. Bump de versão em `smcr_cloud_ha/config.yaml`
3. Se adicionou coluna: atualizar `db_migrate.sh`
4. Commit + push
5. Atualizar o addon no Home Assistant (ele baixa a nova imagem automaticamente)

---

## Versão atual

v1.0.93 — commit `c17a22d`
