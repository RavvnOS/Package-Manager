# Operational Patterns

Running shell scripts in production: cron, daemons, logging, systemd, and deployment.

## Cron-Safe Scripts

Cron has a minimal environment. Scripts must be defensive.

### Cron Gotchas

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Set explicit PATH (cron has minimal PATH)
PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
export PATH

# 2. Set HOME and USER if needed
HOME="${HOME:-/root}"
USER="${USER:-root}"

# 3. Redirect output (cron emails output by default)
exec >> /var/log/myscript.log 2>&1

# 4. Always log timestamps
echo "[$(date -Iseconds)] Script started"

# 5. Use absolute paths
CONFIG_FILE="/etc/myapp/config.ini"
DATA_DIR="/var/lib/myapp"

# 6. Handle failures gracefully
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "[$(date -Iseconds)] Script failed with exit code: $exit_code"
  fi
}
trap cleanup EXIT

# Rest of script...
```

### Crontab Entry

```cron
# Run daily at 2am
0 2 * * * /usr/local/bin/backup.sh

# With lock file to prevent overlap
0 2 * * * flock -n /var/lock/backup.lock /usr/local/bin/backup.sh

# With output logging
0 2 * * * /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1

# With email on error only
0 2 * * * /usr/local/bin/backup.sh >/dev/null 2>&1 || mail -s "Backup failed" admin@example.com
```

### Lock Files for Cron

```bash
#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/lock/$(basename "$0").lock"

# Acquire lock (fail if already locked)
exec 200>"$LOCK_FILE"
flock -n 200 || {
  echo "Another instance is running" >&2
  exit 1
}

# Script continues...
# Lock released automatically on exit
```

## Logging Patterns

### Structured Logging

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly LOG_FILE="${LOG_FILE:-/var/log/myapp.log}"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Log with timestamp and level
log() {
  local level="$1"
  shift
  local timestamp
  timestamp=$(date -Iseconds)
  printf '[%s] [%s] %s\n' "$timestamp" "$level" "$*" >&2
}

# Log level functions
debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && log DEBUG "$@"; }
info() { log INFO "$@"; }
warn() { log WARN "$@"; }
error() { log ERROR "$@"; }
fatal() { log FATAL "$@"; exit 1; }

# Redirect all output to log file
exec >> "$LOG_FILE" 2>&1

# Usage
info "Starting backup..."
debug "Using config: $CONFIG"
warn "Low disk space"
error "Connection failed"
fatal "Cannot proceed"
```

### Log Rotation

```bash
# Script to rotate logs
rotate_log() {
  local log_file="$1"
  local max_size="$2"  # in MB
  local max_backups="${3:-5}"
  
  if [[ ! -f "$log_file" ]]; then
    return 0
  fi
  
  # Check size
  local size_mb
  size_mb=$(du -m "$log_file" | cut -f1)
  
  if [[ $size_mb -ge $max_size ]]; then
    # Rotate
    for i in $(seq $((max_backups - 1)) -1 1); do
      if [[ -f "${log_file}.$i" ]]; then
        mv "${log_file}.$i" "${log_file}.$((i + 1))"
      fi
    done
    mv "$log_file" "${log_file}.1"
    touch "$log_file"
  fi
}

# Usage
rotate_log "/var/log/myapp.log" 100 5  # 100MB, keep 5 backups
```

### Using logrotate (System Tool)

```bash
# /etc/logrotate.d/myapp
/var/log/myapp.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 myapp myapp
    postrotate
        # Send SIGHUP to daemon to reopen log file
        killall -HUP myapp 2>/dev/null || true
    endscript
}
```

## Signal Handling

### Graceful Shutdown

```bash
#!/usr/bin/env bash
set -euo pipefail

# Flag to indicate shutdown
SHUTDOWN=false

# Cleanup function
cleanup() {
  echo "Cleaning up..."
  # Kill child processes
  jobs -p | xargs -r kill 2>/dev/null || true
  # Remove temp files
  rm -rf "$TEMP_DIR"
  exit 0
}

# Signal handlers
handle_sigint() {
  echo "Received SIGINT (Ctrl+C), shutting down gracefully..."
  SHUTDOWN=true
}

handle_sigterm() {
  echo "Received SIGTERM, shutting down gracefully..."
  SHUTDOWN=true
}

trap cleanup EXIT
trap handle_sigint INT
trap handle_sigterm TERM

# Main loop
while true; do
  if [[ "$SHUTDOWN" == "true" ]]; then
    echo "Shutdown flag set, exiting..."
    break
  fi
  
  # Do work...
  sleep 1
done
```

### Reloading Config on SIGHUP

```bash
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/myapp/config"

load_config() {
  echo "Loading config from $CONFIG_FILE"
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
}

handle_sighup() {
  echo "Received SIGHUP, reloading config..."
  load_config
}

trap handle_sighup HUP

load_config

# Main loop
while true; do
  # Use config...
  sleep 1
done
```

## Daemon Patterns

### Simple Daemon

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly PID_FILE="/var/run/myapp.pid"
readonly LOG_FILE="/var/log/myapp.log"

# Check if already running
if [[ -f "$PID_FILE" ]]; then
  old_pid=$(cat "$PID_FILE")
  if kill -0 "$old_pid" 2>/dev/null; then
    echo "Already running with PID $old_pid" >&2
    exit 1
  fi
  rm -f "$PID_FILE"
fi

# Daemonize
if [[ "${DAEMON:-true}" == "true" ]]; then
  # Fork into background
  "$0" DAEMON=false "$@" </dev/null >>"$LOG_FILE" 2>&1 &
  echo $! > "$PID_FILE"
  echo "Started with PID $(cat "$PID_FILE")"
  exit 0
fi

# Cleanup on exit
cleanup() {
  rm -f "$PID_FILE"
}
trap cleanup EXIT

# Write PID
echo $$ > "$PID_FILE"

# Main daemon loop
while true; do
  # Do work...
  sleep 5
done
```

## systemd Integration

### systemd Service Unit

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application
After=network.target

[Service]
Type=simple
User=myapp
Group=myapp
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/bin/myapp.sh
ExecReload=/bin/kill -HUP $MAINPID
Restart=on-failure
RestartSec=5s

# Logging
StandardOutput=journal
StandardError=journal

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/myapp /var/log/myapp

[Install]
WantedBy=multi-user.target
```

### Managing the Service

```bash
# Enable and start
sudo systemctl enable myapp
sudo systemctl start myapp

# Status
sudo systemctl status myapp

# Logs
sudo journalctl -u myapp -f

# Reload config
sudo systemctl reload myapp

# Restart
sudo systemctl restart myapp

# Stop
sudo systemctl stop myapp
```

### systemd Timer (Instead of cron)

```ini
# /etc/systemd/system/myapp-backup.timer
[Unit]
Description=Run myapp backup daily

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/myapp-backup.service
[Unit]
Description=Myapp Backup

[Service]
Type=oneshot
User=myapp
ExecStart=/opt/myapp/bin/backup.sh
```

```bash
# Enable timer
sudo systemctl enable myapp-backup.timer
sudo systemctl start myapp-backup.timer

# Check timer status
sudo systemctl list-timers
```

## Health Checks

### Self-Health Check

```bash
#!/usr/bin/env bash
set -euo pipefail

health_check() {
  # Check if process is running
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  
  local pid
  pid=$(cat "$PID_FILE")
  if ! kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  
  # Check if responding
  if ! curl -sf http://localhost:8080/health >/dev/null; then
    return 1
  fi
  
  return 0
}

if health_check; then
  echo "OK"
  exit 0
else
  echo "FAIL"
  exit 1
fi
```

## Alerting

### Email Alerts

```bash
send_alert() {
  local subject="$1"
  local body="$2"
  local recipients="admin@example.com,ops@example.com"
  
  mail -s "$subject" "$recipients" <<EOF
$body

Hostname: $(hostname)
Time: $(date -Iseconds)
EOF
}

# Usage
if ! backup_database; then
  send_alert "Backup Failed" "Database backup failed. Check logs."
fi
```

### Slack Alerts

```bash
send_slack_alert() {
  local webhook_url="$SLACK_WEBHOOK_URL"
  local message="$1"
  
  curl -X POST "$webhook_url" \
    -H 'Content-Type: application/json' \
    -d "{\"text\":\"$message\"}"
}

# Usage
send_slack_alert ":x: Backup failed on $(hostname)"
```

## Deployment Patterns

### Blue-Green Deployment Script

```bash
#!/usr/bin/env bash
set -euo pipefail

readonly BLUE_DIR="/opt/myapp/blue"
readonly GREEN_DIR="/opt/myapp/green"
readonly CURRENT_LINK="/opt/myapp/current"

deploy() {
  local version="$1"
  
  # Determine target (opposite of current)
  local target
  if [[ "$(readlink "$CURRENT_LINK")" == "$BLUE_DIR" ]]; then
    target="$GREEN_DIR"
  else
    target="$BLUE_DIR"
  fi
  
  echo "Deploying $version to $target"
  
  # Deploy new version
  rsync -a --delete "releases/$version/" "$target/"
  
  # Health check
  if ! "$target/bin/health-check.sh"; then
    echo "Health check failed, aborting deployment"
    return 1
  fi
  
  # Switch symlink atomically
  ln -sfn "$target" "$CURRENT_LINK.new"
  mv -Tf "$CURRENT_LINK.new" "$CURRENT_LINK"
  
  # Reload service
  sudo systemctl reload myapp
  
  echo "Deployment complete"
}

rollback() {
  # Switch back to other environment
  local target
  if [[ "$(readlink "$CURRENT_LINK")" == "$BLUE_DIR" ]]; then
    target="$GREEN_DIR"
  else
    target="$BLUE_DIR"
  fi
  
  echo "Rolling back to $target"
  ln -sfn "$target" "$CURRENT_LINK.new"
  mv -Tf "$CURRENT_LINK.new" "$CURRENT_LINK"
  sudo systemctl reload myapp
}
```

## Monitoring Integrations

### Prometheus Metrics

```bash
# Write metrics to text file for node_exporter
write_metrics() {
  local metrics_file="/var/lib/node_exporter/textfile_collector/myapp.prom"
  local temp_file="${metrics_file}.$$"
  
  cat > "$temp_file" <<EOF
# HELP myapp_backup_last_success_timestamp_seconds Last successful backup
# TYPE myapp_backup_last_success_timestamp_seconds gauge
myapp_backup_last_success_timestamp_seconds $(date +%s)

# HELP myapp_backup_duration_seconds Backup duration in seconds
# TYPE myapp_backup_duration_seconds gauge
myapp_backup_duration_seconds $DURATION

# HELP myapp_backup_size_bytes Backup size in bytes
# TYPE myapp_backup_size_bytes gauge
myapp_backup_size_bytes $SIZE
EOF
  
  mv "$temp_file" "$metrics_file"
}
```

## Resources

- systemd documentation: `man systemd.service`, `man systemd.timer`
- cron: `man 5 crontab`
- logrotate: `man logrotate`
- flock: `man flock`
- Signal numbers: `kill -l`
