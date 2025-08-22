-- database service: postgres-db
-- Database: postgres-db

CREATE DATABASE IF NOT EXISTS postgres-db;
CREATE USER IF NOT EXISTS 'postgres-db'@'%' IDENTIFIED BY 'hdqsj6SxuYRBUZXwdXySKBmEvXElytMZwMJgyVxS0j0=';
GRANT ALL PRIVILEGES ON postgres-db.* TO 'postgres-db'@'%';
FLUSH PRIVILEGES;
