#!/bin/bash

echo "****INIT SCRIPT LAUNCHED****"
hostname=`cat /etc/sysconfig/network | grep HOSTNAME | cut -f2 -d "="`
host_check=`hostname`
if [[ $host_check != $hostname ]]; then
	echo ">_<"
	echo "Hostname changed, a system reboot is required..."
	echo ">_<"
	exit
fi
echo "restarting network service"
echo "..."
/sbin/service network restart

echo ""
optimize=`cat /etc/my.cnf | grep "query_cache_size = 128M"` 
if [[ $optimize == "" ]]; then
	echo "Mysql optimization..."
	cat /etc/my.cnf | grep "user=mysql" | sed -i '/'"user=mysql"'/c'"user=mysql\nskip_name_resolve\nquery_cache_type = 1\nquery_cache_size = 128M\ninnodb_buffer_pool_size = 1024M"  /etc/my.cnf
	echo "Mysql optimization done"
fi

echo ""

echo "begin mysql optimizations"
cp -p /etc/my.cnf /etc/my.cnf.orig
cat /etc/my.cnf | grep "^\[mysqld\]" | sed -i '/'"^\[mysqld\]"'/c'"[mysqld]\nmax_allowed_packet=4M"  /etc/my.cnf
echo "mysql optimizations complete"
echo "..restarting mysql services.."
/etc/init.d/mysqld restart

#Sitename Config
echo "Begin sitename configuration.."
ipaddress=`ifconfig eth0 2>&- | grep "inet addr:" | sed 's/.*inet addr://' | sed 's/[^0-9.].*//'`

if [[ $ipaddress == "" ]]; then
	ipaddress=`ifconfig em1 2>&- | grep "inet addr:" | sed 's/.*inet addr://' | sed 's/[^0-9.].*//'`
fi

if [[ $hostname == "" ]]; then
	hostname=`hostname`
fi

domain=$hostname
host=`echo $domain | awk -F "." '{print $1}'` 

if [ -f /path/to/product/sitename ]; then
	echo "..sitename configuration file found"
	echo "..checking if reconfiguration is required"	
	hostcheck=`cat /etc/hosts | grep $ipaddress | grep -w $hostname`
	hostIp=`cat /etc/hosts | grep $ipaddress`
	#check if ipaddress exists
	if [[ $hostIp == "" ]]; then
		echo "..No entry for ipaddress [$ipaddress] found in /etc/hosts"
		echo "..Adding new ipaddress"
		echo "..re-creating sitename config file"
		printf "$host" > /path/to/product/sitename		
		echo -e "$ipaddress		$domain		$host\n$(cat /etc/hosts)" > /etc/hosts
	else
		#check if hostname changed
		if [[ $hostcheck == "" ]]; then
		echo "..Hostname change picked up"
		echo "..re-creating sitename config file"
		cat /etc/hosts | grep $ipaddress | sed -i '/'"$ipaddress"'/c'"$ipaddress		$domain		$host"  /etc/hosts			
		echo "Updating siteinfo table..."		
		siteid=`echo "select id from systems.siteinfo where sitename='$old_host'" | mysql -N`		
		echo "update systems.siteinfo set sitename='$host' where id=$siteid" | mysql
		printf "$host" > /path/to/product/sitename
		fi
	fi	
else
	echo "..creating sitename config file"
	printf "$host" > /path/to/product/sitename		
	echo -e "$ipaddress		$domain		$host\n$(cat /etc/hosts)" > /etc/hosts
	
fi
echo "Sitename configuration complete"
echo ""
echo "Disable root login..."
#Disable root login
cp -p /etc/ssh/sshd_config /etc/ssh/sshd_config.orig
cat /etc/ssh/sshd_config | sed 's/#PermitRootLogin yes\>/#PermitRootLogin yes\nPermitRootLogin no/' > /etc/ssh/tmp_sshd_config
cat /etc/ssh/tmp_sshd_config | grep "MaxStartups" | sed -i '/'"MaxStartups"'/c'"MaxStartups 100:30:200"  /etc/ssh/tmp_sshd_config
mv -f /etc/ssh/tmp_sshd_config /etc/ssh/sshd_config
echo "Disable DNS lookups for SSH..."
#Disable DNS lookups for SSH
sed -i -r 's/#?UseDNS yes/UseDNS no/g' /etc/ssh/sshd_config

#Updating SSH MAC algorithms
echo
echo "Updating SSH MAC algorithms..."
echo -e "\nCiphers aes128-ctr,aes192-ctr,aes256-ctr\n" >> /etc/ssh/sshd_config
echo -e "MACs hmac-sha1,hmac-ripemd160\n" >> /etc/ssh/sshd_config
echo "SSH MAC algorithms updated."
#Updating SSL Ciphers
echo
echo "Updating SSL Ciphers..."
cp -p /etc/httpd/conf.d/ssl.conf /etc/httpd/conf.d/ssl.conf.orig
cat /etc/httpd/conf.d/ssl.conf | grep SSLProtocol | sed -i '/'"SSLProtocol"'/c'"SSLProtocol all -SSLv3"  /etc/httpd/conf.d/ssl.conf

#disable ssl request logging
sed -i -r 's/CustomLog .*/\#&/g' /etc/httpd/conf.d/ssl.conf

cat /etc/httpd/conf.d/ssl.conf | grep SSLCipherSuite | sed -i '/'"SSLCipherSuite"'/c'"SSLCipherSuite ALL:!EDH:!ADH:RC4+RSA:+HIGH:!MEDIUM:!LOW:!SSLv2:!EXPORT:!ECDH:!3DES"  /etc/httpd/conf.d/ssl.conf

echo "SSL Ciphers updated."
echo

/etc/init.d/sshd restart

echo "Begin Sysct configurations..."
cp -p /etc/sysctl.conf /etc/sysctl.conf.orig
echo -e "\n# Sets swappiness to 0 to ensure that the server only swaps when RAM is too low.\nvm.swappiness=0\n" >> /etc/sysctl.conf
echo

echo "Begin Httpd configurations..."
cp -p /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.orig
#block provision of version info
cat /etc/httpd/conf/httpd.conf | grep "^ServerSignature On" | sed -i '/'"^ServerSignature On"'/c'"#ServerSignature On\nServerSignature Off"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "^ServerTokens OS" | sed -i '/'"^ServerTokens OS"'/c'"#ServerTokens OS\nServerTokens Prod"  /etc/httpd/conf/httpd.conf

cat /etc/httpd/conf/httpd.conf | grep "^KeepAlive Off" | sed -i '/'"^KeepAlive Off"'/c'"KeepAlive On"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "^MaxKeepAliveRequests" | sed -i '/'"^MaxKeepAliveRequests"'/c'"MaxKeepAliveRequests 300"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "^KeepAliveTimeout" | sed -i '/'"^KeepAliveTimeout"'/c'"KeepAliveTimeout  320"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | sed -n '/^<IfModule prefork.c>/,/\<IfModule>/p' | grep "^StartServers" | sed -i '/'"^StartServers"'/c'"StartServers       16"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | sed -n '/^<IfModule prefork.c>/,/\<IfModule>/p' | grep "^MinSpareServers" | sed -i '/'"^MinSpareServers"'/c'"MinSpareServers    5"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | sed -n '/^<IfModule prefork.c>/,/\<IfModule>/p' | grep "^MaxSpareServers" | sed -i '/'"^MaxSpareServers"'/c'"MaxSpareServers   20"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | sed -n '/^<IfModule prefork.c>/,/\<IfModule>/p' | grep "^ServerLimit" | sed -i '/'"^ServerLimit"'/c'"ServerLimit      256"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | sed -n '/^<IfModule prefork.c>/,/\<IfModule>/p' | grep "^MaxClients" | sed -i '/'"^MaxClients"'/c'"MaxClients       150"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | sed -n '/^<IfModule prefork.c>/,/\<IfModule>/p' | grep "^MaxRequestsPerChild" | sed -i '/'"^MaxRequestsPerChild"'/c'"MaxRequestsPerChild  1200"  /etc/httpd/conf/httpd.conf


cat /etc/httpd/conf/httpd.conf | grep "Listen 80" | sed -i '/'"Listen 80"'/c'"#Listen 80"  /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "User apache" | sed -i '/'"User apache"'/c'"User mss" /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "Group apache" | sed -i '/'"Group apache"'/c'"Group mss" /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "DocumentRoot \"/var/www/html\"" | sed -i '/'"DocumentRoot \"\/var\/www\/html\""'/c'"DocumentRoot \"/opt\/pulse\/srv\/www\/public_html\"" /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "<Directory \"/var/www/html\">" | sed -i '/'"<Directory \"\/var\/www\/html\">"'/c'"<Directory \"\/opt\/pulse\/srv\/www\/public_html\">" /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "Options Indexes FollowSymLinks" | sed -i '/'"Options Indexes FollowSymLinks"'/c'"<LimitExcept GET POST>\ndeny from all\n</LimitExcept>\nOptions FollowSymLinks Includes Indexes  MultiViews\n" /etc/httpd/conf/httpd.conf
cat /etc/httpd/conf/httpd.conf | grep "AddIcon /icons/bomb.gif /core" | sed -i '/'"AddIcon \/icons\/bomb\.gif \/core"'/c'"AddIcon \/icons\/bomb\.gif core" /etc/httpd/conf/httpd.conf

echo "disabling http TRACE XSS attack.."
echo -e "\n#http TRACE XSS attack\n" >> /etc/httpd/conf/httpd.conf
echo -e "TraceEnable Off\n" >> /etc/httpd/conf/httpd.conf
echo "...HHttpd configuration done"
echo

echo "Begin php configurations..."
cp -p /etc/php.ini /etc/php.ini.orig
cat /etc/php.ini | grep ";date.timezone =" | sed -i '/'";date.timezone ="'/c'"date.timezone = Africa/Johannesburg"  /etc/php.ini
cat /etc/php.ini | grep "short_open_tag = Off" | sed -i '/'"short_open_tag = Off"'/c'"short_open_tag = On"  /etc/php.ini
cat /etc/php.ini | grep "allow_call_time_pass_reference = Off" | sed -i '/'"allow_call_time_pass_reference = Off"'/c'"allow_call_time_pass_reference = On" /etc/php.ini
cat /etc/php.ini | grep "max_execution_time = 30" | sed -i '/'"max_execution_time = 30"'/c'"max_execution_time = 180" /etc/php.ini
cat /etc/php.ini | grep "memory_limit = 128M" | sed -i '/'"memory_limit = 128M"'/c'"memory_limit = 512M" /etc/php.ini
cat /etc/php.ini | grep "html_errors = Off" | sed -i '/'"html_errors = Off"'/c'";html_errors = Off" /etc/php.ini
cat /etc/php.ini | grep "register_long_arrays = Off" | sed -i '/'"register_long_arrays = Off"'/c'"register_long_arrays = On" /etc/php.ini
cat /etc/php.ini | grep ";upload_tmp_dir =" | sed -i '/'";upload_tmp_dir ="'/c'"upload_tmp_dir = /tmp/" /etc/php.ini
cat /etc/php.ini | grep "upload_max_filesize = 2M" | sed -i '/'"upload_max_filesize = 2M"'/c'"upload_max_filesize = 8M" /etc/php.ini
cat /etc/php.ini | grep "allow_url_include = Off" | sed -i '/'"allow_url_include = Off"'/c'";allow_url_include = Off" /etc/php.ini
#cat /etc/php.ini | grep "\[sysvshm\]" | sed -i '/'"\[sysvshm\]"'/c'"[sysvshm]\nextension=mbstring.so\n" /etc/php.ini
echo -e "\n[Zend]\nzend_loader.license_path=/usr/local/mss/conf/\nzend_loader.enable=1\n" >> /etc/php.ini

echo "Disabling PHP expose_php Information Disclosure..."

cat /etc/php.ini | grep expose_php | sed -i '/'"expose_php"'/c'"expose_php = Off"  /etc/php.ini
cat /etc/php.ini | grep session.cookie_httponly | sed -i '/'"session.cookie_httponly"'/c'"session.cookie_httponly = True"  /etc/php.ini
echo "...php configurations done"
echo 

/etc/init.d/httpd restart
echo ""
echo "****INIT SCRIPT DONE****"
echo ""
