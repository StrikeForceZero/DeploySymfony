#!/bin/bash
## DeploySymfony.sh
## Debian script to deploy symfony from a git repo
## Author: Brett Striker - StrikeForceZero@gmail.com
## License: MIT (see LICENSE file)
## TODO: more prompts, functions, unattended mode

SYMFONY_FOLDER=webserver

confirm () {
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case $response in
        [yY][eE][sS]|[yY])
            true
            ;;
        [nN][oO]|[nN])
            false
            ;;
        *)
            if [[ $response == '' ]]; then
                false
                return
            fi
            echo "please enter Y or N";
            confirm "${1}";
            ;;
    esac
}


if [ ! -f install.lock ]; then
    if confirm "install.lock file not found. Is this a new install? [y/N]"; then
		if confirm "install lamp stack? [y/N]"; then
			sudo apt-get update && apt-get upgrade
			sudo apt-get install apache2 php5 curl php5-curl mysql-server php5-mysql libapache2-mod-php5
		fi
		if confirm "fix php.ini? [y/N]"; then
			echo "fixing php.ini..."
			sudo sed -i "s/^short_open_tag = On$/short_open_tag = Off/" /etc/php5/apache2/php.ini
			#TODO: prompt for desired timezone
			sudo sed -i "s/^;date.timezone =.*$/date.timezone = America\/Detroit/" /etc/php5/apache2/php.ini
		fi
        echo "installing apc (cache), acl, and git..."
        sudo apt-get install php-apc php5-intl acl git
        echo "adding acl to /home partition..."
        awk '$2~"^/home$"{$4="acl,"$4}1' OFS="\t" /etc/fstab
        echo -n "attempting to remount /home... "
        sudo mount -o remount /home
        echo "done."
        echo -n "Please specify a folder/path for the webservers local repository: [webserver] "
        read FOLDER
        FOLDER=${FOLDER:-webserver}
        echo "Please enter in the remote git repository url: "
        echo "(e.g. git@bitbucket.org:username/example.com.git)"
        read GIT_REPO
        git ls-remote "$GIT_REPO" &>-
        if [ "$?" -ne 0 ]; then
                echo "[ERROR] Unable to read from '$GIT_REPO'"
                echo "Please check the URL and try again."
                exit 1;
        fi
        echo -n "git repo appears valid, attempting to clone..."
        git clone $GIT_REPO $FOLDER
        echo "done."
        echo -n "installing composer to $FOLDER..."
        cd $FOLDER
        curl -s https://getcomposer.org/installer | php
        cd ../
        echo "done."
        echo $FOLDER >> ./install.lock
    fi
fi

if [ -f install.lock ]; then
 SYMFONY_FOLDER=$(<install.lock)
else
 echo "WARNING - installation file not detected."
 echo "Install did not complete?"
 if ! confirm "are you sure you would like to continue with $SYMFONY_FOLDER? [y/N]"; then
  exit
 fi
fi

echo "using folder: $SYMFONY_FOLDER"

cd $SYMFONY_FOLDER

if confirm "would you like to fetch updates? [y/N]"; then
 echo -n "fetching updates... "
 git pull origin master
 echo "done."
fi

if confirm "clear Assetics? [y/N]"; then
 echo -n "clearing assetic assets... "
 rm -rf web/css/compiled/* web/js/compiled/*
 echo " done."
fi

if confirm "update dep? [y/N]"; then
 echo -n "installing dep... "
 php composer.phar install --no-dev --optimize-autoloader
 echo "done."
 echo -n "updating dep... "
 php composer.phar update --no-dev --optimize-autoloader
 echo "done."
fi

if confirm "fix permissions? [y/N]"; then
 echo -n "fixing permissions... "
 HTTPDUSER=`ps aux | grep -E '[a]pache|[h]ttpd|[_]www|[w]ww-data|[n]ginx' | grep -v root | head -1 | cut -d\  -f1`
 sudo setfacl -R -m u:"$HTTPDUSER":rwX -m u:`whoami`:rwX app/cache app/logs
 sudo setfacl -dR -m u:"$HTTPDUSER":rwX -m u:`whoami`:rwX app/cache app/logs
 #sudo chgrp -R velocitynoc.com app/cache app/logs
 #sudo chmod  -R g+rwx app/cache app/logs
 echo "done."
fi

if confirm "force update schema? [y/N]"; then
 echo -n "updating schema... "
 php app/console doctrine:schema:update --force
 echo "done."
fi


if confirm "run commands? [y/N]"; then

#clear cache prod
echo -n "clearing prod cache..."
php app/console cache:clear --env=prod >/dev/null
echo " done."
echo -n "warming up prod cache..."
php app/console cache:warmup --env=prod --no-debug >/dev/null
echo " done."
echo -n "dumping assets..."
php app/console assetic:dump --env=prod --no-debug >/dev/null
echo " done."
echo "production cache is now ready."

#symlink assets
echo -n "attempting to symlink assets..."
php app/console assets:install web --symlink
echo " done."

#dump assets
echo -n "dumping assets"
php app/console assetic:dump
echo " done."

#optimize and warmup
 php composer.phar dump-autoload --optimize
 php app/console cache:warmup --env=prod
fi
