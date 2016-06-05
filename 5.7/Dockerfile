FROM ubuntu:xenial
MAINTAINER romeOz <serggalka@gmail.com>

ENV MYSQL_USER=admin \
    MYSQL_PASS= \
    REPLICATION_USER=replica \
    REPLICATION_PASS=replica \
    REPLICATION_HOST= \
    REPLICATION_PORT=3306 \
    MYSQL_DATA_DIR=/var/lib/mysql \
    MYSQL_CONFIG=/etc/mysql/conf.d/custom.cnf \
    MYSQL_RUN_DIR=/var/run/mysqld \
    MYSQL_LOG=/var/log/mysql/error.log \
    OS_LOCALE="en_US.UTF-8"

# Set the locale
RUN locale-gen ${OS_LOCALE}
ENV LANG=${OS_LOCALE} \
    LANGUAGE=en_US:en \
    LC_ALL=${OS_LOCALE}

RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 5072E1F5 \
    && echo "deb http://repo.mysql.com/apt/ubuntu/ xenial mysql-5.7" | tee /etc/apt/sources.list.d/mysql.list \
    && apt-get update \
    && apt-get -yq install mysql-server mysql-client lbzip2 \
    && rm -rf /etc/mysql/* \
    && mkdir /etc/mysql/conf.d \
    && rm -rf /var/lib/apt/lists/* \
    && touch /tmp/.EMPTY_DB \
    # Forward request and error logs to docker log collector
    && ln -sf /dev/stderr ${MYSQL_LOG}

# Add MySQL configuration
COPY my.cnf /etc/mysql/my.cnf
COPY custom.cnf ${MYSQL_CONFIG}

COPY entrypoint.sh /sbin/entrypoint.sh
RUN chmod 755 /sbin/entrypoint.sh

EXPOSE 3306/tcp
VOLUME  ["${MYSQL_DATA_DIR}", "${MYSQL_RUN_DIR}"]
ENTRYPOINT ["/sbin/entrypoint.sh"]