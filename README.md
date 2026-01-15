# Outline LXC Auto-Updater for ProxmoxVE

This repository provides an automated update solution for Outline installations created using the [community-scripts ProxmoxVE Outline installer](https://github.com/community-scripts/ProxmoxVE/blob/main/install/outline-install.sh).

## Overview

The Outline installation script from community-scripts creates a working Outline instance but doesn't include automatic updates. This auto-updater fills that gap by providing:

- **Automated daily checks** for new Outline releases
- **Safe backup and restore** functionality
- **Automatic rollback** if updates fail
- **Comprehensive logging** of all update activities
- **Manual update controls** for immediate updates

## Features

✅ **Daily Automatic Updates** - Checks GitHub releases at 2:30 AM daily  
✅ **Safe Backups** - Creates timestamped backups before each update  
✅ **Rollback Protection** - Automatically restores if updates fail  
✅ **Preserves Configuration** - Keeps your `.env` settings intact  
✅ **Service Validation** - Ensures Outline starts properly after updates  
✅ **Log Rotation** - Prevents log files from growing too large  
✅ **Auto-detects Version** - Creates version file automatically if missing

## Prerequisites

- Outline installed via the [ProxmoxVE community-scripts installer](https://github.com/community-scripts/ProxmoxVE/blob/main/install/outline-install.sh)
- Root access to the LXC container
- Internet connectivity for GitHub API access

## Installation

### Quick Install (no git)

```bash
# Run inside your Outline LXC as root
cd /root \
&& wget -O outline-auto-update.sh https://raw.githubusercontent.com/ivanzud/outline-lxc-auto-updater/main/outline-auto-update.sh \
&& wget -O setup-auto-update.sh https://raw.githubusercontent.com/ivanzud/outline-lxc-auto-updater/main/setup-auto-update.sh \
&& chmod +x outline-auto-update.sh setup-auto-update.sh \
&& ./setup-auto-update.sh
```

### Install via Git (optional)

```bash
apt-get update && apt-get install -y git ca-certificates
cd /root && rm -rf outline-lxc-auto-updater
git clone https://github.com/ivanzud/outline-lxc-auto-updater.git
cd outline-lxc-auto-updater && chmod +x outline-auto-update.sh setup-auto-update.sh
./setup-auto-update.sh
```

### Upgrade/Reinstall the updater

Re-run any of the install methods above. It will overwrite:

- `/usr/local/bin/outline-auto-update`
- `/etc/cron.d/outline-auto-update`
- `/etc/logrotate.d/outline-update`

### Verify

```bash
outline-auto-update --check || true   # exit code 1 means “Up to date”
tail -n 50 /var/log/outline-update.log
```

### 1. Download the Scripts

```bash
# Clone this repository or download the files
wget https://raw.githubusercontent.com/ivanzud/outline-lxc-auto-updater/main/outline-auto-update.sh
wget https://raw.githubusercontent.com/ivanzud/outline-lxc-auto-updater/main/setup-auto-update.sh

# Make them executable
chmod +x outline-auto-update.sh
chmod +x setup-auto-update.sh
```

### 2. Test the Auto-Updater

The script will automatically create a version file if it's missing by reading your current Outline version from package.json.

```bash
# Test if updates are available
./outline-auto-update.sh --check
```

Expected output:

```
Current: 0.85.0
Latest: 0.85.1
Update available
```

### 3. Install the Auto-Updater

```bash
# Run the setup script
sudo ./setup-auto-update.sh
```

## Usage

### Automatic Updates

Once installed, the system will automatically check for updates daily at 2:30 AM.

### Manual Commands

```bash
# Check for available updates
outline-auto-update --check

# Force an immediate update
outline-auto-update --force

# Restore from a specific backup
outline-auto-update --restore /opt/outline_backups/outline-backup-20250122-143000

# View update logs
tail -f /var/log/outline-update.log

# View recent log entries
tail -20 /var/log/outline-update.log
```

### Backup Management

Backups are automatically created before each update and stored in `/opt/outline_backups/`:

```bash
# List available backups
ls -la /opt/outline_backups/

# Manual backup (stops service temporarily)
systemctl stop outline
cp -r /opt/outline /opt/outline_backups/manual-backup-$(date +%Y%m%d-%H%M%S)
systemctl start outline
```

## Configuration

### Changing Update Schedule

Edit the cron file to change when updates run:

```bash
sudo nano /etc/cron.d/outline-auto-update
```

Example schedules:

```bash
# Daily at 3:00 AM
0 3 * * * root /usr/local/bin/outline-auto-update >/dev/null 2>&1

# Weekly on Sundays at 2:00 AM
0 2 * * 0 root /usr/local/bin/outline-auto-update >/dev/null 2>&1

# Monthly on the 1st at 1:00 AM
0 1 1 * * root /usr/local/bin/outline-auto-update >/dev/null 2>&1
```

### Email Notifications

To receive email notifications when updates complete, uncomment and configure the mail line in `outline-auto-update.sh`:

```bash
# Uncomment and modify this line in the script
echo "Outline updated to $latest_version" | mail -s "Outline Update Success" admin@yourdomain.com
```

## How It Works

### Update Process

1. **Version Check** - Compares local version with GitHub releases
2. **Backup Creation** - Creates timestamped backup of current installation
3. **Download** - Fetches new Outline version from GitHub
4. **Service Stop** - Safely stops Outline service
5. **Installation** - Replaces code while preserving configuration
6. **Dependencies** - Installs updated npm packages
7. **Build** - Compiles application for production
8. **Service Start** - Restarts Outline service
9. **Validation** - Confirms service is running properly
10. **Cleanup** - Removes temporary files and old backups

### Safety Features

- **Automatic Rollback** - If any step fails, automatically restores from backup
- **Configuration Preservation** - Your `.env` file is never modified
- **Service Validation** - Ensures Outline starts before considering update successful
- **Backup Retention** - Keeps last 5 backups automatically
- **Comprehensive Logging** - Every action is logged with timestamps

## Troubleshooting

### Blank page after update

If the web UI shows a blank/white page, rebuild assets in production (some environments require devDependencies during build):

```bash
cd /opt/outline
export NODE_ENV=production
yarn install --frozen-lockfile --production=false
yarn build
systemctl restart outline
```

### Update Fails

```bash
# Check the logs for error details
tail -50 /var/log/outline-update.log

# Manually restore from the most recent backup
ls -t /opt/outline_backups/ | head -1
outline-auto-update --restore /opt/outline_backups/[backup-name]
```

### Service Won't Start

```bash
# Check service status
systemctl status outline

# Check Outline logs
journalctl -u outline -f
```

### Version File Missing

```bash
# Recreate the version file
cat /opt/outline/package.json | grep '"version"' | awk -F'"' '{print $4}' > /opt/outline_version.txt
```

### Permission Issues

```bash
# Ensure script has proper permissions
sudo chmod +x /usr/local/bin/outline-auto-update
sudo chown root:root /usr/local/bin/outline-auto-update
```

## File Locations

| File/Directory                       | Purpose                  |
| ------------------------------------ | ------------------------ |
| `/usr/local/bin/outline-auto-update` | Main update script       |
| `/opt/outline_version.txt`           | Current version tracking |
| `/opt/outline_backups/`              | Backup storage directory |
| `/var/log/outline-update.log`        | Update activity logs     |
| `/etc/cron.d/outline-auto-update`    | Cron job configuration   |
| `/etc/logrotate.d/outline-update`    | Log rotation settings    |

## Security Considerations

- Script requires root access (needed for systemctl and file operations)
- Downloads are verified against GitHub's official Outline repository
- Backups are created locally before any changes
- Configuration files are preserved and never transmitted

## Contributing

Feel free to submit issues, suggestions, or pull requests to improve this auto-updater.

## License

This project is provided as-is under the MIT License. Use at your own risk.

## Disclaimer

This is an unofficial tool not affiliated with Outline or the ProxmoxVE community-scripts project. Always test updates in a non-production environment first.
