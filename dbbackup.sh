#!/bin/sh
# Backup.sh

days=30 #set how old to begin backup from for monitor.log and mss.HISTORY tables.
echo `date +%Y-%m-%d\ %T`" Starting backup"

# Directories
backupDir="/var/backup"
osDir=$backupDir"/os"
configDir=$backupDir"/scripts/config"
databaseDir=$backupDir"/product/database"
backupConfDir="/etc/opt/backup"
syncListFile=$backupConfDir"/.sync_list"
syncDestFile=$backupConfDir"/.sync_dest"
keyFile=$backupConfDir"/.key"
retentionFile=$backupConfDir"/.retention"
retention=7; # Default, in days

# Check for customized retention
if [ -f $retentionFile ]; then
	customRetention=`cat $retentionFile`
	if [ $customRetention -eq $customRetention 2> /dev/null ]; then
		retention=$customRetention;
	fi
fi

# Create lock files
echo `date +%Y-%m-%d\ %T`" Creating lock files"
`touch /tmp/prodlock_nodata`
`touch /tmp/prodlock`

#############################
# OS                                            #
#############################
# Create new backup
echo `date +%Y-%m-%d\ %T`" Starting os backup"
osList="$configDir/os.list"
if [[ -s $osList ]]; then
        echo `date +%Y-%m-%d\ %T`" OS list file found: $osList"
        filename=$osDir"/os_"`date +%Y-%m-%d`".tar.gz"
        files=`cat $osList | tr '\n' ' '`
        tar czpf $filename -T $osList
        echo `date +%Y-%m-%d\ %T`" OS backup created: $filename"
else
        echo `date +%Y-%m-%d\ %T`" OS list file not found: $osList"
fi
# Delete old backups
filesToDelete=`find $osDir -name "os_*.tar.gz" -mtime +$retention | tr '\n' ' '`
echo `date +%Y-%m-%d\ %T`" Deleting old os backups ($filesToDelete)"
find $osDir -name "os_*.tar.gz" -mtime +$retention -delete

#############################
# Database                                      #
#############################
# Create new backup
echo `date +%Y-%m-%d\ %T`" Starting database backup"
vfactor=$(($days*86400))
databaseArchiveFilename=$databaseDir"/db_"`date +%Y-%m-%d`".tar"
databases=`echo "show databases" | mysql --skip-column-name`
date=`date +%Y-%m-%d`
currentDate=`date +%s`
last_timestamp=$(($currentDate-$vfactor))

for database in $databases
do
	tables=`echo "show tables" | mysql --skip-column-name $database`	
	for table in $tables
	do 
		if [[ $days > 0 ]]; then
			if [[ $table =~ someBigTable.* ]] || [[ $table == someLogTable ]]; then
				if [ "$table" != "someNotSoBigTable" ]; then
					echo `date +%Y-%m-%d\ %T`" Dump for $days days ago: $database.$table "
					mysqldump $database $table --opt --where "timestamp>='$last_timestamp'" -q -Q | gzip > $databaseDir"/db_"$date"_"$database"."$table".sql.gz";
				else
					echo `date +%Y-%m-%d\ %T`" Table: $database.$table "
                    mysqldump $database $table --opt -q -Q | gzip > $databaseDir"/db_"$date"_"$database"."$table".sql.gz";
				fi
			else 
				echo `date +%Y-%m-%d\ %T`" Table: $database.$table  "
				mysqldump $database $table --opt -q -Q | gzip > $databaseDir"/db_"$date"_"$database"."$table".sql.gz";
			fi
		else
			echo `date +%Y-%m-%d\ %T`" Table: $database.$table  "
				mysqldump $database $table --opt -q -Q | gzip > $databaseDir"/db_"$date"_"$database"."$table".sql.gz";
		fi
	done
done

# Tar up individual archives
echo `date +%Y-%m-%d\ %T`" Tarring up archives"
cd $databaseDir
tar --remove-files -cpf $databaseArchiveFilename "db_"$date"_"*".sql.gz"
echo `date +%Y-%m-%d\ %T`" Database backup created: $databaseArchiveFilename"

# Optionally encrypt archive
if [ -f $keyFile ]; then
	echo `date +%Y-%m-%d\ %T`" Encrypting tar archive"
	gpg --batch -q --passphrase-file $keyFile --cipher-algo AES256 -c $databaseArchiveFilename
	rm -f $databaseArchiveFilename
fi

# Delete old backups
filesToDelete=`find $databaseDir -name "db_*.tar" -mtime +$retention | tr '\n' ' '`
echo `date +%Y-%m-%d\ %T`" Deleting old database backups ($filesToDelete)"
find $databaseDir -name "db_*.tar" -mtime +$retention -delete

# Delete old encrypted backups
filesToDelete=`find $databaseDir -name "db_*.tar.gpg" -mtime +$retention | tr '\n' ' '`
echo `date +%Y-%m-%d\ %T`" Deleting old database backups - encrypted ($filesToDelete)"
find $databaseDir -name "db_*.tar.gpg" -mtime +$retention -delete

# Delete old backups - legacy
filesToDelete=`find $databaseDir -name "db_*.*.gz" -mtime +$retention | tr '\n' ' '`
echo `date +%Y-%m-%d\ %T`" Deleting old database backups - legacy ($filesToDelete)"
find $databaseDir -name "db_*.*.gz" -mtime +$retention -delete

# Optionally rsync backups somewhere
if [ -f $syncListFile ] && [ -f $syncDestFile ]; then
	syncDestination=`cat $syncDestFile`
	echo `date +%Y-%m-%d\ %T`" Syncing archives"
	rsync --delete -L -r -a -v --files-from=$syncListFile $backupDir -e ssh $syncDestination
fi

# Remove lock files
echo `date +%Y-%m-%d\ %T`" Removing lock files (300 second sleep)"
`rm -f /tmp/prodlock`
sleep 305;
`rm -f /tmp/prodlock_nodata`

echo `date +%Y-%m-%d\ %T`" Done"
