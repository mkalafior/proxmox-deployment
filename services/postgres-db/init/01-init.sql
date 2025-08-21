-- database service: postgres-db
-- Database: postgres-db

CREATE DATABASE IF NOT EXISTS postgres-db;
CREATE USER IF NOT EXISTS 'postgres-db'@'%' IDENTIFIED BY 'secure_postgres_password_123';
GRANT ALL PRIVILEGES ON postgres-db.* TO 'postgres-db'@'%';
FLUSH PRIVILEGES;
