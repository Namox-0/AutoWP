#!/bin/bash

# Nombre : AutoWP
# Creador : wvverez
# Github : https://github.com/wvverez
# Instalación LAMP + WordPress Kubuntu / Ubuntu 24.04 / 26.04
# Usa los repositorios oficiales de Ubuntu (sin PPA de ondrej)

# Paleta Colores
RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
BLUE='\e[1;34m'
CYAN='\e[1;36m'
RESET='\e[0m'

export DEBIAN_FRONTEND=noninteractive
LOG="/var/log/autowp.log"

cleanup() {
    printf "\n${RED}[+] Abandonando el script ...${RESET}\n"
    exit 1
}
trap cleanup INT

# Ejecuta un comando enviando la salida al log y abortando si falla
run() {
    "$@" >>"$LOG" 2>&1 || {
        echo -e "${RED}[!] Error ejecutando: $*${RESET}"
        echo -e "${RED}[!] Revisa el log: $LOG${RESET}"
        exit 1
    }
}

printf "\n${BLUE}----------------------------------------------${RESET}\n"
printf "\n${BLUE}[+] Author: wvverez...${RESET}\n"
printf "\n${BLUE}[+] https://github.com/wvverez${RESET}\n"
printf "\n${BLUE}----------------------------------------------${RESET}\n"

# Variables
WP_DIR="MiWordpress"
DB_NAME="MiWordpress"
DB_USER="wpuser"
DB_PASS="Con_sena_2025!"

# Mirar si es root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[+] Este script debe ejecutarse como root (sudo)...${RESET}"
    exit 1
fi

: > "$LOG"
echo ""
echo -e "${CYAN}[+] Iniciando instalación LAMP + WordPress...${RESET}\n"

# Paso 1 Limpieza de PPA antiguo, actualización del sistema

echo -e "${BLUE}[1/9] Actualizando sistema y repositorios...${RESET}"
# Eliminar el PPA de ondrej si quedó de una ejecución anterior (da error 404 en Ubuntu 26.04)
rm -f /etc/apt/sources.list.d/ondrej-ubuntu-php-*.sources \
      /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list \
      /etc/apt/sources.list.d/ondrej-ubuntu-php-*.list.save
run apt-get update
run apt-get upgrade -y
echo -e "${GREEN}[+] Sistema actualizado${RESET}\n"

# Paso 2 Instalación Apache

echo -e "${BLUE}[2/9] Instalando Apache...${RESET}"
run apt-get install -y apache2 curl openssl
ufw allow http  >/dev/null 2>&1 || true
ufw allow https >/dev/null 2>&1 || true
run systemctl enable apache2
run systemctl restart apache2
echo -e "${GREEN}[+] Apache operativo${RESET}\n"

# Paso 3 Instalación MySQL

echo -e "${BLUE}[3/9] Instalando MySQL...${RESET}"
run apt-get install -y mysql-server
run systemctl enable mysql
run systemctl start mysql
echo -e "${GREEN}[+] MySQL en ejecución${RESET}\n"

# Paso 4 Instalación de PHP (versión de los repos oficiales) y extensiones

echo -e "${BLUE}[4/9] Instalando PHP y extensiones...${RESET}"
run apt-get install -y \
    php \
    libapache2-mod-php \
    php-mysql \
    php-cli \
    php-common \
    php-curl \
    php-xml \
    php-mbstring \
    php-zip \
    php-gd \
    php-soap \
    php-intl
run systemctl restart apache2
PHP_VER=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
echo -e "${GREEN}[+] PHP ${PHP_VER} listo${RESET}\n"

# Paso 5 Configuración DB

echo -e "${BLUE}[5/9] Configurando base de datos WordPress...${RESET}"
mysql >>"$LOG" 2>&1 <<EOF || { echo -e "${RED}[!] Error creando la base de datos (ver $LOG)${RESET}"; exit 1; }
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF
echo -e "${GREEN}[+] Base de datos creada${RESET}\n"

# Paso 6 Descarga WP

echo -e "${BLUE}[6/9] Descargando WordPress...${RESET}"
cd /tmp || exit 1
rm -rf /tmp/wordpress /tmp/latest.tar.gz
run curl -fsSL -o latest.tar.gz https://wordpress.org/latest.tar.gz
run tar -xzf latest.tar.gz
rm -rf "/var/www/html/${WP_DIR}"
mv wordpress "/var/www/html/${WP_DIR}"
rm -f latest.tar.gz
echo -e "${GREEN}[+] WordPress descargado${RESET}\n"

# Paso 7 Permisos (usuario por defecto de Apache)

echo -e "${BLUE}[7/9] Asignando permisos...${RESET}"
chown -R www-data:www-data "/var/www/html/${WP_DIR}"
find "/var/www/html/${WP_DIR}" -type d -exec chmod 755 {} \;
find "/var/www/html/${WP_DIR}" -type f -exec chmod 644 {} \;
echo -e "${GREEN}[+] Permisos aplicados${RESET}\n"

# Paso 8 VirtualHost Apache

echo -e "${BLUE}[8/9] Configurando Apache VirtualHost...${RESET}"
cat <<EOF > /etc/apache2/sites-available/${WP_DIR}.conf
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    DocumentRoot /var/www/html/${WP_DIR}
    ServerName localhost
    <Directory /var/www/html/${WP_DIR}>
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/${WP_DIR}_error.log
    CustomLog \${APACHE_LOG_DIR}/${WP_DIR}_access.log combined
</VirtualHost>
EOF
run a2dissite 000-default.conf
run a2ensite "${WP_DIR}.conf"
run a2enmod rewrite
run apache2ctl configtest
run systemctl reload apache2

# Herramientas para comprobar puertos
command -v ss >/dev/null 2>&1      || run apt-get install -y iproute2
command -v netstat >/dev/null 2>&1 || run apt-get install -y net-tools

echo -e "${BLUE}[+] Verificando estado de Apache...${RESET}"
systemctl status apache2 --no-pager | grep "Active:"

echo -e "${BLUE}[+] Verificando puerto 80...${RESET}"
ss -tuln | grep ':80 '

echo -e "${GREEN}[+] VH Apache configurado${RESET}\n"

# Paso 9 Configuración WP

echo -e "${BLUE}[9/9] Configurando WordPress...${RESET}"
cd "/var/www/html/${WP_DIR}" || exit 1
cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/${DB_NAME}/" wp-config.php
sed -i "s/username_here/${DB_USER}/" wp-config.php
sed -i "s/password_here/${DB_PASS}/" wp-config.php

# Claves y salts únicos
for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
    sed -i "s/'$k', *'put your unique phrase here'/'$k', '$(openssl rand -hex 32)'/" wp-config.php
done

chown www-data:www-data wp-config.php
chmod 640 wp-config.php
echo -e "${GREEN}[+] WordPress configurado${RESET}\n"

echo -e "${RED}=============================================${RESET}"
echo -e "${GREEN}[+] Instalación completada${RESET}"
echo -e "${YELLOW}[+] Accede a WordPress:${RESET}"
echo -e "${YELLOW}    http://localhost/wp-admin/install.php${RESET}"
echo -e "${YELLOW}[+] BD: ${DB_NAME} | Usuario: ${DB_USER} | Clave: ${DB_PASS}${RESET}"
echo -e "${YELLOW}[+] Log: ${LOG}${RESET}"
echo -e "${RED}=============================================${RESET}"
