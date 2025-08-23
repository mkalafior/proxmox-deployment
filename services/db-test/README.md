# db-test Database Service

## Configuration
- Database Type: postgresql
- Database Name: dbtest
- Database User: dbuser
- Port: 5432

## Connection String
```
postgresql://dbuser:ov9qBtpl+UMZYfGbLrqUeI8Y6a8T56Ty74QtrDVi4Mw=@db-test.proxmox.local:5432/dbtest
```

## Management
- Connect: `psql -h db-test.proxmox.local -p 5432 -U dbuser -d dbtest`
- Backup: `pg_dump -h db-test.proxmox.local -p 5432 -U dbuser dbtest > backup.sql`
