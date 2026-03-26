#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# build.sh — Prepara e constrói a imagem Docker do add-on SMCR Cloud para HA
# ─────────────────────────────────────────────────────────────────────────────
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/../SMCR_CLOUD"
APP_DIR="${SCRIPT_DIR}/app"

echo "==> Sincronizando código PHP de ${SOURCE_DIR} para ${APP_DIR}..."

if [ ! -d "${SOURCE_DIR}" ]; then
    echo "ERRO: Diretório fonte não encontrado: ${SOURCE_DIR}"
    echo "Certifique-se que o projeto SMCR_CLOUD está em ../SMCR_CLOUD"
    exit 1
fi

# Copia o projeto PHP (exceto arquivos desnecessários no container)
rsync -av --delete \
    --exclude='.git' \
    --exclude='*.md' \
    --exclude='LICENSE' \
    --exclude='data_files/' \
    "${SOURCE_DIR}/" "${APP_DIR}/"

echo "==> Construindo imagem Docker..."
docker build \
    --tag "local/smcr_cloud:latest" \
    --build-arg BUILD_FROM="php:8.2-apache" \
    "${SCRIPT_DIR}"

echo ""
echo "==> Build concluído: local/smcr_cloud:latest"
echo ""
echo "Para testar localmente (sem HA):"
echo "  docker run --rm -it \\"
echo "    -v \$(pwd)/test_data:/data \\"
echo "    -p 8765:8765 \\"
echo "    local/smcr_cloud:latest"
