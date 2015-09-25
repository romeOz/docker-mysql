FROM ubuntu:trusty
MAINTAINER romeOz <serggalka@gmail.com>

ENV MYSQL_USER=admin \
    MYSQL_PASS= \
    MYSQL_MODE=standalone \
    REPLICATION_USER=replica \
    REPLICATION_PASS=replica \
    REPLICATION_HOST= \
    REPLICATION_PORT=3306 \
    MYSQL_HOME=/var/lib/mysql \
    MYSQL_CONFIG=/etc/mysql/conf.d/my.cnf \
    MYSQL_LOG=/var/log/mysql/error.log \
    OS_LOCALE="en_US.UTF-8"

# Set the locale
RUN locale-gen ${OS_LOCALE}
ENV LANG ${OS_LOCALE}
ENV	LANGUAGE en_US:en
ENV	LC_ALL ${OS_LOCALE}

# Add MySQL configuration
ADD my.cnf /etc/mysql/conf.d/my.cnf
ADD mysqld_charset.cnf /etc/mysql/conf.d/mysqld_charset.cnf

RUN apt-get update \
    && apt-get -yq install mysql-server-5.6 pwgen lbzip2 \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/mysql/conf.d/mysqld_safe_syslog.cnf \
    && if [ ! -f /usr/share/mysql/my-default.cnf ] ; then cp /etc/mysql/my.cnf /usr/share/mysql/my-default.cnf; fi \
    && mysql_install_db > /dev/null 2>&1 \
    && touch /var/lib/mysql/.EMPTY_DB

# Add MySQL scripts
ADD run.sh /run.sh

# Add VOLUMEs to allow backup of config and databases
VOLUME  ["/etc/mysql", "/var/lib/mysql"]

EXPOSE 3306/tcp
CMD ["/run.sh"]
