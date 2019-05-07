#!/bin/sh
#


echo "****product_INIT SCRIPT LAUNCHED****"
hostname=`cat /etc/sysconfig/network | grep HOSTNAME | cut -f2 -d "="`
host_check=`hostname`
if [[ $host_check != $hostname ]]; then
        echo ">_<"
        echo "Hostname changed, a system reboot is required..."
        echo "product_INIT SCRIPT ABORTED!"
        echo ">_<"
        exit
fi
# Check if MySQL is running
service mysqld status
if [ $? != 0 ]; then
        echo "MySQL not running, starting"
        service mysqld start
        if [ $? != 0 ]; then
                echo "Could not start MySQL, exiting..."
                exit
        fi
fi

# Check for database, to make sure we don't re-install
echo "#####Checking if prod_product database is installed.#####"
echo ""
check=`mysql -e "show databases" | grep "prod_product" | wc -l`
if [ $check != 0 ]; then
        echo "Database present, skipping database install...";
else
        # Create database and import structure
        echo "Creating and initializing prod_product database...";
        mysql -e "CREATE DATABASE prod_product"
        mysql prod_product < /opt/product/install/database/base/prod_product_structure.sql
        mysql prod_product < /opt/product/install/database/data/prod_product_data.sql

fi

echo ""
#Check for proxy database
echo "#####Checking if proxy database is installed.#####"
echo ""
check_proxy=`mysql -e "show databases" | grep "proxy" | wc -l`
if [ $check_proxy != 0 ]; then
        echo "Proxy database present, skipping database install..."
else
        echo "Creating proxy database..."
        mysql < /opt/product/install/proxy/proxy_db.sql
		mysql proxy -e "INSERT INTO proxy.sc_filter_result VALUES ( NULL,'allowed','Allowed')"
		mysql proxy -e "INSERT INTO proxy.sc_filter_result VALUES ( NULL,'blocked','Blocked')"
fi

#Create mysql user and grant permissions on prod_product database
echo "Creating user for prod_product database...";
mysql -e "CREATE USER 'user'@'localhost' IDENTIFIED BY 'xxx';"
mysql -e "GRANT ALL PRIVILEGES ON prod_product.* TO 'user'@'localhost';"
mysql -e "GRANT ALL PRIVILEGES ON proxy.* TO 'user'@'localhost';"

echo ""

echo "#####Restarting network service.#####"
echo "..."
/sbin/service network restart

echo "#####Done restarting network service.#####"
echo ""

#Hostname Config
echo "#####Begin hosts file configuration.#####"
ipaddress=`ifconfig em1 2>&- | grep "inet addr:" | sed 's/.*inet addr://' | sed 's/[^0-9.].*//'`

if [[ $ipaddress == "" ]]; then
	ipaddress=`ifconfig eth0 2>&- | grep "inet addr:" | sed 's/.*inet addr://' | sed 's/[^0-9.].*//'`
fi

hostname=`cat /etc/sysconfig/network | grep HOSTNAME | cut -f2 -d "="`
if [[ $hostname == "" ]]; then
        hostname=`hostname`
fi

domain=$hostname
host=`echo $domain | awk -F "." '{print $1}'`

echo "Checking if reconfiguration is required"
hostcheck=`cat /etc/hosts | grep $ipaddress | grep $hostname`
hostIp=`cat /etc/hosts | grep $ipaddress`
#check if ipaddress exists
if [[ $hostIp == "" ]]; then
        echo "No entry for ipaddress [$ipaddress] found in /etc/hosts"
        echo "Adding new ipaddress"
        echo -e "$ipaddress             $domain         $host\n$(cat /etc/hosts)" > /etc/hosts
else
        #check if hostname changed
        if [[ $hostcheck == "" ]]; then
                echo "New hostname picked up..."
                echo "Modifying /etc/hosts file..."
                cat /etc/hosts | grep $ipaddress | sed -i '/'"$ipaddress"'/c'"$ipaddress                $domain         $host"  /etc/hosts
        fi
fi
echo "#####Hosts file configuration complete.#####"
echo ""


echo "#####Disabling iptables.#####"
#Disable firewall
service iptables save
service iptables stop
chkconfig iptables off

echo ""

green=`tput setaf 2`
magenta=`tput setaf 5`
cyan=`tput setaf 6`
yellow=`tput setaf 3`
red=`tput setaf 1`
bold=`tput bold`
reset=`tput sgr0`


border () {
    local str="$*"      # Put all arguments into single string
    local len=${#str}
    local i
    for (( i = 0; i < len + 4; ++i )); do
        printf '-'
    done
    printf "\n|${bold}${cyan} $str ${reset}|\n"
    for (( i = 0; i < len + 4; ++i )); do
        printf '-'
    done
    echo
}

proxyhandler () {
    local str=$1
	cp -p /path/to/module/handler.pl /path/to/module/handler.pl.orig
	sed -i -r 's/#(.+\/opt\/proxy_scripts\/bin\/'$str'\.pl)/\1/g' /path/to/module/handler.pl
	if [ $? == 0 ]; then
		echo
		echo "${green}$str log import module has been enabled! ${reset}"
	else
		echo "Something went wrong, $str log import module not enabled!"
	fi
}


type[1]="BlueCoat"
type[2]="Checkpoint R77"
type[3]="Checkpoint R80"
type[4]="ZScalar"

while true; do
		echo 
        border "Please select the log types to be imported"
        for i in "${!type[@]}"
        do
          echo " $i ${type[$i]}"
        done
        echo
        read -p "${bold}${cyan}Enter selection [1-4] > ${reset}"


        if [[ $REPLY =~ ^[1-4]$ ]]; then
                case $REPLY in
                  1)
                        file=${type[$REPLY]}
                        read -p "$file log types selected, do you want to proceed y/n " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then							
							proxyhandler process$file
							break
						else
							continue
                        fi
                        ;;
                  2)
                        file=${type[$REPLY]}
                        read -p "$file log types selected, do you want to proceed y/n " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then							
							proxyhandler processCheckPoint
							if [ $? == 0 ]; then
								cp -p /etc/cron.d/proxy_scripts /var/tmp/proxy_scripts.orig
								sed -i -r 's/#(.+cleanup\.pl.+)/\1/g' /etc/cron.d/proxy_scripts
							fi
							break
						else
							continue
                        fi
                        ;;
                  3)
                        file=${type[$REPLY]}
                        read -p "$file log types selected, do you want to proceed y/n " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then							
							proxyhandler processCheckPoint_R80
							if [ $? == 0 ]; then
								cp -p /etc/cron.d/proxy_scripts /var/tmp/proxy_scripts.orig
								sed -i -r 's/#(.+cleanup\.pl.+)/\1/g' /etc/cron.d/proxy_scripts
							fi
							break
						else
							continue
                        fi
                        ;;
                  4)
                        file=${type[$REPLY]}
                        read -p "$file log types selected, do you want to proceed y/n " -n 1 -r
                        echo
                        if [[ $REPLY =~ ^[Yy]$ ]]; then							
							proxyhandler process$file
							if [ $? == 0 ]; then
								cp -p /etc/cron.d/proxy_scripts /var/tmp/proxy_scripts.orig
								sed -i -r 's/#(.+zscalar_logrotate.+)/\1/g' /etc/cron.d/proxy_scripts								
								sed -i -r 's/#(.+cleanup_logs.+)/\1/g' /etc/cron.d/proxy_scripts
							fi
							break
						else
							continue
                        fi
                        ;;
                  0)
                        break
                        ;;
                esac
          else
                echo "${red}($REPLY) Invalid entry ${reset}"
                echo

          fi
done

	

	
##Running sub scripts

#Product config
/opt/product/install/user_product_config.pl

#LDAP Default domain
/opt/product/install/ldap_domain_init.pl

#Selfsigned certificate
/opt/product/install/ssl_self_sign_cert.pl

wait $!

#Initialize default user
/opt/product/install/ldap_default_user.pl

#Start productd
echo "######Retarting productd.#####";
service productd restart

wait $!

chkconfig --add productd
