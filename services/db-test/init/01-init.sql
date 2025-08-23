-- database service: db-test
-- Database: dbtest

CREATE DATABASE IF NOT EXISTS dbtest;
CREATE USER IF NOT EXISTS 'dbuser'@'%' IDENTIFIED BY 'ov9qBtpl+UMZYfGbLrqUeI8Y6a8T56Ty74QtrDVi4Mw=';
GRANT ALL PRIVILEGES ON dbtest.* TO 'dbuser'@'%';
FLUSH PRIVILEGES;
