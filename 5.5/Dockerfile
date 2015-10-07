FROM ubuntu:trusty
MAINTAINER romeOz <serggalka@gmail.com>

ENV MYSQL_USER=admin \
    MYSQL_PASS= \
    REPLICATION_USER=replica \
    REPLICATION_PASS=replica \
    REPLICATION_HOST= \
    REPLICATION_PORT=3306 \
    MYSQL_DATA_DIR=/var/lib/mysql \
    MYSQL_CONFIG=/etc/mysql/conf.d/my.cnf \
    MYSQL_RUN_DIR=/var/run/mysqld \
    MYSQL_LOG=/var/log/mysql/error.log \
    OS_LOCALE="en_US.UTF-8"

# Set the locale
RUN locale-gen ${OS_LOCALE}
ENV LANG=${OS_LOCALE} \
    LANGUAGE=en_US:en \
    LC_ALL=${OS_LOCALE}

# Add MySQL configuration
COPY my.cnf ${MYSQL_CONFIG}
COPY mysqld_charset.cnf /etc/mysql/conf.d/mysqld_charset.cnf

RUN apt-get update \
    && apt-get -yq install mysql-server-5.5 lbzip2 \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/mysql/conf.d/mysqld_safe_syslog.cnf \
    && touch /tmp/.EMPTY_DB

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 3306/tcp
VOLUME  ["${MYSQL_DATA_DIR}", "${MYSQL_RUN_DIR}"]
ENTRYPOINT ["/sbin/entrypoint.sh"]
