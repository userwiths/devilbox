# Bashrc folder
#
# 1. This folder will be mounted to /etc/bashrc-devilbox.d
# 2. All files ending by *.sh will be sourced by bash automatically
#    for the devilbox and root user.
#


# Add your custom vimrc and always load it with vim.
# Also make sure you add vimrc to this folder.

export MYSQL_SERVER="172.16.238.12";
export ELASTIC_SERVER="172.16.238.26";
export MYSQL_USER="root";
export MYSQL_PASSWORD="root";
export ADMIN_USER="s.tonev";
export ADMIN_PASSWORD="Qwerty_2_Qwerty";

alias magento_access=' chmod -R 777 {var,generated,pub,vendor,app/etc}';
alias rebuild='rm -fr generated/code/*; chmod -R 777 generated; php bin/magento setup:upgrade && php bin/magento setup:di:compile && php bin/magento setup:static-content:deploy -f && php bin/magento c:c && php bin/magento c:f && magento_access';
alias update='composer update && rebuild';
alias cache='php bin/magento c:c; php bin/magento c:f; magento_access';
alias mysqlconnect="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_SERVER ";
alias mkdir='mkdir -p';

install_project() {
	# $1 project name.
	# $2 url
	cd /shared/httpd;
	mkdir "$1";
	cd "$1";
	git clone "$2" "$1";
	cd "$1";
	mysqlconnect -e "create database $1";
	composer install;
	sudo php bin/magento setup:install \
		--admin-firstname="Admin" --admin-lastname="Admin" \
		--admin-password="$ADMIN_PASSWORD" --admin-email="s.tonev@beluga.software" --admin-user="$ADMIN_USERNAME" \
		--db-password="$MYSQL_PASSWORD" --db-host="$MYSQL_SERVER" --db-user="$MYSQL_USER" --db-name="$1" \
		--elasticsearch-host="$ELASTIC_SERVER" --use-rewrites=1;
	rebuild;
}
