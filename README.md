# SMCR HA — Add-on para Home Assistant

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Add-on para Home Assistant que empacota o **SMCR Cloud** como container Docker, permitindo gerenciar dispositivos ESP32 com firmware [SMCR](https://github.com/rede-analista/SMCR) diretamente pelo Home Assistant via Ingress.

Faz parte do ecossistema SMCR:

| Projeto | Descrição |
|---------|-----------|
| [SMCR](https://github.com/rede-analista/SMCR) | Firmware ESP32 |
| [SMCR_CLOUD](https://github.com/rede-analista/SMCR_CLOUD) | Painel web standalone |
| **SMCR_HA** | Este add-on — painel integrado ao Home Assistant |

---

## Funcionalidades

- Painel web completo de gerenciamento de dispositivos SMCR acessível via Ingress do HA
- Cadastro e ativação de dispositivos ESP32
- Visualização de status em tempo real (heartbeat, última sincronização)
- Sincronização de configuração de pinos e ações entre o painel e o ESP32
- Suporte a MQTT com auto-discovery do Home Assistant
- Comunicação HTTPS direta com o ESP32 via porta dedicada
- Migração automática do banco de dados a cada inicialização

---

## Requisitos

- Home Assistant OS ou Supervised
- Add-on Mosquitto MQTT Broker (para funcionalidades MQTT)
- Rede local com acesso aos dispositivos ESP32

---

## Instalação

1. No Home Assistant, acesse **Configurações → Add-ons → Loja de Add-ons**
2. Clique no menu **⋮** (canto superior direito) → **Repositórios**
3. Adicione a URL do repositório:
   ```
   https://github.com/rede-analista/SMCR_HA
   ```
4. Localize **SMCR HA** na loja e clique em **Instalar**
5. Configure as opções e clique em **Iniciar**

---

## Configuração

| Opção | Padrão | Descrição |
|-------|--------|-----------|
| `http_port` | `2082` | Porta HTTP (usada pelo Ingress do HA) |
| `https_port` | `2083` | Porta HTTPS para acesso direto do ESP32 |
| `db_password` | — | Senha do banco de dados interno |
| `admin_user` | — | Usuário administrador do painel |
| `admin_password` | — | Senha do administrador |
| `reset_on_start` | `false` | Recria o banco de dados ao iniciar (apaga todos os dados) |

> **Importante:** Altere `db_password` e `admin_password` para valores seguros antes de iniciar o add-on.

---

## Portas

| Porta | Protocolo | Uso |
|-------|-----------|-----|
| 2082 | HTTP | Acesso via Ingress do Home Assistant |
| 2083 | HTTPS | Acesso direto do firmware ESP32 (certificado autoassinado) |

No firmware SMCR, configure `cloud_port = 2083` e `cloud_use_https = true` para comunicação com este add-on.

---

## Diferenças em relação ao SMCR_CLOUD standalone

| Recurso | SMCR_CLOUD | SMCR_HA |
|---------|------------|---------|
| Acesso web | URL direta | Via Ingress do HA |
| Instalação | Servidor PHP/Apache | Add-on HA |
| Banco de dados | MySQL externo | SQLite/MySQL interno |
| Migração de banco | Manual | Automática no boot |

---

## Licença

[MIT](LICENSE) © Rede Analista
