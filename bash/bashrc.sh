#!/bin/bash

export MYSQL_SERVER="172.16.238.12";
export ELASTIC_SERVER="172.16.238.26";
export MYSQL_USER="root";
export MYSQL_PASSWORD="root";
export ADMIN_USER="s.tonev";
export ADMIN_PASSWORD="Qwerty_2_Qwerty";
export DEPLOY_LANGUAGES="bg_BG en_US";
export GITHUB_USER="username goes here";
export GITHUB_TOKEN="token goes here";
export GITHUB_ORGANIZATION="organization goes here";

alias echo="echo -e";
alias magento_access='chmod -R 777 {var,generated,pub,vendor,app/etc}';
alias cache='magento c:c; magento c:f; magento_access';
alias rebuild='magento_rebuild';
alias update='composer_exec update && rebuild';
alias mysql="mysql -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_SERVER ";
alias mysqldump="mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -h $MYSQL_SERVER ";
alias mkdir='mkdir -p';
alias magento_logs='tail var/log/* ';
alias magento_update='update';
alias magento_cache='cache';
alias magento_disable_cache='magento cache:disable';
alias magento_admin_url='magento info:adminuri';
alias magento="php bin/magento ";

git_ignore_chmod () {
	git config core.fileMode false;
}

current_dir_name() {
	echo "${PWD##*/}";
}

# Tries to install using ComposerV2. If fails, tries with ComposerV1. If fails again print error. 
# Always returns to ComposerV2.
composer_exec() {
	if [ "$1" != "install" ]; then
		if [ "$1" != "update" ]; then
			echo "Unrecognized argument $1.";
			echo "Expecting [install] or [update]";
			return 1;
		fi;
	fi;
	composer self-update --2;
	if ! composer $1; then
		echo "ComposerV2 install failed. Trying with ComposerV1";
		composer self-update --1;
		if ! composer $1; then
			echo "Both composer versions failed. Returning to ComposerV2";
			composer self-update --2;
			return 1;
		fi;
		composer self-update --2;
	fi;
}

# Can use the `jq` tool, but for starters will try a simple approach.
composer_verify_repos () {
	repos=$(composer config repositories --no-plugins --no-ansi --list | grep repositories);
	total=$(echo "$repos" | wc -l);

	while [ $total -gt 0 ]; do
		# two lines at a time.
		# Top - type of repo.
		# Bottom - url of repo.
		total=$((total-2));
		chunk=$(echo "$repos" | head -n $total | tail -n 2);

		type_left=$(echo "$chunk" | head -n 1 | awk -F ' ' '{print $1}');
		type_right=$(echo "$chunk" | head -n 1 | awk -F ' ' '{print $2}');

		url_left=$(echo "$chunk" | tail -n 1 | awk -F ' ' '{print $1}');
		url_right=$(echo "$chunk" | tail -n 1 | awk -F ' ' '{print $2}');

		name=$(echo "$type_left"|awk -F '\.' '{print $2}');

		if [ -z "$url_left" ]; then
			continue;
		fi;

		if [ "$type_right" == "artifact" ]; then
			if [ ! -f "$url_right"  ]; then
				echo "File not found: $url_right";
				echo "Removing repo: $name";
				composer config repositories.$name --unset;
			fi;
			continue;
		fi;
	done;
}

magento_preset_extensions () {
	if [[ ! -d "app/code/Mageplaza/CurrencyFormatter" ]]; then
		git clone https://github.com/mageplaza/magento-2-currency-formatter "app/code/Mageplaza/CurrencyFormatter";
		cd app/code/Mageplaza/CurrencyFormatter || return 1;
		rm -fr .git;
		cd ../../../.. || return 1;
	fi;
	composer require mageplaza/magento-2-bulgarian-language-pack:dev-master mageplaza/module-smtp;
}

# Run the whitelist command on a single magento module.
whitelist_single_module () {
	if [ -f "$1/etc/db_schema.xml" ]; then
		moduleName=$(echo "$1" | awk -F '/' 'NF == 4 {print $3 "_" $4}');
		if [ ! -f "$1/etc/db_schema_whitelist.json" ]; then
			echo "Whitelisting module: $moduleName";
			magento setup:db-declaration:generate-whitelist --module-name="$1";
		else
			echo "Already whitelisted: $moduleName";
		fi;
	fi;
}

# Run the whitelist command, on all magento modules in `app/code` that DO NOT have the whitelist.json file.
magento_whitelist () {
	find app/code -maxdepth 2 -type d -not -empty -exec bash -c "whitelist_single_module $1" \;
}
magento_rebuild () {
	if [ ! -z "$1" ]; then
		cd "/shared/httpd/$1/$1" || return 1;
	fi;
	rm -fr generated/code/*;
	magento_access;
	# Only rebuild if required.
	if [ "$(magento setup:db:status --no-ansi)" != "All modules are up to date." ]; then
		magento_whitelist;
		magento setup:upgrade;
	fi;
	magento setup:di:compile;
	magento_deploy_themes;
	cache;
}

# Rebuild, but without static content.
magento_rebuild_styleless () {
	rm -fr generated/code/*;
	chmod -R 777 generated;
	# Only rebuild if required.
	if [ "$(magento setup:db:status --no-ansi)" != "All modules are up to date." ]; then
		magento_whitelist;
		magento setup:upgrade;
	fi;
	magento setup:di:compile;
	cache;
}

# Set Url For Admin.
magento_set_adminurl () {
	magento setup:config:set --backend-frontname "$1" -n;
}

# Enable all modules that contain the specified word.
magento_modules_enable () {
	magento module:enable $(magento module:status | grep "$1");
}

# Disable all modules that contain the specified word.
magento_modules_disable () {
	magento module:disable $(magento module:status | grep "$1");
}

# Create Admin User. First argument will be used as username.
magento_user () {
	if [ -z "$1" ]; then
		echo "This function expects one(1) parameter.";
		echo "The suplied parameter will be used as username, firstname, last name and during email as follows.";
		echo "[param]@mailinator.com";
		echo "Please supply a username/parameter.";
		return 1;
	fi;
	magento admin:user:create --admin-user "$1" --admin-password "Qwerty_2_Qwerty" --admin-email "$1@mailinator.com" --admin-firstname="$1" --admin-lastname="$1";
}

# Run reindex & cron.
magento_data () {
	magento indexer:reindex;
	magento cron:run;
}

# Disable CSS/JS versioning.
magento_disable_sign() {
	if [ -z "$1" ]; then
		database="$(current_dir_name)";
	else
		database="$1";
	fi;
	if ! mysql -e "insert into $database.core_config_data (config_id, scope, scope_id, path, value) values (null, 'default', 0, 'dev/static/sign', 0);" 2> /dev/null; then
		echo "Row already exists: Updating ...";
		mysql -e "update $database.core_config_data set value = 0 where path = 'dev/static/sign';";
	fi;
}

number_of_themes () {
	find "app/design/$1" -maxdepth 2 -type d -not -empty | awk -F '/' 'NF == 5 {print}'| wc -l;
}

# Deploy only frontend themes.
# If we have custom print only them, else print the default ones.
magento_frontend_themes () {
	used_themes=$(mysql "$(current_dir_name)" -e "select tm.theme_path from core_config_data as ccd join theme as tm on tm.theme_id = ccd.value where ccd.path = 'design/theme/theme_id';");
	for theme in $(echo "$used_themes" | grep -v "theme_path"); do
		deploy_single_theme frontend "$theme";
	done;

	# Files are not always present/not-empty, prefer database when available.
	#if [ $(number_of_themes frontend) -lt 3 ]; then
	#	find app/design/frontend/ -maxdepth 2 -type d -not -empty -exec bash -c "deploy_single_theme frontend $1" \;
	#else
	#	find app/design/frontend/ -maxdepth 2 -type d -not -empty -not -name "luma" -not -name "blank" -exec bash -c "deploy_single_theme frontend $1" \;
	#fi;
}

# Deploy only backend themes.
magento_backend_themes () {
	if [ $(number_of_themes adminhtml) -gt 0 ]; then
		find app/design/adminhtml/ -maxdepth 2 -type d -not -empty -exec bash -c "deploy_single_theme adminhtml $1" \;
	else
		deploy_single_theme adminhtml;
	fi;
}

# Empty the magento log files.
magento_logs_clear () {
	find var/log -name "./*.log" -exec bash -c "echo > $1" \;
}

# List all found magento projects. Based on `bin/magento` file existance.
magento_projects () {
	find /shared/httpd/ -mindepth 1 -maxdepth 1 -type d -not -empty -exec bash -c '\
		themes="$1";\
		project="${themes##*/}";\
		if [ -f "$themes/$project/bin/magento" ]; then\
			echo $project;\
		fi;' \;
}

# Deploy a single theme.
deploy_single_theme () {
	if [ -z "$2" ]; then 
		magento setup:static-content:deploy -f --area $1 $DEPLOY_LANGUAGES;
	else
		# Frontend Themes
		if ! magento setup:static-content:deploy -f --area $1 --theme "$theme" --no-parent $DEPLOY_LANGUAGES; then
			magento setup:static-content:deploy -f --area $1 --theme "$theme" $DEPLOY_LANGUAGES;
		fi;
	fi;
}

# Deploy both frontend & backend themes.
magento_deploy_themes () {
	magento_frontend_themes;
	magento_backend_themes;
}

magento_install() {
	# $1 project name.
	# $2 url
	
	if [ -z "$1" ]; then
		echo "Two(2) arguments are required.";
		echo "1. Name of the project.";
		echo "2. Url which will be git-clone'ed";
		echo "Please provide both arguments";
		return 1;
	else
		project="$1";
		if [ -z "$2" ]; then
			repo_url="$(get_github_repo "$project")"; 
		else
			repo_url="$2";		
		fi;
	fi;
	echo "URL: $repo_url";
	cd /shared/httpd || return 1;
	
	if [[ ! -d "$project/$project" ]]; then
		if [[ -d "/shared/https/$project" ]]; then
			cd "$project" || return 1;
		else
			mkdir "$project";
			cd "$project"  || return 1;
		fi;
		git clone "$repo_url" "$project";
	fi;
	
	cd "/shared/httpd/$project/$project"  || return 1;
	# If composer.lock exists 'composer install' *might* throw an error.
	if [[ -f "composer.lock" ]]; then
		rm "composer.lock";
	fi;
	composer_verify_repos;

	mysql -e "CREATE DATABASE IF NOT EXISTS $project";

	if ! composer_exec install; then
		echo "Composer install failed. Please check the error.";
		return 1;
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
	magento module:disable $(magento module:status | grep -v "Magento\|List of\|None") Magento_TwoFactorAuth;

	# Install project
	if ! magento setup:install \
		--admin-firstname="Admin" --admin-lastname="Admin" \
		--admin-password="$ADMIN_PASSWORD" --admin-email="s.tonev@beluga.software" --admin-user="$ADMIN_USER" \
		--db-password="$MYSQL_PASSWORD" --db-host="$MYSQL_SERVER" --db-user="$MYSQL_USER" --db-name="$project" \
		--elasticsearch-host="$ELASTIC_SERVER" --use-rewrites=1; 
	then
		echo "Magento install failed. Please check the error.";
		return 1;
	fi;

	magento_rebuild_styleless;
	
	# Enable non-default & rebuild again.
	magento_disable_cache;
	magento_disable_sign "$project";

	# Enable modules that DO NOT contain Magento in them.
	magento module:enable $(magento module:status | grep  -v "Magento\|List of\|None\|TwoFactorAuth");
	magento_rebuild;
	
	# devilbox specific.
	cd "/shared/httpd/$project" || return 1;
	ln -s "$project/pub" htdocs
}

# Dump mysql db.
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

# Remove collation, restore db, set url addresses to project url, set elastic url. 
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
get_admin_url () {
	project="$2";
	echo "$project $(php "$1"/bin/magento info:adminuri | grep URI)" | awk -F ' Admin URI: ' '{printf "http://%s.loc%s", $1, $2}';
}

# Get admin url for all found magento projects.
magento_panels_urls () {
	printf "%10s | %10s | %20s\n" "PROJECT" "URL" "ADMIN URL";
	find /shared/httpd/ -mindepth 1 -maxdepth 1 -type d -not -empty -exec bash -c 'get_single_admin_url $1' \;
}
get_single_admin_url () {
	path="$1";
	project="${path##*/}";
	if [ -f "$path/$project/bin/magento" ]; then
		printf "%10s | %10s | %20s\n" "$project" "http://$project.loc/" "$(get_admin_url "$path"/"$project" "$project")";
	fi;
}

# Make git link such that it contains all required auth info.
get_github_repo () {
	part="$(get_github_repo_url "$1" | awk -F '//' '{print $2}')";
	echo "https://$GITHUB_USER:$GITHUB_TOKEN@$part";
}

# Get repo link containing the argument, choose the shortest link.
get_github_repo_url () {
	curl -u $GITHUB_USER:$GITHUB_TOKEN "https://api.github.com/orgs/$GITHUB_ORGANIZATION/repos?per_page=80" |\
	grep clone_url |\
	grep "$1" |\
	awk -F '"' '{print $4}' |\
	sort -n |\
	head -n 1;
}

export -f magento_install;
export -f magento_rebuild;
export -f get_single_admin_url;
export -f deploy_single_theme;
export -f whitelist_single_module;
export -f get_admin_url;

echo "=========================================================================================================";
echo "Greetings, this shell has a few shortcuts related to Magento 2 development.";
echo "You can write 'magento' and hit [TAB] twice to see them.";
echo "=========================================================================================================";