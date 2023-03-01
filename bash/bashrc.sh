#!/bin/bash

export MYSQL_SERVER="172.16.238.12";
export ELASTIC_SERVER="172.16.238.26";
export MYSQL_USER="root";
export MYSQL_PASSWORD="root";
export ADMIN_USER="s.tonev";
export ADMIN_PASSWORD="Qwerty_2_Qwerty";
export DEPLOY_LANGUAGES="bg_BG en_US";
export GITHUB_USER="stiliyantonev";

alias magento_access='chmod -R 777 {var,generated,pub,vendor,app/etc}';
alias cache='php bin/magento c:c; php bin/magento c:f; magento_access';
alias rebuild='magento_rebuild';
alias update='composer_update && rebuild';
alias mysql="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_SERVER ";
alias mysqldump="mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_SERVER ";
alias mkdir='mkdir -p';
alias magento_logs='tail var/log/* ';
alias magento_update='update';
alias magento_cache='cache';
alias magento_disable_cache='php bin/magento cache:disable';
alias magento_admin_url='php bin/magento info:adminuri';

current_dir_name() {
	echo "${PWD##*/}";
}

# Tries to install using ComposerV2. If fails, tries with ComposerV1. If fails again print error. 
# Always returns to ComposerV2.
composer_install() {
	composer self-update --2;
	composer install;
	if [ $? -ne 0 ]; then
		echo "ComposerV2 install failed. Trying with ComposerV1";
		composer self-update --1;
		composer install;
		if [ $? -ne 0 ]; then
			echo "Both composer versions failed. Returning to ComposerV2";
			composer self-update --2;
			exit 1;	
		fi;
		composer self-update --2;
	fi;
}

# Tries to update using ComposerV2. If fails, tries with ComposerV1. If fails again print error. 
# Always returns to ComposerV2.
composer_update() {
	composer self-update --2;
	composer update;
	if [ $? -ne 0 ]; then
		echo "ComposerV2 install failed. Trying with ComposerV1";
		composer self-update --1;
		composer update;
		if [ $? -ne 0 ]; then
			echo "Both composer versions failed. Returning to ComposerV2";
			composer self-update --2;
			exit 1;	
		fi;
		composer self-update --2;
	fi;
}

magento_whitelist () {
	for module in $(find app/code -maxdepth 2 -type d -not -empty); do
		if [ -f "$module/etc/db_schema.xml" ]; then
			if [ ! -f "$module/etc/db_schema_whitelist.json" ]; then
				moduleName=$(echo "$module" | awk -F '/' 'NF == 4 {print $3 "_" $4}');
				echo "$moduleName";
				php bin/magento setup:db-declaration:generate-whitelist --module-name="$moduleName";
			fi;
		fi;
	done;
}
magento_rebuild () {
	rm -fr generated/code/*;
	chmod -R 777 generated;
	# Only rebuild if required.
	if [ "$(php bin/magento setup:db:status --no-ansi)" != "All modules are up to date." ]; then
		magento_whitelist;
		php bin/magento setup:upgrade;
	fi;
	php bin/magento setup:di:compile;
	magento_deploy_themes;
	cache;
}

# Set Url For Admin.
magento_set_adminurl () {
	php bin/magento setup:config:set --backend-frontname "$1" -n;
}
magento_modules_enable () {
	php bin/magento module:enable $(php bin/magento module:status | grep "$1");
}
magento_modules_disable () {
	php bin/magento module:disable $(php bin/magento module:status | grep "$1");
}

# Create Admin User. First argument will be used as username.
magento_user () {
	if [ -z "$1" ]; then
		echo "This function expects one(1) parameter.";
		echo "The suplied parameter will be used as username, firstname, last name and during email as follows.";
		echo "[param]@mailinator.com";
		echo "Please supply a username/parameter.";
		exit;
	fi;
	php bin/magento admin:user:create --admin-user "$1" --admin-password "Qwerty_2_Qwerty" --admin-email "$1@mailinator.com" --admin-firstname="$1" --admin-lastname="$1";
}
magento_data () {
	php bin/magento indexer:reindex;
	php bin/magento cron:run;
}

# Disable CSS/JS versioning.
magento_disable_sign() {
	if [ -z "$1" ]; then
		database="$(current_dir_name)";
	else
		database="$1";
	fi;
	mysql -e "insert into $database.core_config_data (config_id, scope, scope_id, path, value) values (null, 'default', 0, 'dev/static/sign', 0);" 2> /dev/null;
	if [ $? == 1 ]; then
		echo "Row already exists: Updating ...";
		mysql -e "update $database.core_config_data set value = 0 where path = 'dev/static/sign';";
	fi;
}

# Get/Print only frontend themes.
# If we have custom print only them, else print the default ones.
magento_frontend_themes () {
	counter=0;
	for themes in $(find app/design/frontend/ -maxdepth 2 -type d -not -empty -not -name "luma" -not -name "blank");do 
		echo $("$themes" | awk -F '/' 'NF == 5 {print $4 "/" $5}');
		counter=$((counter+1));
	done;
	if [ $counter -eq 0 ]; then
		echo "Did not find custom themes. Deploying blank & luma:";
		for themes in $(find app/design/frontend/ -maxdepth 2 -type d -not -empty);do 
			echo $(echo "$themes"| awk -F '/' 'NF == 5 {print $4 "/" $5}');
		done;
	fi;
}

# Get/Print only backend themes.
magento_backend_themes () {
	for themes in $(find app/design/adminhtml/ -maxdepth 2 -type d -not -empty);do 
		echo $(echo "$themes"| awk -F '/' 'NF == 5 {print $4 "/" $5}'); 
	done;
}
magento_projects () {
	for themes in $(find /shared/httpd/ -mindepth 1 -maxdepth 1 -type d -not -empty);do
		project="${themes##*/}";
		if [ -f "$themes/$project/bin/magento" ]; then
			echo $project;
		fi;
	done;
}

# Deploy both frontend & backend themes.
magento_deploy_themes () {
	failure=0;

	# Frontend Themes
	for theme in $(magento_frontend_themes); do
		php bin/magento setup:static-content:deploy -f --area frontend --theme "$theme" --no-parent $DEPLOY_LANGUAGES;
		if [ $? -ne 0 ]; then
			failure=1;
		fi;
	done;
	if [ $failure -eq 1 ]; then
		for theme in $(magento_frontend_themes); do
			php bin/magento setup:static-content:deploy -f --area frontend --theme "$theme" $DEPLOY_LANGUAGES;
		done;
	fi;

	# Backend Themes
	for theme in $(magento_backend_themes); do
		php bin/magento setup:static-content:deploy -f --area adminhtml --theme "$theme" --no-parent $DEPLOY_LANGUAGES;
	done;
	if [ $failure -eq 1 ]; then
		for theme in $(magento_backend_themes); do
			php bin/magento setup:static-content:deploy -f --area frontend --theme "$theme" $DEPLOY_LANGUAGES;
		done;
	fi;
}

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
		if [[ -d "/shared/https/$1" ]]; then
			cd "$1";
		else
			mkdir "$1";
			cd "$1"  || exit;
		fi;		
		git clone "$2" "$1";
	fi;
	
	cd "/shared/httpd/$1/$1"  || exit;
	# If composer.lock exists 'composer install' *might* throw an error.
	if [[ -f "composer.lock" ]]; then
		rm "composer.lock";
	fi;
	mysql -e "CREATE DATABASE IF NOT EXISTS $1";
	composer_install;

	if [ $? -ne 0 ]; then
		echo "Composer install failed. Please check the error.";
		exit;
	fi;
	
	# In most cases this module is missing pub folder.
	if [[ -f "app/code/Amasty/Xsearch" ]]; then
		if [[ ! -f "app/code/Amasty/Xsearch/pub" ]]; then
			mkdir app/code/Amasty/Xsearch/pub;
		fi;
	fi;
	# In most cases this module is missing pub folder.
	if [[ -f "app/code/Amasty/Shopby" ]]; then
		if [[ ! -f "app/code/Amasty/Shopby/pub" ]]; then
			mkdir app/code/Amasty/Shopby/pub;
		fi;
	fi;
	
	# Sleep, cause its too quick to notice the changes sometimes.
	sleep 2;
	# Disable modules that DO NOT contain Magento in them.
	php bin/magento module:disable $(php bin/magento module:status | grep -v "Magento\|List of");

	# Install project
	php bin/magento setup:install \
		--admin-firstname="Admin" --admin-lastname="Admin" \
		--admin-password="$ADMIN_PASSWORD" --admin-email="s.tonev@beluga.software" --admin-user="$ADMIN_USER" \
		--db-password="$MYSQL_PASSWORD" --db-host="$MYSQL_SERVER" --db-user="$MYSQL_USER" --db-name="$1" \
		--elasticsearch-host="$ELASTIC_SERVER" --use-rewrites=1;
	if [ $? -ne 0 ]; then
		echo "Magento install failed. Please check the error.";
		exit;
	fi;

	magento_rebuild;
	
	# Enable non-default & rebuild again.
	magento_disable_cache;
	magento_disable_sign "$1";

	# Enable modules that DO NOT contain Magento in them.
	php bin/magento module:enable $(php bin/magento module:status | grep  -v "Magento\|List of");
	magento_rebuild;
	
	# devilbox specific.
	cd .. || exit;
	ln -s "$1/pub" htdocs
}
magento_dump () {
	if [ -z "$1" ]; then
		echo "Did not find expected parameter: project/database name.";
		database="$(current_dir_name)";
		echo "Attempting dump with database: $database";
	else
		database="$1";
	fi;
	mysqldump "$database" > "dump.$database.sql";
}
magento_restore () {
	if [ -z "$2" ]; then
		database="$(current_dir_name)";
		restore_file="$1";
	else
		database="$1";
		restore_file="$2";
	fi;
	 
	sed -i "s/COLLATE=utf8mb4_0900_ai_ci//g" "$restore_file";
	mysql "$database" < "$restore_file";
	mysql -e "update $database.core_config_data set value = '$ELASTIC_SERVER' where path like '%elastic%server_host%';";
	mysql -e "update $database.core_config_data set value = 'http://$database.loc/' where path like '%base_url';";
	mysql -e "update $database.core_config_data set value = 'http://$database.loc/static/' where path like '%base_static_url';";
	mysql -e "update $database.core_config_data set value = 'http://$database.loc/media/' where path like '%base_media_url';";
	magento_disable_sign "$database";
	magento_cache;
}
update_github_token () {
	new_link="https://$GITHUB_USER:$1@github.com/belugait";
	for project in $(magento_projects); do
		if [ -d "/shared/httpd/$project/$project" ]; then
			repoFull="$(git -C "/shared/httpd/$project/$project" remote -v)";
			repoFull="${repoFull##*/}";
			repo="$(echo "$repoFull" | awk -F "." "{print $1}")";
			git -C "/shared/httpd/$project/$project" remote set-url origin "$new_link/$repo.git";
		fi;
	done;
}

echo "=========================================================================================================";
echo "Greetings, this shell has a few shortcuts related to Magento 2 development.";
echo "You can write 'magento' and hit [TAB] twice to see them.";
echo "=========================================================================================================";