#!/bin/bash

set -e

echo "-- Building mysql 5.5 image"
docker build -t mysql-5.5 5.5/
DIR_VOLUME=$(pwd)/vol55
mkdir -p ${DIR_VOLUME}/backup

echo
echo "-- Testing mysql 5.5 is running"
docker run --name base_1 -d -e MYSQL_USER=user  -e 'MYSQL_PASS=test' mysql-5.5; sleep 10
docker run --name base_2 -d --link base_1:base_1 mysql-5.5; sleep 10
docker exec -it base_2 bash -c 'mysqladmin -uuser -ptest -h${BASE_1_PORT_3306_TCP_ADDR} ping | grep -c "mysqld is alive"'
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5

echo
echo "-- Testing backup/checking on mysql 5.5"
docker run --name base_1 -d -e MYSQL_USER=user  -e 'MYSQL_PASS=test' -e 'DB_NAME=db_1,test_1' mysql-5.5; sleep 10
docker run -it --rm --link base_1:base_1 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=test' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.5; sleep 10
docker run -it --rm -e 'MYSQL_CHECK=default' -e 'DB_NAME=db_1' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.5 | tail -n 1 | grep -c 'Success'; sleep 10
docker run -it --rm -e 'MYSQL_CHECK=/tmp/backup/backup.last.bz2' -e 'DB_NAME=test_1' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.5 | tail -n 1 | grep -c 'Success'; sleep 10
docker run -it --rm -e 'MYSQL_CHECK=default' -e 'DB_NAME=db' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.5 2>&1 | tail -n 1 | grep -c 'Fail'; sleep 10
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
rm -r ${DIR_VOLUME}


echo
echo
echo "-- Testing master/slave on mysql 5.5"
docker run --name base_1 -d -e 'MYSQL_MODE=master' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'DB_NAME=db_1,test_1' mysql-5.5; sleep 10
docker exec -it base_1 mysql -uroot -e 'CREATE TABLE test_1.foo (id INT NOT NULL AUTO_INCREMENT, name VARCHAR(100), PRIMARY KEY(id)) ENGINE = INNODB; INSERT INTO test_1.foo (name) VALUES ("Petr");'
echo
echo "-- Create slave"
docker run --name base_2 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' mysql-5.5; sleep 10
docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Linda");'; sleep 5
docker exec -it base_2 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Linda"
echo
echo "-- Backup master"
docker run -it --rm --link base_1:base_1 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -v ${DIR_VOLUME}/backup_master:/tmp/backup mysql-5.5 --master-data --single-transaction; sleep 10
echo
echo "-- Restore slave from master-file"
docker run --name base_3 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' -v ${DIR_VOLUME}/backup_master:/tmp/backup  mysql-5.5; sleep 10
docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Tom");'; sleep 5
docker run --name base_4 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=default' -v ${DIR_VOLUME}/backup_master:/tmp/backup  mysql-5.5; sleep 10
docker exec -it base_3 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Tom"
echo
echo "-- Backup slave"
docker run -it --rm --link base_4:base_4 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_4' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -v  ${DIR_VOLUME}/backup_slave:/tmp/backup mysql-5.5 --dump-slave; sleep 10
echo
echo "-- Restore slave from slave-file"
docker run --name base_5 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' -v ${DIR_VOLUME}/backup_slave:/tmp/backup  mysql-5.5; sleep 10
docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Bob");'; sleep 5
docker exec -it base_5 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Bob"
docker exec -it base_1 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4"
docker exec -it base_2 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4"
docker exec -it base_3 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4"
docker exec -it base_4 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4"
docker exec -it base_5 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4"
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
echo
echo "-- Restore master from master-file"
docker run --name restore_1 -d -e 'MYSQL_MODE=master' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=default' -v ${DIR_VOLUME}/backup_master:/tmp/backup mysql-5.5; sleep 10
docker run --name restore_2 -d --link restore_1:restore_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=restore_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass'  mysql-5.5; sleep 10
docker exec -it restore_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Romeo");'; sleep 5
docker exec -it restore_1 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Romeo";
docker exec -it restore_1 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "3"
docker exec -it restore_2 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "3"
echo
echo "-- Clear"
docker rm -f -v $(sudo docker ps -aq); sleep 5
docker rmi mysql-5.5; sleep 5
rm -r ${DIR_VOLUME}



#echo
#echo
#echo "-- Building mysql 5.6 image"
#docker build -t mysql-5.6 5.6/
#DIR_VOLUME=$(pwd)/vol56
#mkdir -p ${DIR_VOLUME}/backup
#
#echo
#echo "-- Testing mysql 5.6 is running"
#docker run --name base_1 -d -e MYSQL_USER=user  -e 'MYSQL_PASS=test' mysql-5.6; sleep 10
#docker run --name base_2 -d --link base_1:base_1 mysql-5.6; sleep 10
#docker exec -it base_2 bash -c 'mysqladmin -uuser -ptest -h${BASE_1_PORT_3306_TCP_ADDR} ping | grep -c "mysqld is alive"'
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#
#echo
#echo "-- Testing backup/checking on mysql 5.6"
#docker run --name base_1 -d -e MYSQL_USER=user  -e 'MYSQL_PASS=test' -e 'DB_NAME=db_1,test_1' mysql-5.6; sleep 10
#docker run -it --rm --link base_1:base_1 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=test' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.6; sleep 10
#docker run -it --rm -e 'MYSQL_CHECK=default' -e 'DB_NAME=db_1' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.6 | tail -n 1 | grep -c 'Success'; sleep 10
#docker run -it --rm -e 'MYSQL_CHECK=/tmp/backup/backup.last.bz2' -e 'DB_NAME=test_1' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.6 | tail -n 1 | grep -c 'Success'; sleep 10
#docker run -it --rm -e 'MYSQL_CHECK=default' -e 'DB_NAME=db' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.6 2>&1 | tail -n 1 | grep -c 'Fail'; sleep 10
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#rm -r ${DIR_VOLUME}
#
#
#echo
#echo
#echo "-- Testing master/slave on mysql 5.6"
#docker run --name base_1 -d -e 'MYSQL_MODE=master' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'DB_NAME=db_1,test_1' mysql-5.6; sleep 10
#docker exec -it base_1 mysql -uroot -e 'CREATE TABLE test_1.foo (id INT NOT NULL AUTO_INCREMENT, name VARCHAR(100), PRIMARY KEY(id)) ENGINE = INNODB; INSERT INTO test_1.foo (name) VALUES ("Petr");'
#echo
#echo "-- Create slave"
#docker run --name base_2 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' mysql-5.6; sleep 10
#docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Linda");'; sleep 5
#docker exec -it base_2 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Linda"
#echo
#echo "-- Backup master"
#docker run -it --rm --link base_1:base_1 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -v ${DIR_VOLUME}/backup_master:/tmp/backup mysql-5.6 --master-data --single-transaction; sleep 10
#echo
#echo "-- Restore slave from master-file"
#docker run --name base_3 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' -v ${DIR_VOLUME}/backup_master:/tmp/backup  mysql-5.6; sleep 10
#docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Tom");'; sleep 5
#docker run --name base_4 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=default' -v ${DIR_VOLUME}/backup_master:/tmp/backup  mysql-5.6; sleep 10
#docker exec -it base_3 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Tom"
#echo
#echo "-- Backup slave"
#docker run -it --rm --link base_4:base_4 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_4' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -v  ${DIR_VOLUME}/backup_slave:/tmp/backup mysql-5.6 --dump-slave; sleep 15
#echo
#echo "-- Restore slave from slave-file"
#docker run --name base_5 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' -v ${DIR_VOLUME}/backup_slave:/tmp/backup  mysql-5.6; sleep 15
#docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Bob");'; sleep 10
#docker exec -it base_5 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Bob"
#docker exec -it base_1 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_2 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_3 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_4 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_5 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4"
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#echo
#echo "-- Restore master from master-file"
#docker run --name restore_1 -d -e 'MYSQL_MODE=master' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=default' -v ${DIR_VOLUME}/backup_master:/tmp/backup mysql-5.6; sleep 15
#docker run --name restore_2 -d --link restore_1:restore_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=restore_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass'  mysql-5.6; sleep 15
#docker exec -it restore_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Romeo");'; sleep 5
#docker exec -it restore_1 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Romeo";
#docker exec -it restore_1 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "3"
#docker exec -it restore_2 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "3"
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#docker rmi mysql-5.6; sleep 5
#rm -r ${DIR_VOLUME}



#echo
#echo
#echo "-- Building mysql 5.7 image"
#docker build -t mysql-5.7 5.7/
#DIR_VOLUME=$(pwd)/vol57
#mkdir -p ${DIR_VOLUME}/backup
#
#echo
#echo "-- Testing mysql 5.7 is running"
#docker run --name base_1 -d -e MYSQL_USER=user  -e 'MYSQL_PASS=test' mysql-5.7; sleep 10
#docker run --name base_2 -d --link base_1:base_1 mysql-5.7; sleep 10
#docker exec -it base_2 bash -c 'mysqladmin -uuser -ptest -h${BASE_1_PORT_3306_TCP_ADDR} ping | grep -c "mysqld is alive"'
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#
#echo
#echo "-- Testing backup/checking on mysql 5.7"
#docker run --name base_1 -d -e MYSQL_USER=user  -e 'MYSQL_PASS=test' -e 'DB_NAME=db_1,test_1' mysql-5.7; sleep 10
#docker run -it --rm --link base_1:base_1 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=test' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.7; sleep 10
#docker run -it --rm -e 'MYSQL_CHECK=default' -e 'DB_NAME=db_1' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.7 | tail -n 1 | grep -c 'Success'; sleep 10
#docker run -it --rm -e 'MYSQL_CHECK=/tmp/backup/backup.last.bz2' -e 'DB_NAME=test_1' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.7 | tail -n 1 | grep -c 'Success'; sleep 10
#docker run -it --rm -e 'MYSQL_CHECK=default' -e 'DB_NAME=db' -v ${DIR_VOLUME}/backup:/tmp/backup mysql-5.7 2>&1 | tail -n 1 | grep -c 'Fail'; sleep 10
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#rm -r ${DIR_VOLUME}
#
#
#echo
#echo
#echo "-- Testing master/slave on mysql 5.7"
#docker run --name base_1 -d -e 'MYSQL_MODE=master' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'DB_NAME=db_1,test_1' mysql-5.7; sleep 10
#docker exec -it base_1 mysql -uroot -e 'CREATE TABLE test_1.foo (id INT NOT NULL AUTO_INCREMENT, name VARCHAR(100), PRIMARY KEY(id)) ENGINE = INNODB; INSERT INTO test_1.foo (name) VALUES ("Petr");'
#echo
#echo "-- Create slave"
#docker run --name base_2 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' mysql-5.7; sleep 20
#docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Linda");'; sleep 5
#docker exec -it base_2 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Linda"
#echo
#echo "-- Backup master"
#docker run -it --rm --link base_1:base_1 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_1' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -v ${DIR_VOLUME}/backup_master:/tmp/backup mysql-5.7 --master-data --single-transaction; sleep 15
#echo
#echo "-- Restore slave from master-file"
#docker run --name base_3 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' -v ${DIR_VOLUME}/backup_master:/tmp/backup  mysql-5.7; sleep 20
#docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Tom");'; sleep 5
#docker run --name base_4 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=default' -v ${DIR_VOLUME}/backup_master:/tmp/backup  mysql-5.7; sleep 25
#docker exec -it base_3 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Tom"
#echo
#echo "-- Backup slave"
#docker run -it --rm --link base_4:base_4 -e 'MYSQL_MODE=backup' -e 'DB_REMOTE_HOST=base_4' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass' -v  ${DIR_VOLUME}/backup_slave:/tmp/backup mysql-5.7 --dump-slave; sleep 15
#echo
#echo "-- Restore slave from slave-file"
#docker run --name base_5 -d --link base_1:base_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=base_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=/tmp/backup/backup.last.bz2' -v ${DIR_VOLUME}/backup_slave:/tmp/backup  mysql-5.7; sleep 20
#docker exec -it base_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Bob");'; sleep 10
#docker exec -it base_5 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Bob"
#docker exec -it base_1 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_2 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_3 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_4 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4";sleep 3
#docker exec -it base_5 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "4"
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#echo
#echo "-- Restore master from master-file"
#docker run --name restore_1 -d -e 'MYSQL_MODE=master' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'MYSQL_RESTORE=default' -v ${DIR_VOLUME}/backup_master:/tmp/backup mysql-5.7; sleep 20
#docker run --name restore_2 -d --link restore_1:restore_1 -e 'MYSQL_MODE=slave' -e 'REPLICATION_HOST=restore_1' -e MYSQL_USER=user -e 'MYSQL_PASS=pass' -e 'DB_REMOTE_USER=user' -e 'DB_REMOTE_PASS=pass'  mysql-5.7; sleep 20
#docker exec -it restore_1 mysql -uroot -e 'INSERT INTO test_1.foo (name) VALUES ("Romeo");'; sleep 5
#docker exec -it restore_1 mysql -uroot -e 'SELECT * FROM test_1.foo;' | grep -c -w "Romeo";
#docker exec -it restore_1 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "3"
#docker exec -it restore_2 mysql -uroot -e 'SELECT COUNT(*) FROM test_1.foo;' | grep -c -w "3"
#echo
#echo "-- Clear"
#docker rm -f -v $(sudo docker ps -aq); sleep 5
#docker rmi mysql-5.7; sleep 5
#rm -r ${DIR_VOLUME}

echo
echo "-- Done"