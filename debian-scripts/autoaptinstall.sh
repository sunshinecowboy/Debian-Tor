#!/bin/bash

# Check if running as root, if not, advise to run as root and exit
if (( $EUID != 0 )); then
    echo "This script must be run as root. Try running with 'sudo'."
    exit 1
fi

# Function to get user input with a default value
get_input() {
    local prompt default_value
    prompt=$1
    default_value=$2

    # Display prompt and read user input, use default if no input is given
    read -p "$prompt [$default_value]: " input
    echo "${input:-$default_value}"
}

# User-configurable variables with defaults
LOGDIR=$(get_input "Enter the directory for storing logs" "/var/log/auto-update")
BOOT_TIME=$(get_input "Enter the time after boot to run the update (e.g., 5min, 10min)" "5min")
UPDATE_FREQ=$(get_input "Enter the frequency of updates (e.g., 24h, 12h)" "24h")

# Create log directory
echo "Establishing log directory at $LOGDIR"
mkdir -p "$LOGDIR" || { echo "Failed to create log directory"; exit 1; }

# Create and configure auto-update script
AUTOUPDATE="/usr/bin/auto-update"
echo "Creating auto-update executable at $AUTOUPDATE"

cat <<EOF > "$AUTOUPDATE"
#!/bin/bash
# Auto-update script

# Ensure running as root
if (( \$EUID != 0 )); then
    echo "This script must be run as root."
    exit 1
fi

# Log file setup
TIMESTAMP=\$(date +'%Y_%m_%d--%H-%M-%S')
LOGFILE=${LOGDIR}/update_\$TIMESTAMP.log

# Update commands
{
    apt-get update
    apt-get upgrade -y
    apt-get autoremove -y
    apt-get autoclean
} | tee "\$LOGFILE"

echo "Update Complete!"
EOF

chmod +x "$AUTOUPDATE" || { echo "Failed to set permissions on auto-update"; exit 1; }

# Create and enable systemd service and timer
SERVICE_FILE="/etc/systemd/system/auto-update.service"
TIMER_FILE="/etc/systemd/system/auto-update.timer"

echo "Creating and enabling systemd timer for scheduled updates..."

# Service file
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Auto Apt Update Script

[Service]
ExecStart=$AUTOUPDATE
EOF

# Timer file
cat <<EOF > "$TIMER_FILE"
[Unit]
Description=Run auto-update.service $BOOT_TIME after boot and every $UPDATE_FREQ relative to activation time

[Timer]
OnBootSec=$BOOT_TIME
OnUnitActiveSec=$UPDATE_FREQ

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the timer
systemctl start auto-update.timer && systemctl enable auto-update.timer || { echo "Failed to start or enable the timer"; exit 1; }

echo "Installation Complete! Auto-update will run $BOOT_TIME after boot and every $UPDATE_FREQ."

