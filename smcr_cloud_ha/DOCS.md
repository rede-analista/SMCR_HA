# SMCR Cloud HA

Gerenciamento centralizado de dispositivos ESP32 com firmware SMCR, com suporte a MQTT e Home Assistant Discovery.

## Configuração

| Opção            | Padrão             | Descrição                                              |
|------------------|--------------------|--------------------------------------------------------|
| `port`           | `8765`             | Porta HTTP da interface web                            |
| `db_password`    | `smcr_secret_2024` | Senha do banco de dados MariaDB                        |
| `admin_user`     | `admin`            | Usuário administrador inicial                          |
| `admin_password` | `admin123`         | Senha do administrador inicial                         |
| `reset_on_start` | `false`            | Se `true`, apaga e recria o banco ao iniciar o add-on  |

> **Atenção:** Após o primeiro acesso, altere a senha do administrador em **Configurações → Alterar Minha Senha**.

## Acesso

O add-on aparece automaticamente na barra lateral do Home Assistant como **SMCR Cloud HA**. Também pode ser acessado diretamente pela porta configurada.

## Registro de dispositivos ESP32

Os ESP32 com firmware SMCR podem se registrar automaticamente ao ligar. Configure no firmware:

- **Endpoint:** `POST http://<ip-do-ha>:8765/api/register.php`
- **Token:** disponível em **Configurações → Token de Auto-Registro**

Payload enviado pelo ESP32:
```json
{
  "unique_id":        "smcr_A1B2C3D4E5F6",
  "register_token":   "seu_token_aqui",
  "hostname":         "esp32modularx",
  "ip":               "192.168.1.100",
  "port":             8080,
  "firmware_version": "2.1.2"
}
```

## Descoberta de dispositivos

Acesse **Dispositivos → Descobrir** para encontrar ESP32 na rede via mDNS ou varredura por range de IP.

O firmware SMCR deve anunciar via mDNS (`_http._tcp`) com os TXT records:
```
device_type = smcr
device      = SMCR
version     = 2.1.2
```

## Automação: descoberta periódica via Home Assistant

É possível configurar uma automação no HA para executar a descoberta mDNS automaticamente e registrar novos dispositivos sem intervenção manual.

### 1. Obtenha o token

No app SMCR Cloud → **Configurações → Token de Auto-Registro**, copie o token exibido.

### 2. Adicione ao `configuration.yaml` do Home Assistant

```yaml
rest_command:
  smcr_auto_discover:
    url: "http://127.0.0.1:8765/api/auto_discover.php"
    method: POST
    headers:
      Authorization: "Bearer SEU_TOKEN_AQUI"
    content_type: "application/json"
```

> Substitua `SEU_TOKEN_AQUI` pelo token copiado no passo anterior.

### 3. Crie a automação

Via interface do HA (YAML):
```yaml
automation:
  - alias: "SMCR - Descoberta automática de dispositivos"
    trigger:
      - platform: time_pattern
        minutes: "/30"
    action:
      - service: rest_command.smcr_auto_discover
```

A automação roda a cada 30 minutos, encontra ESP32 novos via mDNS e os registra automaticamente no SMCR Cloud. Dispositivos já cadastrados são ignorados.

O endpoint retorna:
```json
{
  "ok": true,
  "found": 2,
  "registered": 1,
  "skipped": 1,
  "errors": []
}
```

## Reset do banco de dados

Para apagar todos os dados e reiniciar do zero, defina `reset_on_start: true` nas configurações do add-on e reinicie. Após a reinicialização, defina novamente como `false`.
