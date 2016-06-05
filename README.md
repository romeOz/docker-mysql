Table of Contents
-------------------

 * [Installation](#installation)
 * [Quick Start](#quick-start)
 * [Command-line arguments](#command-line-arguments) 
 * [Setting a specific password for the admin account](#setting-a-specific-password-for-the-admin-account)
 * [Creating Database at Launch](#creating-database-at-launch)
 * [Persistence](#persistence)
 * [Backuping](#backuping)
 * [Checking backup](#checking-backup)
 * [Restore from backup](#restore-from-backup)
 * [Replication - Master/Slave](#replication---masterslave)
 * [Environment variables](#environment-variables) 
 * [Logging](#logging) 
 * [Out of the box](#out-of-the-box) 

Installation
-------------------

 * [Install Docker 1.9+](https://docs.docker.com/installation/) or [askubuntu](http://askubuntu.com/a/473720)
 * Pull the latest version of the image.
 
```bash
docker pull romeoz/docker-mysql
```

Alternately you can build the image yourself.

```bash
git clone https://github.com/romeoz/docker-mysql.git
cd docker-mysql
docker build -t="$USER/mysql" .
```

Quick Start
-------------------

Run the mysql container:

```bash
docker run --name mysql -d romeoz/docker-mysql
```

The simplest way to login to the mysql container is to use the `docker exec` command to attach a new process to the running container and connect to the MySQL Server over the unix socket.

```bash
docker exec -it mysql mysql -uroot
```

Command-line arguments
-------------------

You can customize the launch command of mysql by specifying arguments to `mysqld` on the docker run command. For example, to run mysql using lower case table name, you can do:

```bash
docker run --name db -d \
  romeoz/docker-mysql \
  --lower_case_table_names=1
```

Setting a specific password for the admin account
-------------------------------------------------

If you want to use a preset password instead of a random generated one, you can
set the environment variable `MYSQL_PASS` to your specific password when running the container:

```bash
docker run --name db -d -e 'MYSQL_PASS=mypass' romeoz/docker-mysql
```

You can now test your deployment:

```bash
docker exec -it db mysql -uadmin -pmypass
```

The admin username can also be set via the `MYSQL_USER` environment variable.

>Remember that the `root` user has no password, but it's only accessible from within the container.

Creating Database at Launch
-------------------

If you want a database to be created inside the container when you start it up
for the first time you can set the environment variable `DB_NAME` to a string
that names the database.

```bash
docker run --name mysql -d  -e 'DB_NAME=dbname' romeoz/docker-mysql
```

You may also specify a comma separated list of database names in the `DB_NAME` variable. The following command creates two new databases named *dbname1* and *dbname2* (p.s. this feature is only available in releases greater than 9.1-1).

```bash
docker run --name mysql -d \
  -e 'DB_NAME=dbname1,dbname2' \
  romeoz/docker-mysql
```

If this is combined with importing SQL files, those files will be imported into the
created database.

Persistence
-------------------

For data persistence a volume should be mounted at `/var/lib/mysql`.

SELinux users are also required to change the security context of the mount point so that it plays nicely with selinux.

```bash
mkdir -p /to/path/data
sudo chcon -Rt svirt_sandbox_file_t /to/path/data
```

The updated run command looks like this.

```bash
docker run --name mysql -d \
  -v /host/to/path/data:/var/lib/mysql \
  romeoz/docker-mysql
```

This will make sure that the data stored in the database is not lost when the container is stopped and started again.

Backuping
-------------------

The backup all databases is made over a regular MySQL connection (used [mysqldump](https://dev.mysql.com/doc/refman/5.7/en/mysqldump.html)).

Create a temporary container for backup:

```bash
docker run -it --rm \
    --net mysql_net \
    -e 'MYSQL_MODE=backup' \
    -e 'DB_REMOTE_HOST=mysql' -e 'DB_REMOTE_USER=admin' -e 'DB_REMOTE_PASS=pass' \
    -v /host/to/path/backup:/tmp/backup \
    romeoz/docker-mysql
```
 
Archive will be available in the `/host/to/path/backup`.

> Algorithm: one backup per week (total 4), one backup per month (total 12) and the last backup. Example: `backup.last.tar.bz2`, `backup.1.tar.bz2` and `/backup.dec.tar.bz2`.

To pass additional settings to `mysqldump`, you can use command-line arguments:

```bash
docker run -it --rm \
    --net mysql_net \
    -e 'MYSQL_MODE=backup' \    
    -e 'DB_REMOTE_HOST=mysql' -e 'DB_REMOTE_USER=admin' -e 'DB_REMOTE_PASS=pass' \
    -v /host/to/path/backup:/tmp/backup \    
    romeoz/docker-mysql \
    --master-data --single-transaction
```

Checking backup
-------------------

Check-data is the name of database `DB_NAME`. 

```bash
docker run -it --rm \
    -e 'MYSQL_CHECK=default' \
    -e 'DB_NAME=foo' \
    -v /host/to/path/backup:/tmp/backup \
    romeoz/docker-mysql
```

Default used the `/tmp/backup/backup.last.bz2`.

Restore from backup
-------------------

```bash
docker run --name='db_restore' -d \
  -e 'MYSQL_RESTORE=default' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mysql
```

Also see ["Replication"](replication---masterslave).

Replication - Master/Slave
-------------------------

You may use the `MYSQL_MODE` variable along with `REPLICATION_HOST`, `REPLICATION_PORT`, `REPLICATION_USER` and `REPLICATION_PASS` to enable replication.

Your master database must support replication or super-user access for the credentials you specify. The `MYSQL_MODE` variable should be set to `master`, for replication on your master node and `slave` for replication or a point-in-time snapshot of a running instance.

Create a master instance with database `dbname`

```bash
docker network create mysql_net

docker run --name='mysql-master' -d \
  -e 'MYSQL_MODE=master' \
  -e 'DB_NAME=dbname' \
  -e 'MYSQL_USER=dbuser' -e 'MYSQL_PASS=dbpass' \
  romeoz/docker-mysql
```

or import backup

```bash
docker network create mysql_net

docker run --name='mysql-master' -d \
  -e 'MYSQL_MODE=master' \
  -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' \
  -e 'MYSQL_USER=dbuser' -e 'MYSQL_PASS=dbpass' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mysql
```

Create a slave instance + fast import backup from master

```bash
docker run --name='mysql-slave' -d  \
  --net mysql_net  \
  -e 'MYSQL_MODE=slave' -e 'MYSQL_PASS=pass' \
  -e 'REPLICATION_HOST=mysql-master' \
  -e 'DB_REMOTE_USER=dbuser' -e 'DB_REMOTE_PASS=dbpass' \
  romeoz/docker-mysql
```

Variables `DB_REMOTE_USER` and `DB_REMOTE_PASS` is master settings. 

or import as backup file

```bash
docker run --name='mysql-slave' -d  \
  --net mysql_net  \
  -e 'MYSQL_MODE=slave' -e 'MYSQL_PASS=pass' \
  -e 'REPLICATION_HOST=mysql-master' \
  -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mysql
```

>Protection against unauthorized inserting records `docker exec -it mysql-slave mysql -uroot -e 'GRANT SELECT ON *.* TO "web"@"%" WITH GRANT OPTION;'`

Environment variables
---------------------

`MYSQL_USER`: Set a specific username for the admin account (default 'admin').

`MYSQL_PASS`: Set a specific password for the admin account.

`MYSQL_MODE`: Set a specific mode. Takes on the values `master`, `slave` or `backup`.

`MYSQL_BACKUP_DIR`: Set a specific backup directory (default '/tmp/backup').

`MYSQL_BACKUP_FILENAME`: Set a specific filename backup (default 'backup.last.bz2').

`MYSQL_CHECK`: Defines one SQL script/dump to initialize the database. Note that the dump must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.bz2`

`MYSQL_RESTORE`: Defines one or more SQL scripts/dumps separated by spaces to initialize the database. Note that the scripts must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.bz2`

`MYSQL_ROTATE_BACKUP`: Determines whether to use the rotation of backups (default "true").

`REPLICATION_PORT`: Set a specific replication port for the master instance (default '3306').

`REPLICATION_USER`: Set a specific replication username for the master instance (default 'replica').

`REPLICATION_PASS`: Set a specific replication password for the master instance (default 'replica').

Logging
-------------------

All the logs are forwarded to stdout and sterr. You have use the command `docker logs`.

```bash
docker logs mysql
```

####Split the logs

You can then simply split the stdout & stderr of the container by piping the separate streams and send them to files:

```bash
docker logs mysql > stdout.log 2>stderr.log
cat stdout.log
cat stderr.log
```

or split stdout and error to host stdout:

```bash
docker logs mysql > -
docker logs mysql 2> -
```

####Rotate logs

Create the file `/etc/logrotate.d/docker-containers` with the following text inside:

```
/var/lib/docker/containers/*/*.log {
    rotate 31
    daily
    nocompress
    missingok
    notifempty
    copytruncate
}
```
> Optionally, you can replace `nocompress` to `compress` and change the number of days.

Out of the box
-------------------
 * Ubuntu 14.04 or 16.04 LTS
 * MySQL 5.5, 5.6 or 5.7
 
>Environment depends on the version of MySQL. 

License
-------------------

MySQL docker image is open-sourced software licensed under the [MIT license](http://opensource.org/licenses/MIT).