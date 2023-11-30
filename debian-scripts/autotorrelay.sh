#!/bin/bash
#if not root, run as root
if (( $EUID != 0 )); then
   echo "Try Running As Root!"
exit
fi

# Function to install and configure automatic updates
install_auto_updates() {
    echo "Do you want to enable automatic updates? [yes/no]"
    read enable_auto_updates
    case "$enable_auto_updates" in
        yes|YES|y|Y)
            # Install unattended-upgrades package
            apt install unattended-upgrades apt-listchanges -y

            # Enable automatic updates
            dpkg-reconfigure -plow unattended-upgrades

            # Create or modify the configuration file
            echo "Unattended-Upgrade::Automatic-Reboot \"true\";" >> /etc/apt/apt.conf.d/50unattended-upgrades
            echo "Unattended-Upgrade::Automatic-Reboot-Time \"02:00\";" >> /etc/apt/apt.conf.d/50unattended-upgrades
            ;;
        no|NO|n|N)
            echo "Automatic updates not enabled."
            ;;
        *)
            echo "Invalid input. Automatic updates not enabled."
            ;;
    esac
}

# Call the function to prompt for automatic updates installation
install_auto_updates

# Function to get input with a default value
echo "Updating system and installing necessary packages........."

# Update the system and install necessary packages
apt update && apt upgrade -y
apt install -y ufw fish tor nyx vim fail2ban htop unzip rsyslog

# Prompt for necessary variables with default values
get_input_with_default() {
    local prompt=$1
    local default=$2
    read -p "$prompt [$default]: " input
    echo "${input:-$default}"
}

SSHPORT=$(get_input_with_default "Enter SSH Port" "22")
ControlPort=$(get_input_with_default "Enter Control Port" "9051")
ORPort=$(get_input_with_default "Enter OR Port" "9001")
DirPort=$(get_input_with_default "Enter Directory Port" "9030")
SocksPort=$(get_input_with_default "Enter Tor SOCKS Port" "0")
TorNickname=$(get_input_with_default "Enter Tor Nickname" "ididntreadtheconfig")
ContactInfo=$(get_input_with_default "Enter Contact Info (email)" "user@example.com")
RelayBandwidthRate=$(get_input_with_default "Enter Relay Bandwidth Rate" "500 KB")
RelayBandwidthBurst=$(get_input_with_default "Enter Relay Bandwidth Burst" "1000 KB")

# Prompt for Tor Control Port password and hash it
while true; do
    echo "Enter a password for Tor Control Port:"
    read -s tor_password
    echo "Confirm password:"
    read -s tor_password_confirm
    if [ "$tor_password" = "$tor_password_confirm" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

HashedControlPassword=$(tor --hash-password $tor_password | tail -n 1)

echo "Setting up and enabling firewall........"

# Set up and enable UFW
ufw default deny incoming
ufw default allow outgoing
ufw allow $SSHPORT/tcp
ufw allow $ControlPort/tcp
ufw allow $DirPort/tcp
ufw allow $ORPort/tcp
ufw allow $SocksPort/tcp
ufw enable
setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/tor

echo "Creating Tor Relay config file at /etc/tor/torrc........."

# Create the /etc/tor/torrc
{
  echo User debian-tor 
  echo Log notice syslog
  echo DataDirectory /var/lib/tor
  echo ControlPort $ControlPort
  echo ORPort $ORPort
  echo DirPort $DirPort
  echo Nickname $TorNickname
  echo ContactInfo $ContactInfo
  echo RelayBandwidthRate $RelayBandwidthRate
  echo RelayBandwidthBurst $RelayBandwidthBurst
  echo HashedControlPassword $HashedControlPassword
  echo ExitRelay 0
} > /etc/tor/torrc

echo "We now need to set up the SSHD and its fail2ban jail......."

# Function to configure root login and SSH port for SSHD
configure_sshd_settings() {
    local sshd_config="/etc/ssh/sshd_config"
    local temp_file=$(mktemp)

    # Prompt for SSH port
    read -p "Enter SSH Port [default: 22]: " ssh_port
    ssh_port=${ssh_port:-22}

    # Prompt for allowing root login
    echo "Do you want to allow root to SSH? [yes/no]"
    read allow_root_ssh
    case "$allow_root_ssh" in
        yes|YES|y|Y) permit_root_login="yes";;
        no|NO|n|N) permit_root_login="no";;
        *) echo "Invalid input. Defaulting to 'no'."; permit_root_login="no";;
    esac

    # Update sshd_config
    awk -v permit_root_login="$permit_root_login" -v ssh_port="$ssh_port" '
    /^#?Port/ { print "Port " ssh_port; next }
    /^#?PermitRootLogin/ { print "PermitRootLogin " permit_root_login; next }
    { print }
    ' "$sshd_config" > "$temp_file" && mv "$temp_file" "$sshd_config"

    # Restart the SSH service to apply changes
    systemctl restart sshd
}

# Run the function to configure SSHD settings
configure_sshd_settings

# Function to configure sshd in jail.conf with defaults
configure_sshd_in_jail_conf() {
    local jail_conf_path="/etc/fail2ban/jail.conf"
    local temp_file=$(mktemp)

    # Get user inputs with defaults
    local maxretry=$(get_input_with_default "Enter maxretry" "5")
    local findtime=$(get_input_with_default "Enter findtime (e.g., 1w)" "1w")
    local bantime=$(get_input_with_default "Enter bantime (e.g., 52w)" "52w")

    awk -v maxretry="$maxretry" -v findtime="$findtime" -v bantime="$bantime" '
    /^\[sshd\]$/ {
        print;
        print "enabled = true";
        print "maxretry = " maxretry;
        print "findtime = " findtime;
        print "bantime = " bantime;
        next;
    }
    { print }
    ' "$jail_conf_path" > "$temp_file" && mv "$temp_file" "$jail_conf_path"
}

# Configure sshd in jail.conf with defaults
configure_sshd_in_jail_conf

# Set Permissions for tor
chown -R debian-tor:debian-tor /var/lib/tor

echo "Starting system services............"

# Start rsyslog service
systemctl enable rsyslog
systemctl start rsyslog

# Start Tor service
systemctl enable tor
systemctl start tor

# Add functionality to the configuration files
echo allowipv6 = auto >> /etc/fail2ban/fail2ban.conf

# Create Locals
cp /etc/fail2ban/fail2ban.conf /etc/fail2ban/fail2ban.local 
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local

# Start Fail2Ban service
systemctl enable fail2ban
systemctl start fail2ban

echo "Complete! Your hardened tor server is up and running! To view it's performace type nyx -i 127.0.0.1:$ControlPort and enter your password!"
