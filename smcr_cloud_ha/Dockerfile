ARG BUILD_FROM
FROM ${BUILD_FROM}

# Instala dependências do sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    mariadb-server \
    supervisor \
    jq \
    libpng-dev \
    libzip-dev \
    unzip \
    python3 \
    python3-zeroconf \
    && rm -rf /var/lib/apt/lists/*

# Instala extensões PHP necessárias
RUN docker-php-ext-install pdo pdo_mysql mysqli

# Habilita módulos Apache
RUN a2enmod rewrite headers

# Desabilita o site padrão do Apache
RUN a2dissite 000-default || true

# Copia arquivos do rootfs (configurações Apache, supervisord, MySQL)
COPY rootfs/ /

# Habilita o site SMCR
RUN a2ensite smcr

# Cria diretório runtime para o MariaDB
RUN mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

# Copia a aplicação PHP
COPY app/ /var/www/html/
RUN chown -R www-data:www-data /var/www/html

# Copia e habilita o script de inicialização
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
