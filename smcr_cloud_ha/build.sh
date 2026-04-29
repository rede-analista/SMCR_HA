#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh — Prepara e constrói a imagem Docker do add-on SMCR Cloud para HA
# ─────────────────────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${SCRIPT_DIR}/app"

# Localiza SMCR_CLOUD: primeiro ../SMCR_CLOUD (estrutura padrão do repo),
# depois ~/OneDrive/Desenvolvimento/SMCR_CLOUD (estrutura local de dev)
if [ -d "${SCRIPT_DIR}/../SMCR_CLOUD" ]; then
    SOURCE_DIR="${SCRIPT_DIR}/../SMCR_CLOUD"
elif [ -d "${HOME}/OneDrive/Desenvolvimento/SMCR_CLOUD" ]; then
    SOURCE_DIR="${HOME}/OneDrive/Desenvolvimento/SMCR_CLOUD"
else
    echo "ERRO: Diretório SMCR_CLOUD não encontrado."
    echo "  Tentado: ${SCRIPT_DIR}/../SMCR_CLOUD"
    echo "  Tentado: ${HOME}/OneDrive/Desenvolvimento/SMCR_CLOUD"
    exit 1
fi

echo "==> Sincronizando código PHP de ${SOURCE_DIR} para ${APP_DIR}..."

# Copia o projeto PHP (exceto arquivos desnecessários no container)
rsync -av --delete \
    --exclude='.git' \
    --exclude='*.md' \
    --exclude='LICENSE' \
    --exclude='data_files/' \
    "${SOURCE_DIR}/" "${APP_DIR}/"

echo "==> Construindo imagem Docker..."
docker build \
    --tag "local/smcr_cloud_ha:latest" \
    --build-arg BUILD_FROM="php:8.2-apache" \
    "${SCRIPT_DIR}"

echo ""
echo "==> Build concluído: local/smcr_cloud_ha:latest"
echo ""
echo "Para testar localmente (sem HA):"
echo "  docker run --rm -it \\"
echo "    -v \$(pwd)/test_data:/data \\"
echo "    -p 8765:8765 \\"
echo "    local/smcr_cloud_ha:latest"
