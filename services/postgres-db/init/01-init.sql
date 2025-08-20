-- database service: postgres-db
-- Database: myapp

CREATE DATABASE IF NOT EXISTS myapp;
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'secret123';
GRANT ALL PRIVILEGES ON myapp.* TO 'appuser'@'%';
FLUSH PRIVILEGES;
