# Signal CLI REST API Service Type - Deployment Guide

This service type provides a complete deployment solution for the Signal CLI REST API in LXC containers, replicating the functionality of the Docker version but with native LXC integration.

## What This Service Type Provides

### ✅ Complete Signal CLI REST API Stack
- **Signal CLI**: Latest version (configurable) with Java runtime
- **REST API**: Go-based wrapper providing HTTP endpoints
- **Multiple Modes**: Support for normal, native, and json-rpc execution modes
- **Systemd Integration**: Native service management with proper logging
- **Health Monitoring**: Comprehensive health checks and monitoring
- **Data Persistence**: Signal configuration persists across deployments

### ✅ Key Features Replicated from Docker
- Multi-stage build process (runtime + dependency installation)
- Environment variable configuration
- Auto-receive scheduling support
- Health check endpoints
- Swagger API documentation
- Security hardening with dedicated user
- Resource limits and protection

## File Structure

```
deployment-templates/service-types/signal-api/
├── config.yml                           # Service type configuration
├── runtime_install.yml.j2               # Java + Go + build tools installation
├── dependency_install.yml.j2            # Signal CLI + REST API build process
├── systemd.service.j2                   # Systemd service configuration
├── health_check.yml.j2                  # Health monitoring tasks
├── redeploy_tasks.yml.j2                # Redeployment and update tasks
├── restart.yml.j2                       # Service restart tasks
├── templates/
│   └── signal-api-wrapper.sh.j2         # Service wrapper script
└── starter/
    ├── README.md.j2                     # Service documentation
    └── env.example.j2                   # Environment configuration example
```

## How to Use

### 1. Create a Service Configuration

Create a service configuration file (e.g., `services/my-signal-api/service-config.yml`):

```yaml
service_name: my-signal-api
service_type: signal-api
app_port: 8080

# Signal-specific configuration
signal_cli_version: "0.13.5"
java_version: "17"
enable_native_mode: false

# Environment variables
env:
  MODE: "normal"  # Options: normal, native, json-rpc
  LOG_LEVEL: "info"
  AUTO_RECEIVE_SCHEDULE: "0 22 * * *"  # Optional: daily at 10 PM

# Container configuration
container_template: "ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
container_cores: 2
container_memory: 2048
container_disk: 10
```

### 2. Deploy the Service

```bash
# Deploy to Proxmox
./tools/proxmox-deploy services/my-signal-api

# Or use the CLI tool
pxd deploy my-signal-api
```

### 3. Configure Signal

After deployment, you need to register a phone number:

```bash
# Get the container IP
SIGNAL_API_IP=$(pxd ip my-signal-api)

# Register a phone number
curl -X POST "http://$SIGNAL_API_IP:8080/v1/register" \
  -H "Content-Type: application/json" \
  -d '{"number": "+1234567890"}'

# Verify with SMS code
curl -X POST "http://$SIGNAL_API_IP:8080/v1/verify" \
  -H "Content-Type: application/json" \
  -d '{"number": "+1234567890", "code": "123456"}'
```

## Configuration Options

### Service Type Specific Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `signal_cli_version` | `0.13.5` | Signal CLI version to install |
| `java_version` | `17` | Java version for Signal CLI |
| `graalvm_version` | `22.3.0` | GraalVM version for native mode |
| `enable_native_mode` | `false` | Enable GraalVM native compilation |
| `cleanup_source` | `false` | Remove source code after build |

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MODE` | `normal` | Execution mode: normal, native, json-rpc |
| `PORT` | `8080` | Service port |
| `LOG_LEVEL` | `info` | Log level: debug, info, warn, error |
| `SIGNAL_CLI_CONFIG_DIR` | `/opt/signal-api/data` | Signal data directory |
| `AUTO_RECEIVE_SCHEDULE` | `` | Cron schedule for auto-receive |

## Execution Modes

### Normal Mode (Default)
- Uses Java-based signal-cli for each request
- Higher latency but most stable
- Lower memory usage when idle

### Native Mode
- Uses GraalVM-compiled native binary
- Lower latency and memory usage
- Requires `enable_native_mode: true` in config

### JSON-RPC Mode
- Single persistent signal-cli daemon
- Fastest performance
- Higher memory usage

## Advantages Over Docker

1. **Native Integration**: Direct systemd, logging, and monitoring
2. **Better Performance**: No container runtime overhead
3. **Persistent Storage**: No volume mapping complexity
4. **Easier Debugging**: Direct access to processes and logs
5. **Resource Efficiency**: Lower memory and CPU overhead
6. **Network Simplicity**: Direct host networking or simple bridging

## API Endpoints

Once deployed, the following endpoints are available:

- **Swagger UI**: `http://[container-ip]:8080/`
- **Health Check**: `http://[container-ip]:8080/v1/health`
- **Register Number**: `POST /v1/register`
- **Verify Number**: `POST /v1/verify`
- **Send Message**: `POST /v2/send`
- **Receive Messages**: `GET /v1/receive`

## Monitoring and Maintenance

### Service Management
```bash
# Check service status
systemctl status my-signal-api

# View logs
journalctl -u my-signal-api -f

# Restart service
systemctl restart my-signal-api
```

### Health Monitoring
The service type includes comprehensive health checks that verify:
- Port accessibility
- API endpoint responses
- Signal CLI functionality
- Systemd service status

### Updates and Redeployment
```bash
# Redeploy with updates
pxd redeploy my-signal-api

# Force rebuild
pxd redeploy my-signal-api --force-rebuild
```

## Troubleshooting

### Common Issues

1. **Service won't start**
   - Check logs: `journalctl -u [service-name]`
   - Verify Java installation: `java -version`
   - Check signal-cli: `/usr/local/bin/signal-cli --version`

2. **Can't register phone number**
   - Ensure number is in international format (+1234567890)
   - Check internet connectivity
   - Verify Signal CLI is accessible

3. **API not responding**
   - Check port accessibility: `netstat -tlnp | grep 8080`
   - Verify firewall settings
   - Check service status

4. **Build failures**
   - Ensure internet connectivity for downloads
   - Check disk space
   - Verify Go and Java installations

## Security Considerations

- Service runs under dedicated user account
- Data directory has restricted permissions (0700)
- Systemd security hardening enabled
- Network access limited to required ports
- No privileged operations required

## Data Persistence

Signal configuration and registration data is stored in `/opt/signal-api/data` and persists across:
- Service restarts
- Container reboots
- Redeployments (unless explicitly cleaned)

This ensures you don't need to re-register your phone number after updates.

## Performance Tuning

### Memory Limits
Adjust in service configuration:
```yaml
container_memory: 2048  # MB for normal mode
container_memory: 4096  # MB for json-rpc mode
```

### CPU Allocation
```yaml
container_cores: 2  # Recommended minimum
container_cores: 4  # For high-traffic deployments
```

### Mode Selection
- **Normal**: Best for low-traffic, occasional use
- **Native**: Best balance of performance and stability
- **JSON-RPC**: Best for high-traffic, continuous use

This service type provides a complete, production-ready Signal CLI REST API deployment that matches Docker functionality while leveraging the benefits of native LXC integration.
