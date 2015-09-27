Table of Contents
-------------------

 * [Installation](#installation)
 * [Quick Start](#quick-start)
 * [Passing extra configuration to start mysql server](#passing-extra-configuration-to-start-mysql-server)
 * [Setting a specific password for the admin account](#setting-a-specific-password-for-the-admin-account)
 * [Creating Database at Launch](#creating-database-at-launch)
 * [Persistence](#persistence)
 * [Replication - Master/Slave](#replication---masterslave)
 * [Backup of a MySQL cluster](#backup-of-a-mysql-cluster)
 * [Checking backup](#checking-backup)
 * [Restore from backup](#restore-from-backup)
 * [Environment variables](#environment-variables) 
 * [Logging](#logging)
 * [Upgrading](#upgrading)
 * [Out of the box](#out-of-the-box)
 

Installation
-------------------

 * [Install Docker](https://docs.docker.com/installation/) or [askubuntu](http://askubuntu.com/a/473720)
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

Run the mysql image:

```bash
docker run --name mysql -d romeoz/docker-mysql
```

The first time that you run your container, a new user `admin` with all privileges
will be created in MySQL with a random password. To get the password, check the logs
of the container by running:

```bash
docker logs <CONTAINER_ID>
```

You will see an output like the following:

        ========================================================================
        You can now connect to this MySQL Server using:
        
            mysql -uadmin -p47nnf4FweaKu -h<host> -P<port>
        
        Please remember to change the above password as soon as possible!
        MySQL user 'root' has no password but only allows local connections.
        ========================================================================

In this case, `47nnf4FweaKu` is the password allocated to the `admin` user.

Remember that the `root` user has no password, but it's only accessible from within the container.

The simplest way to login to the mysql container is to use the `docker exec` command to attach a new process to the running container and connect to the MySQL Server over the unix socket.

```bash
docker exec -it mysql mysql -uroot
```

Passing extra configuration to start mysql server
------------------------------------------------

To pass additional settings to `mysqld`, you can use environment variable `EXTRA_OPTS`.
For example, to run mysql using lower case table name, you can do:

```bash
docker run -d -e 'EXTRA_OPTS=--lower_case_table_names=1' romeoz/docker-mysql
```

Setting a specific password for the admin account
-------------------------------------------------

If you want to use a preset password instead of a random generated one, you can
set the environment variable `MYSQL_PASS` to your specific password when running the container:

```bash
docker run -d -e 'MYSQL_PASS=mypass' romeoz/docker-mysql
```

You can now test your deployment:

```bash
docker exec -it db mysql -uadmin -pmypass
```

The admin username can also be set via the `MYSQL_USER` environment variable.

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

This will make sure that the data stored in the database is not lost when the image is stopped and started again.

Replication - Master/Slave
-------------------------

You may use the `MYSQL_MODE` variable along with `REPLICATION_HOST`, `REPLICATION_PORT`, `REPLICATION_USER` and `REPLICATION_PASS` to enable replication.

Your master database must support replication or super-user access for the credentials you specify. The `MYSQL_MODE` variable should be set to `master`, for replication on your master node and `slave` for replication or a point-in-time snapshot of a running instance.

Create a master instance with database `dbname`

```bash
docker run --name='mysql-master' -d \
  -e 'MYSQL_MODE=master' \
  -e 'DB_NAME=dbname' \
  -e 'MYSQL_USER=dbuser' -e 'MYSQL_PASS=dbpass' \
  romeoz/docker-mysql
```

or import backup

```bash
docker run --name='mysql-master' -d \
  -e 'MYSQL_MODE=master' \
  -e 'MYSQL_IMPORT=/tmp/backup/backup.last.bz2' \
  -e 'MYSQL_USER=dbuser' -e 'MYSQL_PASS=dbpass' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mysql
```

Create a slave instance + fast import backup from master

```bash
docker run --name='mysql-slave' -d  \
  --link mysql-master:mysql-master  \
  -e 'MYSQL_MODE=slave' -e 'MYSQL_PASS=pass' \
  -e 'REPLICATION_HOST=mysql-master' \
  -e 'DB_REMOTE_USER=dbuser' -e 'DB_REMOTE_PASS=dbpass' \
  romeoz/docker-mysql
```

Variables `DB_REMOTE_USER` and `DB_REMOTE_PASS` is master settings. 

or import as backup file

```bash
docker run --name='mysql-slave' -d  \
  --link mysql-master:mysql-master  \
  -e 'MYSQL_MODE=slave' -e 'MYSQL_PASS=pass' \
  -e 'REPLICATION_HOST=mysql-master' \
  -e 'MYSQL_IMPORT=/tmp/backup/backup.last.bz2' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mysql
```

>Protection against unauthorized inserting records `docker exec -it mysql-slave mysql -uroot -e 'GRANT SELECT ON *.* TO "web"@"%" WITH GRANT OPTION;'`

Backup of a MySQL cluster
-------------------

The backup all databases is made over a regular MySQL connection (used [mysqldump](https://dev.mysql.com/doc/refman/5.6/en/mysqldump.html)).

Create a temporary container for backup:

```bash
docker run -it --rm \
    --link mysql:mysql \
    -e 'MYSQL_MODE=backup' \
    -e 'DB_REMOTE_HOST=mysql' -e 'DB_REMOTE_USER=admin' -e 'DB_REMOTE_PASS=pass' \
    -v /host/to/path/backup:/tmp/backup \
    romeoz/docker-mysql
```
 
Archive will be available in the `/host/to/path/backup`.

> Algorithm: one backup per week (total 4), one backup per month (total 12) and the last backup. Example: `backup.last.tar.bz2`, `backup.1.tar.bz2` and `/backup.dec.tar.bz2`.

To pass additional settings to `mysqldump`, you can use environment variable `BACKUP_OPTS`.

```bash
docker run -it --rm \
    --link mysql-master:mysql-master \
    -e 'MYSQL_MODE=backup' \
    -e 'BACKUP_OPTS=--master-data --single-transaction' \
    -e 'DB_REMOTE_HOST=mysql' -e 'DB_REMOTE_USER=admin' -e 'DB_REMOTE_PASS=pass' \
    -v /host/to/path/backup:/tmp/backup \    
    romeoz/docker-mysql
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
  -e 'MYSQL_IMPORT=default' \
  -v /host/to/path/backup:/tmp/backup \
  romeoz/docker-mysql
```

Also, see ["Replication"](replication---masterslave).

Environment variables
---------------------

`MYSQL_USER`: Set a specific username for the admin account (default 'admin').

`MYSQL_PASS`: Set a specific password for the admin account.

`REPLICATION_PORT`: Set a specific replication port for the master instance (default '3306').

`REPLICATION_USER`: Set a specific replication username for the master instance (default 'replica').

`REPLICATION_PASS`: Set a specific replication password for the master instance (default 'replica').

`MYSQL_BACKUP_DIR`: Set a specific backup directory (default '/tmp/backup').

`MYSQL_BACKUP_FILENAME`: Set a specific filename backup (default 'backup.last.bz2').

`MYSQL_IMPORT`: Defines one or more SQL scripts/dumps separated by spaces to initialize the database. Note that the scripts must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.bz2`
 
`MYSQL_CHECK`: Defines one SQL script/dump to initialize the database. Note that the dump must be inside the container, so you may need to mount them. You can specify as `default` that is equivalent to the `/tmp/backup/backup.last.bz2`

`MYSQL_MODE`: Set a specific mode. Takes on the values `master`, `slave` or `backup`.

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

Upgrading
-------------------

To upgrade to newer releases, simply follow this 3 step upgrade procedure.

- **Step 1**: Stop the currently running image

```bash
docker stop mysql
```

- **Step 2**: Update the docker image.

```bash
docker pull romeoz/docker-mysql
```

- **Step 3**: Start the image

```bash
docker run --name mysql -d [OPTIONS] romeoz/docker-mysql
```

Out of the box
-------------------
 * Ubuntu 14.04.3 (LTS)
 * MySQL 5.5/5.6

License
-------------------

MySQL container image is open-sourced software licensed under the [MIT license](http://opensource.org/licenses/MIT)