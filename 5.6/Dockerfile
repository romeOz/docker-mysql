FROM ubuntu:trusty
MAINTAINER romeOz <serggalka@gmail.com>

ENV MYSQL_USER=admin \
    MYSQL_PASS= \
    MYSQL_MODE=standalone \
    REPLICATION_USER=replica \
    REPLICATION_PASS=replica \
    REPLICATION_HOST= \
    REPLICATION_PORT=3306 \
    MYSQL_DATADIR=/var/lib/mysql \
    MYSQL_CONFIG=/etc/mysql/conf.d/my.cnf \
    MYSQL_RUNDIR=/var/run/mysqld \
    MYSQL_LOG=/var/log/mysql/error.log \
    OS_LOCALE="en_US.UTF-8"

# Set the locale
RUN locale-gen ${OS_LOCALE}
ENV LANG ${OS_LOCALE}
ENV	LANGUAGE en_US:en
ENV	LC_ALL ${OS_LOCALE}

# Add MySQL configuration
COPY my.cnf ${MYSQL_CONFIG}
COPY mysqld_charset.cnf /etc/mysql/conf.d/mysqld_charset.cnf

RUN apt-get update \
    && apt-get -yq install mysql-server-5.6 lbzip2 \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/mysql/conf.d/mysqld_safe_syslog.cnf \
    && touch /var/lib/mysql/.EMPTY_DB

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 3306/tcp
VOLUME  ["${MYSQL_DATADIR}", "${MYSQL_RUNDIR}"]
ENTRYPOINT ["/sbin/entrypoint.sh"]
