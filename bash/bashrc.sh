# Bashrc folder
#
# 1. This folder will be mounted to /etc/bashrc-devilbox.d
# 2. All files ending by *.sh will be sourced by bash automatically
#    for the devilbox and root user.
#


# Add your custom vimrc and always load it with vim.
# Also make sure you add vimrc to this folder.
#!/bin/bash

export MYSQL_SERVER="172.16.238.12";
export ELASTIC_SERVER="172.16.238.26";
export MYSQL_USER="root";
export MYSQL_PASSWORD="root";
export ADMIN_USER="s.tonev";
export ADMIN_PASSWORD="Qwerty_2_Qwerty";

alias magento_access=' chmod -R 777 {var,generated,pub,vendor,app/etc}';
alias cache='php bin/magento c:c; php bin/magento c:f; magento_access';
alias rebuild='rm -fr generated/code/*; chmod -R 777 generated; php bin/magento setup:upgrade ;php bin/magento setup:di:compile; php bin/magento setup:static-content:deploy -f; cache';
alias update='composer update && rebuild';
alias mysql="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_SERVER ";
alias mysqldump="mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_SERVER ";
alias mkdir='mkdir -p';
alias magento_logs='tail var/log/* ';
alias magento_rebuild='rebuild';
alias magento_update='update';
alias magento_cache='cache';
alias magento_disable_cache='php bin/magento cache:disable';

magento_modules_enable () {
	php bin/magento module:enable $(php bin/magento module:status | grep "$1");
}
magento_modules_disable () {
	php bin/magento module:disable $(php bin/magento module:status | grep "$1");
}
magento_user () {
	php bin/magento admin:user:create --admin-user "$1" --admin-password "Qwerty_2_Qwerty" --admin-email "$1@mailinator.com" --admin-firstname="$1" --admin-lastname="$1";
}
magento_data () {
	php bin/magento indexer:reindex;
	php bin/magento cron:run;
}
magento_disable_sign() {
	if [ -z "$1" ]; then
		database="${PWD##*/}";
	else
		database="$1";
	fi;
	mysql -e "insert into $database.core_config_data (config_id, scope, scope_id, path, value) values (null, 'default', 0, 'dev/static/sign', 0);";
	if [ $? == 1 ]; then
		echo "Row already exists: Updating ...";
		mysql -e "update $database.core_config_data set value = 0 where path = 'dev/static/sign';";
	fi;
}
magento_themes () {
	echo $(find app/design/frontend -type d -maxdepth 2);
	#for a in $(find app/design/frontend/ -maxdepth 2 -type d -not -empty);do 
	#	echo $(echo "$a" | cut -d"/" -c 3-4); 
	#done;
}
#install_project agrina "https://stiliyantonev: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@github.com/belugait/agrina.git"
#install_project tnc "https://stiliyantonev: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@github.com/belugait/tnc.git"
magento_install() {
	# $1 project name.
	# $2 url
	
	if [ $# -ne 2 ]; then
		echo "Two(2) arguments are required.";
		echo "1. Name of the project.";
		echo "2. Url which will be git-clone'ed";
		echo "Please provide both arguments";
		exit;
	fi;
	
	cd /shared/httpd || exit;
	
	if [[ ! -d "$1/$1" ]]; then
		if [[ ! -d "$1" ]]; then
			mkdir "$1";
			cd "$1"  || exit;
		fi;		
		git clone "$2" "$1";
	fi;
	
	cd "/shared/httpd/$1/$1"  || exit;
	if [[ -f "composer.lock" ]]; then
		rm "composer.lock";
	fi;
	mysql -e "CREATE DATABASE IF NOT EXISTS $1";
	composer install;
	
	# In most cases this module is missing pub folder.
	if [[ ! -f "app/code/Amasty/Xsearch" ]]; then
	    mkdir app/code/Amasty/Xsearch/pub;
	fi;
	# In most cases this module is missing pub folder.
	if [[ ! -f "app/code/Amasty/Shopby" ]]; then
	    mkdir app/code/Amasty/Shopby/pub;
	fi;
	
	# Disable most non-default modules.
	php bin/magento module:disable $(php bin/magento module:status | grep "Mageplaza\|Amasty\|TwoFactor\|Beluga");
	sudo php bin/magento setup:install \
		--admin-firstname="Admin" --admin-lastname="Admin" \
		--admin-password="$ADMIN_PASSWORD" --admin-email="s.tonev@beluga.software" --admin-user="$ADMIN_USER" \
		--db-password="$MYSQL_PASSWORD" --db-host="$MYSQL_SERVER" --db-user="$MYSQL_USER" --db-name="$1" \
		--elasticsearch-host="$ELASTIC_SERVER" --use-rewrites=1;
	rebuild;
	
	# Enable non-default & rebuild again.
	magento_disable_cache;
	magento_disable_sign "$1";
	php bin/magento module:enable $(php bin/magento module:status | grep  "Mageplaza\|Amasty\|Beluga");
	rebuild;
	
	# devilbox specific.
	cd .. || exit;
	ln -s "$1/pub" htdocs
}
magento_dump () {
	mysqldump "$1" > "dump.$1.sql";
}
magento_restore () {
	if [ -z "$2" ]; then
		database="${PWD##*/}";
		mysql "$database" < "$1";
	else
		database="$1";
		mysql "$1" < "$2";
	fi;
	
	mysql -e "update $database.core_config_data set value = '$ELASTIC_SERVER' where path like '%elastic%server_host%';";
	mysql -e "update $database.core_config_data set value = 'http://$database.loc/' where path like '%base_url';";
	mysql -e "update $database.core_config_data set value = 'http://$database.loc/static/' where path like '%base_static_url';";
	mysql -e "update $database.core_config_data set value = 'http://$database.loc/media/' where path like '%base_media_url';";
}
