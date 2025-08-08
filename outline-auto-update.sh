#!/usr/bin/env bash

# Outline Auto-Update Script
# This script checks for new Outline releases and updates automatically
# Author: Auto-generated for ProxmoxVE Outline installation
# Usage: Run manually or setup as cron job

set -euo pipefail

# Configuration
OUTLINE_DIR="/opt/outline"
VERSION_FILE="/opt/outline_version.txt"
BACKUP_DIR="/opt/outline_backups"
LOG_FILE="/var/log/outline-update.log"
SERVICE_NAME="outline"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log "${RED}ERROR: $1${NC}"
    exit 1
}

# Success message
success() {
    log "${GREEN}SUCCESS: $1${NC}"
}

# Warning message
warning() {
    log "${YELLOW}WARNING: $1${NC}"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root"
fi

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Function to get current installed version
get_current_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        # Version file missing, try to create it from package.json
        warning "Version file not found, attempting to create from package.json"
        
        if [[ -f "$OUTLINE_DIR/package.json" ]]; then
            local version_from_package
            version_from_package=$(grep '"version"' "$OUTLINE_DIR/package.json" | awk -F'"' '{print $4}')
            
            if [[ -n "$version_from_package" ]]; then
                echo "$version_from_package" > "$VERSION_FILE"
                success "Created version file with version: $version_from_package"
                echo "$version_from_package"
            else
                error_exit "Could not extract version from package.json"
            fi
        else
            error_exit "Neither version file nor package.json found. Is Outline properly installed?"
        fi
    fi
}

# Function to get latest version from GitHub
get_latest_version() {
    local latest_version
    latest_version=$(curl -fsSL https://api.github.com/repos/outline/outline/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
    
    if [[ -z "$latest_version" ]]; then
        error_exit "Failed to fetch latest version from GitHub"
    fi
    
    echo "$latest_version"
}

# Function to compare versions
# Returns 0 (success) only if $1 is strictly greater than $2
version_gt() {
    local v1="$1"
    local v2="$2"
    # If equal, not greater
    if [[ "$v1" == "$v2" ]]; then
        return 1
    fi
    # Ensure version-aware sort with stable locale
    if [[ "$(printf '%s\n%s\n' "$v1" "$v2" | LC_ALL=C sort -V | tail -n1)" == "$v1" ]]; then
        return 0
    fi
    return 1
}

# Function to backup current installation
backup_current() {
    local backup_name="outline-backup-$(date +%Y%m%d-%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    log "Creating backup: $backup_name"
    
    # Stop the service
    systemctl stop "$SERVICE_NAME"
    
    # Create backup
    cp -r "$OUTLINE_DIR" "$backup_path"
    
    # Keep only last 5 backups
    cd "$BACKUP_DIR"
    ls -t | tail -n +6 | xargs -r rm -rf
    
    success "Backup created at $backup_path"
    echo "$backup_path"
}

# Function to restore from backup
restore_backup() {
    local backup_path="$1"
    
    if [[ ! -d "$backup_path" ]]; then
        error_exit "Backup directory not found: $backup_path"
    fi
    
    warning "Restoring from backup: $backup_path"
    
    # Stop service
    systemctl stop "$SERVICE_NAME" || true
    
    # Remove current installation
    rm -rf "$OUTLINE_DIR"
    
    # Restore backup
    cp -r "$backup_path" "$OUTLINE_DIR"
    
    # Start service
    systemctl start "$SERVICE_NAME"
    
    success "Restored from backup successfully"
}

# Function to update Outline
update_outline() {
    local new_version="$1"
    local backup_path="$2"
    
    log "Updating Outline to version $new_version"
    
    # Download new version
    local temp_file=$(mktemp)
    if ! curl -fsSL "https://github.com/outline/outline/archive/refs/tags/v${new_version}.tar.gz" -o "$temp_file"; then
        error_exit "Failed to download Outline version $new_version"
    fi
    
    # Extract to temporary directory
    local temp_dir=$(mktemp -d)
    tar zxf "$temp_file" -C "$temp_dir"
    
    # Preserve current configuration
    local env_backup=$(mktemp)
    cp "$OUTLINE_DIR/.env" "$env_backup"
    
    # Remove old installation (keeping backup)
    rm -rf "$OUTLINE_DIR"
    
    # Move new version to outline directory
    mv "$temp_dir/outline-${new_version}" "$OUTLINE_DIR"
    
    # Restore configuration
    cp "$env_backup" "$OUTLINE_DIR/.env"
    
    # Change to outline directory
    cd "$OUTLINE_DIR"
    
    # Set development environment for build
    export NODE_ENV=development
    sed -i 's/NODE_ENV=production/NODE_ENV=development/g' "$OUTLINE_DIR/.env"
    
    # Install dependencies and build
    log "Installing dependencies..."
    if ! yarn install --frozen-lockfile; then
        warning "Failed to install dependencies, attempting restore..."
        restore_backup "$backup_path"
        error_exit "Update failed during dependency installation"
    fi
    
    log "Building Outline..."
    export NODE_OPTIONS="--max-old-space-size=3584"
    if ! yarn build; then
        warning "Failed to build, attempting restore..."
        restore_backup "$backup_path"
        error_exit "Update failed during build"
    fi
    
    # Set back to production
    sed -i 's/NODE_ENV=development/NODE_ENV=production/g' "$OUTLINE_DIR/.env"
    export NODE_ENV=production
    
    # Update version file
    echo "$new_version" > "$VERSION_FILE"
    
    # Start service
    systemctl start "$SERVICE_NAME"
    
    # Wait for service to start
    sleep 10
    
    # Check if service is running
    if ! systemctl is-active --quiet "$SERVICE_NAME"; then
        warning "Service failed to start, attempting restore..."
        restore_backup "$backup_path"
        error_exit "Update failed - service wouldn't start"
    fi
    
    # Cleanup
    rm -f "$temp_file" "$env_backup"
    rm -rf "$temp_dir"
    
    success "Updated Outline to version $new_version"
}

# Main execution
main() {
    log "Starting Outline auto-update check"
    
    # Check if Outline directory exists
    if [[ ! -d "$OUTLINE_DIR" ]]; then
        error_exit "Outline directory not found: $OUTLINE_DIR"
    fi
    
    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^$SERVICE_NAME.service"; then
        error_exit "Outline service not found: $SERVICE_NAME"
    fi
    
    # Get current and latest versions
    local current_version
    local latest_version
    
    current_version=$(get_current_version)
    latest_version=$(get_latest_version)
    
    log "Current version: $current_version"
    log "Latest version: $latest_version"
    
    # Compare versions
    if version_gt "$latest_version" "$current_version"; then
        log "New version available: $latest_version"
        
        # Create backup
        local backup_path
        backup_path=$(backup_current)
        
        # Attempt update
        if update_outline "$latest_version" "$backup_path"; then
            success "Successfully updated from $current_version to $latest_version"
            
            # Optional: Send notification (uncomment and configure as needed)
            # echo "Outline updated to $latest_version" | mail -s "Outline Update Success" admin@yourdomain.com
            
        else
            error_exit "Update failed"
        fi
    else
        log "Outline is already up to date (version $current_version)"
    fi
    
    log "Auto-update check completed"
}

# Handle script arguments
case "${1:-}" in
    "--force")
        log "Force update requested"
        latest_version=$(get_latest_version)
        backup_path=$(backup_current)
        update_outline "$latest_version" "$backup_path"
        ;;
    "--check")
        current_version=$(get_current_version)
        latest_version=$(get_latest_version)
        echo "Current: $current_version"
        echo "Latest: $latest_version"
        if version_gt "$latest_version" "$current_version"; then
            echo "Update available"
            exit 0
        else
            echo "Up to date"
            exit 1
        fi
        ;;
    "--restore")
        if [[ -z "${2:-}" ]]; then
            echo "Usage: $0 --restore <backup_path>"
            exit 1
        fi
        restore_backup "$2"
        ;;
    *)
        main
        ;;
esac