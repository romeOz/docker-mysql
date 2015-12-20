#!/bin/bash

set -m
set -e

MYSQL_DATA_DIR=${MYSQL_DATA_DIR:-"/var/lib/mysql"}
MYSQL_CONFIG=${MYSQL_CONFIG:-"/etc/mysql/conf.d/custom.cnf"}
MYSQL_LOG=${MYSQL_LOG:-"/var/log/mysql/error.log"}
MYSQL_BACKUP_DIR=${MYSQL_BACKUP_DIR:-"/tmp/backup"}
MYSQL_BACKUP_FILENAME=${MYSQL_BACKUP_FILENAME:-"backup.last.bz2"}
MYSQL_RESTORE=${MYSQL_RESTORE:-}
MYSQL_CHECK=${MYSQL_CHECK:-}
MYSQL_ROTATE_BACKUP=${MYSQL_ROTATE_BACKUP:-true}
MYSQL_CACHE_ENABLED=${MYSQL_CACHE_ENABLED:-false}

MYSQL_USER=${MYSQL_USER:-admin}
MYSQL_PASS=${MYSQL_PASS:-}

DB_NAME=${DB_NAME:-}
DB_REMOTE_HOST=${DB_REMOTE_HOST:-}
DB_REMOTE_PORT=${DB_REMOTE_PORT:-3306}
DB_REMOTE_USER=${DB_REMOTE_USER:-admin}
DB_REMOTE_PASS=${DB_REMOTE_PASS:-}

MYSQL_MODE=${MYSQL_MODE:-}

REPLICATION_USER=${REPLICATION_USER:-replica}
REPLICATION_PASS=${REPLICATION_PASS:-replica}
REPLICATION_HOST=${REPLICATION_HOST:-}
REPLICATION_PORT=${REPLICATION_PORT:-3306}

# Set permission of config file
chmod 644 ${MYSQL_CONFIG}

start_mysql()
{
    $(which mysqld_safe) >/dev/null 2>&1 &

    # wait for mysql server to start (max 30 seconds)
    timeout=30
    echo -n "Waiting for database server to accept connections"
    while ! $(which mysqladmin) -u root status >/dev/null 2>&1
    do
      timeout=$(($timeout - 1))
      if [ $timeout -eq 0 ]; then
        echo -e "\nCould not connect to database server. Aborting..."
        exit 1
      fi
      echo -n "."
      sleep 1
    done
    echo
}

create_mysql_user()
{
    if [[ -n ${MYSQL_USER} && -n ${MYSQL_PASS} ]]; then
        echo "Creating MySQL user ${MYSQL_USER}..."
        mysql -uroot -e "CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASS}'"
        mysql -uroot -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'%' WITH GRANT OPTION"
    fi
}

create_db()
{
    if [[ -n ${DB_NAME} ]]; then
        for db in $(awk -F',' '{for (i = 1 ; i <= NF ; i++) print $i}' <<< "${DB_NAME}"); do
            echo "Creating database \"${db}\"..."
            mysql -uroot -e "CREATE DATABASE IF NOT EXISTS ${db};"
        done
        echo "Done!"
    fi
}

create_backup_dir()
{
    if [[ ! -d ${MYSQL_BACKUP_DIR}/ ]]; then
        mkdir -p ${MYSQL_BACKUP_DIR}/
    fi
    chmod -R 0755 ${MYSQL_BACKUP_DIR}
}

rotate_backup()
{
    echo "Rotate backup..."

    if [[ ${MYSQL_ROTATE_BACKUP} == true ]]; then
        WEEK=$(date +"%V")
        MONTH=$(date +"%b")
        let "INDEX = WEEK % 5" || true
        if [[ ${INDEX} == 0  ]]; then
          INDEX=4
        fi

        test -e ${MYSQL_BACKUP_DIR}/backup.${INDEX}.bz2 && rm ${MYSQL_BACKUP_DIR}/backup.${INDEX}.bz2
        mv ${MYSQL_BACKUP_DIR}/backup.bz2 ${MYSQL_BACKUP_DIR}/backup.${INDEX}.bz2
        echo "Create backup file: ${MYSQL_BACKUP_DIR}/backup.${INDEX}.bz2"

        test -e ${MYSQL_BACKUP_DIR}/backup.${MONTH}.bz2 && rm ${MYSQL_BACKUP_DIR}/backup.${MONTH}.bz2
        ln ${MYSQL_BACKUP_DIR}/backup.${INDEX}.bz2 ${MYSQL_BACKUP_DIR}/backup.${MONTH}.bz2
        echo "Create backup file: ${MYSQL_BACKUP_DIR}/backup.${MONTH}.bz2"

        test -e ${MYSQL_BACKUP_DIR}/backup.last.bz2 && rm ${MYSQL_BACKUP_DIR}/backup.last.bz2
        ln ${MYSQL_BACKUP_DIR}/backup.${INDEX}.bz2 ${MYSQL_BACKUP_DIR}/backup.last.bz2
        echo "Create backup file:  ${MYSQL_BACKUP_DIR}/backup.last.bz2"
    else
        mv ${MYSQL_BACKUP_DIR}/backup.bz2 ${MYSQL_BACKUP_DIR}/backup.last.bz2
        echo "Create backup file: ${MYSQL_BACKUP_DIR}/backup.last.bz2"
    fi
}

import_backup()
{
    FILES=$1
    if [[ ${FILES} == default ]]; then
        FILES="${MYSQL_BACKUP_DIR}/${MYSQL_BACKUP_FILENAME}"
    fi
    for FILE in ${FILES}; do
	    echo "Importing dump ${FILE} ..."
        if [[ -f "${FILE}" ]]; then
            if [[ ${FILE} =~ \.bz2$ ]]; then
                lbzip2 -dc -n 2 ${FILE} | mysql -uroot
            else
                mysql -uroot < "${FILE}"
            fi
        else
            echo "Unknown dump: ${FILE}"
            exit 1
        fi
    done
    rm -f ${MYSQL_DATA_DIR}/auto.cnf
}

# Initialize empty data volume and create MySQL user
if [[ ! -d ${MYSQL_DATA_DIR}/mysql ]]; then
    echo "An empty or uninitialized MySQL volume is detected in ${MYSQL_DATA_DIR}"
    echo "Installing MySQL..."
    mysql_install_db || exit 1
    touch /tmp/.EMPTY_DB
    echo "Done!"
else
    echo "Using an existing volume of MySQL."
fi

if [[ ${MYSQL_CACHE_ENABLED} == true ]]; then
    echo "Enabled query cache to '${MYSQL_CONFIG}' (query_cache_type = 1)"
    sed -i "s/^#query_cache_type.*/query_cache_type = 1/" ${MYSQL_CONFIG}
fi

# Set MySQL REPLICATION - MASTER
if [[ ${MYSQL_MODE} == master ]]; then
    echo "Configuring MySQL replication as master (1/2) ..."
    if [ ! -f /tmp/.REPLICATION_SET_1 ]; then
        RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"
        echo "Writting configuration file '${MYSQL_CONFIG}' with server-id=${RAND}"
        sed -i "s/^#server-id.*/server-id = ${RAND}/" ${MYSQL_CONFIG}
        sed -i "s/^#log-bin.*/log-bin = ${HOSTNAME}-bin/" ${MYSQL_CONFIG}
        touch /tmp/.REPLICATION_SET_1
    else
        echo "MySQL replication master already configured, skip"
    fi
fi

# Set MySQL REPLICATION - SLAVE
if [[ ${MYSQL_MODE} == slave ]]; then
    echo "Configuring MySQL replication as slave (1/2) ..."
    if [[ -z ${REPLICATION_HOST} || -z ${REPLICATION_PORT} ]]; then
        echo
        echo "WARNING: "
        echo "  Please specify a replication host/port for salve. "
        echo
        exit 1;
    fi
    if [ ! -f /tmp/.REPLICATION_SET_1 ]; then
        RAND="$(date +%s | rev | cut -c 1-2)$(echo ${RANDOM})"
        echo "Writting configuration file '${MYSQL_CONFIG}' with server-id=${RAND}"
        sed -i "s/^#server-id.*/server-id = ${RAND}/" ${MYSQL_CONFIG}
        sed -i "s/^#log-bin.*/log-bin = ${HOSTNAME}-bin/" ${MYSQL_CONFIG}
        sed -i "s/^#relay-log.*/relay-log = ${HOSTNAME}-relay-bin/" ${MYSQL_CONFIG}
        # 1062 - Duplicate entry for INSERT...
        #sed -i "s/^#slave-skip-errors.*/slave-skip-errors = 1062/" ${MYSQL_CONFIG}
        touch /tmp/.REPLICATION_SET_1
    else
        echo "MySQL replication slave already configured, skip"
    fi
fi

# allow arguments to be passed to mysqld_safe
if [[ ${1:0:1} = '-' ]]; then
  EXTRA_OPTS="$@"
  set --
elif [[ ${1} == mysqld_safe || ${1} == $(which mysqld_safe) ]]; then
  EXTRA_OPTS="${@:2}"
  set --
fi


# default behaviour is to launch mysqld_safe
if [[ -z ${1} ]]; then

    echo "Starting MySQL..."
    start_mysql

    # Export to backup
    if [[ ${MYSQL_MODE} == backup ]]; then
        if [[ -z ${DB_REMOTE_USER} || -z ${DB_REMOTE_PASS} ]]; then
            echo
            echo "WARNING: "
            echo "  Please specify a DB_REMOTE_USER/DB_REMOTE_PASS for backup. "
            echo
            exit 1;
        fi
        if [[ -z ${EXTRA_OPTS} ]]; then
            EXTRA_OPTS="--compress --opt"
        fi
        echo "Backup database..."
        mysqldump --all-databases --host=${DB_REMOTE_HOST} --port=${DB_REMOTE_PORT} \
            --user=${DB_REMOTE_USER} --password=${DB_REMOTE_PASS} ${EXTRA_OPTS} \
        | lbzip2 -n 2 -9 > ${MYSQL_BACKUP_DIR}/backup.bz2
        rotate_backup
        exit 0;
    fi

    # Check backup
    if [[ -n ${MYSQL_CHECK} ]]; then
        echo "Check backup..."
        if [[ -z ${DB_NAME} ]]; then
          echo "Unknown database. DB_NAME does not null"
          exit 1;
        fi
        import_backup "${MYSQL_CHECK}"
        if [[ -n $(echo "SELECT schema_name FROM information_schema.schemata WHERE schema_name='${DB_NAME}';" | mysql -uroot | grep -w "${DB_NAME}") ]]; then
            echo "Success checking backup"
        else
            echo "Fail checking backup"
            exit 1
        fi
        exit 0;
    fi


    # Create admin user and pre create database
    if [ -f /tmp/.EMPTY_DB ]; then
        create_mysql_user
        create_db
        rm /tmp/.EMPTY_DB
    fi

    # Restore form backup
    if [[ -n ${MYSQL_RESTORE} && ${MYSQL_MODE} != slave ]]; then
        echo "Import dump..."
        import_backup "${MYSQL_RESTORE}"
    fi

    # Set MySQL REPLICATION - MASTER
    if [[ ${MYSQL_MODE} == master ]]; then
        echo "Configuring MySQL replication as master (2/2) ..."
        if [ ! -f /tmp/.REPLICATION_SET_2 ]; then
            if [[ -z ${REPLICATION_USER} || -z ${REPLICATION_PASS} ]]; then
                echo
                echo "WARNING: "
                echo "  Please specify a username/password for backup. "
                echo
                exit 1;
            fi
            if [[ -n $(echo "SELECT User FROM mysql.user;" | mysql -uroot | grep -w "${REPLICATION_USER}") ]]; then
                echo "Remove duplicate log user '${REPLICATION_USER}'..."
                mysql -uroot -e "REVOKE ALL PRIVILEGES ON *.* FROM '${REPLICATION_USER}'@'%'"
                mysql -uroot -e "DROP USER '${REPLICATION_USER}'@'%'"
            fi
            echo "Creating a log user '${REPLICATION_USER}:${REPLICATION_PASS}'"
            mysql -uroot -e "CREATE USER '${REPLICATION_USER}'@'%' IDENTIFIED BY '${REPLICATION_PASS}'"
            mysql -uroot -e "GRANT REPLICATION SLAVE ON *.* TO '${REPLICATION_USER}'@'%'"
            mysql -uroot -e "reset master"
            echo "Done!"
            touch /tmp/.REPLICATION_SET_2
        else
            echo "MySQL replication master already configured, skip"
        fi
    fi

    # Set MySQL REPLICATION - SLAVE
    if [[ ${MYSQL_MODE} == slave ]]; then
        echo "Configuring MySQL replication as slave (2/2) ..."
        if [[ -z ${REPLICATION_HOST} || -z ${REPLICATION_PORT} ]]; then
            echo
            echo "WARNING: "
            echo "  Please specify a replication host/port for salve. "
            echo
            exit 1;
        fi

        if [ ! -f /tmp/.REPLICATION_SET_2 ]; then
            echo "Setting master connection info on slave"
            mysql -uroot -e "CHANGE MASTER TO MASTER_HOST='${REPLICATION_HOST}',MASTER_USER='${REPLICATION_USER}',MASTER_PASSWORD='${REPLICATION_PASS}',MASTER_PORT=${REPLICATION_PORT}, MASTER_CONNECT_RETRY=30;"
            if [[ -n ${DB_REMOTE_PASS} && -z ${MYSQL_RESTORE} ]]; then
                mysqldump --all-databases --master-data --single-transaction --compress \
                    --host=${REPLICATION_HOST} --port=${REPLICATION_PORT} \
                    --user=${DB_REMOTE_USER} --password=${DB_REMOTE_PASS} | mysql -uroot
                rm -f ${MYSQL_DATA_DIR}/auto.cnf
            fi
            if [[ -n ${MYSQL_RESTORE} ]]; then
                echo "Import dump..."
                import_backup "${MYSQL_RESTORE}"
            fi
            mysql -uroot -e "START SLAVE;"
            echo "Done!"
            touch /tmp/.REPLICATION_SET_2
        else
            echo "MySQL replication slave already configured, skip"
        fi
    fi

    $(which mysqladmin) shutdown
    exec $(which mysqld_safe) ${EXTRA_OPTS}
else
    exec "$@"
fi