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
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Habilita módulos Apache
RUN a2enmod rewrite headers php8.2

# Desabilita o site padrão do Apache
RUN a2dissite 000-default || true

# Copia arquivos do rootfs (Apache, MySQL, cont-init.d, services.d)
COPY rootfs/ /

# Habilita o site SMCR e torna scripts executáveis
RUN a2ensite smcr \
    && chmod a+x /etc/cont-init.d/*.sh \
    && chmod a+x /etc/services.d/mariadb/run \
    && chmod a+x /etc/services.d/apache2/run

# Cria diretório runtime para o MariaDB
RUN mkdir -p /run/mysqld && chown mysql:mysql /run/mysqld

# Copia a aplicação PHP
COPY app/ /var/www/html/
RUN chown -R www-data:www-data /var/www/html
