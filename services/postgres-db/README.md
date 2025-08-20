# postgres-db Database Service

## Configuration
- Database Type: postgresql
- Database Name: myapp
- Database User: appuser
- Port: 5432

## Connection String
```
postgresql://appuser:secret123@postgres-db.proxmox.local:5432/myapp
```

## Management
- Connect: `psql -h postgres-db.proxmox.local -p 5432 -U appuser -d myapp`
- Backup: `pg_dump -h postgres-db.proxmox.local -p 5432 -U appuser myapp > backup.sql`
