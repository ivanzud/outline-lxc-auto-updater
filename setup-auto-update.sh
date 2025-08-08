#!/usr/bin/env bash

# Setup script for Outline auto-updater
# This script installs the auto-update script and sets up cron job

set -euo pipefail

SCRIPT_DIR="/usr/local/bin"
SCRIPT_NAME="outline-auto-update"
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"
CRON_FILE="/etc/cron.d/outline-auto-update"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Setting up Outline Auto-Update...${NC}"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}"
    exit 1
fi

# Check if the auto-update script exists in current directory
if [[ ! -f "./outline-auto-update.sh" ]]; then
    echo -e "${RED}ERROR: Please save the auto-update script as 'outline-auto-update.sh' in the current directory${NC}"
    echo "Then run this setup script again."
    exit 1
fi

# Copy script to system location
echo "Installing auto-update script at $SCRIPT_PATH"
cp "./outline-auto-update.sh" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

echo -e "${GREEN}✓ Auto-update script installed${NC}"

# Create cron job
echo "Setting up cron job..."

cat > "$CRON_FILE" << 'EOF'
# Outline Auto-Update Cron Job
# Checks for updates every day at 2:30 AM
# Logs are written to /var/log/outline-update.log

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

30 2 * * * root /usr/local/bin/outline-auto-update >/dev/null 2>&1
EOF

# Set proper permissions for cron file
chmod 644 "$CRON_FILE"

echo -e "${GREEN}✓ Cron job created${NC}"

# Create log rotation for update logs
echo "Setting up log rotation..."

cat > "/etc/logrotate.d/outline-update" << 'EOF'
/var/log/outline-update.log {
    weekly
    missingok
    rotate 12
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF

echo -e "${GREEN}✓ Log rotation configured${NC}"

# Test the script
echo "Testing the auto-update script..."
if "$SCRIPT_PATH" --check; then
    echo -e "${GREEN}✓ Script test passed - update available${NC}"
elif [[ $? -eq 1 ]]; then
    echo -e "${YELLOW}✓ Script test passed - already up to date${NC}"
else
    echo -e "${RED}✗ Script test failed${NC}"
    exit 1
fi

echo
echo -e "${GREEN}🎉 Outline Auto-Update Setup Complete!${NC}"
echo
echo "Configuration:"
echo "  • Auto-update script: $SCRIPT_PATH"
echo "  • Cron schedule: Daily at 2:30 AM"
echo "  • Log file: /var/log/outline-update.log"
echo "  • Backups stored in: /opt/outline_backups"
echo
echo "Manual Usage:"
echo "  • Check for updates: $SCRIPT_NAME --check"
echo "  • Force update: $SCRIPT_NAME --force"
echo "  • Restore backup: $SCRIPT_NAME --restore <backup_path>"
echo "  • View logs: tail -f /var/log/outline-update.log"
echo
echo "To change the update schedule, edit: $CRON_FILE"
echo
echo -e "${YELLOW}Note: The first automatic check will run tomorrow at 2:30 AM${NC}"