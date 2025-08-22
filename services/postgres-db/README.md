# postgres-db Database Service

## Configuration
- Database Type: postgresql
- Database Name: postgres-db
- Database User: postgres-db
- Port: 5432

## Connection String
```
postgresql://postgres-db:hdqsj6SxuYRBUZXwdXySKBmEvXElytMZwMJgyVxS0j0=@postgres-db.proxmox.local:5432/postgres-db
```

## Management
- Connect: `psql -h postgres-db.proxmox.local -p 5432 -U postgres-db -d postgres-db`
- Backup: `pg_dump -h postgres-db.proxmox.local -p 5432 -U postgres-db postgres-db > backup.sql`
