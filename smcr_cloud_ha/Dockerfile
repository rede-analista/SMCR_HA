ARG BUILD_FROM
FROM ${BUILD_FROM}

# Instala Apache, PHP 8.2 e dependências do sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    php8.2 \
    php8.2-mysql \
    php8.2-gd \
    php8.2-zip \
    libapache2-mod-php8.2 \
    mariadb-server \
    supervisor \
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Habilita módulos Apache
RUN a2enmod rewrite headers php8.2

# Desabilita o site padrão do Apache (será substituído pelo smcr.conf)
RUN a2dissite 000-default || true

# Copia arquivos do rootfs (configurações Apache, supervisord, MySQL)
COPY rootfs/ /

# Habilita o site SMCR
RUN a2ensite smcr

# Cria diretório runtime para o MariaDB
RUN mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

# Copia a aplicação PHP do SMCR_CLOUD
COPY app/ /var/www/html/
RUN chown -R www-data:www-data /var/www/html

# Copia e habilita o script de inicialização
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
