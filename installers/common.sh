raspap_dir="/etc/raspap"
raspap_user="www-data"
webroot_dir="/var/www/html"
version=`sed 's/\..*//' /etc/debian_version`

# Determine version, set default home location for lighttpd and
# php package to install
if [ $version -eq 10 ]; then
    version_msg="10.0 (Buster)"
    sudo apt update --allow-releaseinfo-change
    php_package="php7.3-cgi"
elif [ $version -eq 9 ]; then
    version_msg="9.0 (Stretch)"
    php_package="php7.0-cgi"
elif [ $version -eq 8 ]; then
    version_msg="8.0 (Jessie)"
    php_package="php5.6-cgi"
else
    version_msg="Earlier than 8.0 (Wheezy)"
    webroot_dir="/var/www"
    php_package="php5.6-cgi"
fi

phpcgiconf=""
if [ "$php_package" = "php7.3-cgi" ]; then
    phpcgiconf="/etc/php/7.3/cgi/php.ini"
elif [ "$php_package" = "php7.0-cgi" ]; then
    phpcgiconf="/etc/php/7.0/cgi/php.ini"
elif [ "$php_package" = "php5.6-cgi" ]; then
    phpcgiconf="/etc/php5/cgi/php.ini"
fi

# Outputs a RaspAP Install log line
function install_log() {
    echo -e "\033[1;32mLabyrinthAP Install: $*\033[m"
}

# Outputs a RaspAP Install Error log line and exits with status code 1
function install_error() {
    echo -e "\033[1;37;41mLabyrinthAP Install Error: $*\033[m"
    exit 1
}

# Outputs a RaspAP Warning line
function install_warning() {
    echo -e "\033[1;33mWarning: $*\033[m"
}

# Outputs a welcome message
function display_welcome() {
    raspberry='\033[0;35m'
    green='\033[1;32m'

    echo -e "${green}\n"
    echo -e "  ooooo                  oooo         o8o        .o.       ooooooooo."
    echo -e "   888                    888                   .888.       888    Y88."
    echo -e "   888          .ooooo.   888  oooo  oooo      .8 888.      888   .d88"
    echo -e "   888         d88   88b  888 .8P     888     .8   888.     888ooo88P"
    echo -e "   888         888   888  888888.     888    .88ooo8888.    888"
    echo -e "   888       o 888   888  888  88b.   888   .8       888.   888"
    echo -e "  o888ooooood8  Y8bod8P  o888o o888o o888o o88o     o8888o o888o"
    echo -e "${raspberry}"
    echo -e "The Quick Installer will guide you through a few easy steps\n\n"
}

### NOTE: all the below functions are overloadable for system-specific installs
### NOTE: some of the below functions MUST be overloaded due to system-specific installs

function config_installation() {
    install_log "Configure installation"
    echo "Detected ${version_msg}"
    echo "Install directory: ${raspap_dir}"
    echo "Lighttpd directory: ${webroot_dir}"
    echo -n "Complete installation with these values? [y/N]: "
    read answer
    if [[ $answer != "y" ]]; then
        echo "Installation aborted."
        exit 0
    fi
}

# Runs a system software update to make sure we're using all fresh packages
function update_system_packages() {
    # OVERLOAD THIS
    install_error "No function definition for update_system_packages"
}

# Installs additional dependencies using system package manager
function install_dependencies() {
    # OVERLOAD THIS
    install_error "No function definition for install_dependencies"
}

#If Armbian set network interfaces naming convention

function common_interfaces() {
  if [ -f /boot/armbianEnv.txt ]; then
    sudo sed -i '1i extraargs=net.ifnames=0' /boot/armbianEnv.txt && install_log "armbianEnv patched"
  else install_log "Armbian undetected no patching required"
  fi
}

function stop_lokinet(){
    sudo systemctl stop lokinet.service
}

# Replaces NetworkManager with DHCPD
function check_for_networkmananger() {
    # OVERLOAD THIS
    install_error "No function definition for install_dependencies"
}


# Enables PHP for lighttpd and restarts service for settings to take effect
function enable_php_lighttpd() {
    install_log "Enabling PHP for lighttpd"

    sudo lighttpd-enable-mod fastcgi-php
    sudo service lighttpd force-reload
    sudo /etc/init.d/lighttpd restart || install_error "Unable to restart lighttpd"
}

# Verifies existence and permissions of RaspAP directory
function create_raspap_directories() {
    install_log "Creating LabyrinthAP directories"
    if [ -d "$raspap_dir" ]; then
        sudo mv $raspap_dir "$raspap_dir.`date +%F-%R`" || install_error "Unable to move old '$raspap_dir' out of the way"
    fi
    sudo mkdir -p "$raspap_dir" || install_error "Unable to create directory '$raspap_dir'"

    # Create a directory for existing file backups.
    sudo mkdir -p "$raspap_dir/backups"

    # Create a directory to store networking configs
    sudo mkdir -p "$raspap_dir/networking"
    # Copy existing dhcpcd.conf to use as base config
    cat /etc/dhcpcd.conf | sudo tee -a /etc/raspap/networking/defaults

    sudo chown -R $raspap_user:$raspap_user "$raspap_dir" || install_error "Unable to change file ownership for '$raspap_dir'"
}

# Generate logging enable/disable files for hostapd
function create_logging_scripts() {
    install_log "Creating logging scripts"
    sudo mkdir $raspap_dir/hostapd || install_error "Unable to create directory '$raspap_dir/hostapd'"

    # Move existing shell scripts
    sudo mv "$webroot_dir/installers/"*log.sh "$raspap_dir/hostapd" || install_error "Unable to move logging scripts"
    # Make enablelog.sh and disablelog.sh not writable by www-data group.
    sudo chown -c root:"$raspap_user" "$raspap_dir/hostapd/"*log.sh || install_error "Unable change owner and/or group."
    sudo chmod 750 "$raspap_dir/hostapd/"*log.sh || install_error "Unable to change file permissions."
}


# Fetches latest files from github to webroot
function download_latest_files() {
    if [ -d "$webroot_dir" ]; then
        sudo mv $webroot_dir "$webroot_dir.`date +%F-%R`" || install_error "Unable to remove old webroot directory"
    fi

    install_log "Cloning latest files from github"
    git clone --depth 1 https://github.com/necro-nemesis/LabyrinthAP-webgui /tmp/raspap-webgui || install_error "Unable to download files from github"
    sudo mv /tmp/raspap-webgui $webroot_dir || install_error "Unable to move raspap-webgui to web root"
}

# Sets files ownership in web root directory
function change_file_ownership() {
    if [ ! -d "$webroot_dir" ]; then
        install_error "Web root directory doesn't exist"
    fi

    install_log "Changing file ownership in web root directory"
    sudo chown -R $raspap_user:$raspap_user "$webroot_dir" || install_error "Unable to change file ownership for '$webroot_dir'"
}

# Check for existing /etc/network/interfaces and /etc/hostapd/hostapd.conf files
function check_for_old_configs() {
    if [ -f /etc/network/interfaces ]; then
        sudo cp /etc/network/interfaces "$raspap_dir/backups/interfaces.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/interfaces.`date +%F-%R`" "$raspap_dir/backups/interfaces"
    fi

    if [ -f /etc/hostapd/hostapd.conf ]; then
        sudo cp /etc/hostapd/hostapd.conf "$raspap_dir/backups/hostapd.conf.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/hostapd.conf.`date +%F-%R`" "$raspap_dir/backups/hostapd.conf"
    fi

    if [ -f /etc/dnsmasq.conf ]; then
        sudo cp /etc/dnsmasq.conf "$raspap_dir/backups/dnsmasq.conf.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/dnsmasq.conf.`date +%F-%R`" "$raspap_dir/backups/dnsmasq.conf"
    fi

    if [ -f /etc/dnsmasq.hosts ]; then
        sudo cp /etc/dnsmasq.hosts "$raspap_dir/backups/dnsmasq.hosts.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/dnsmasq.hosts.`date +%F-%R`" "$raspap_dir/backups/dnsmasq.hosts"
    fi

    if [ -f /etc/dhcpcd.conf ]; then
        sudo cp /etc/dhcpcd.conf "$raspap_dir/backups/dhcpcd.conf.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/dhcpcd.conf.`date +%F-%R`" "$raspap_dir/backups/dhcpcd.conf"
    fi

    if [ -f /etc/rc.local ]; then
        sudo cp /etc/rc.local "$raspap_dir/backups/rc.local.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/rc.local.`date +%F-%R`" "$raspap_dir/backups/rc.local"
    fi

    if [ -f /etc/nftables.conf ]; then
        sudo cp /etc/nftables.conf "$raspap_dir/backups/nftables.conf.`date +%F-%R`"
        sudo ln -sf "$raspap_dir/backups/nftables.conf.`date +%F-%R`" "$raspap_dir/backups/nftables.conf"
    fi
}

# Move configuration file to the correct location
function move_config_file() {
    if [ ! -d "$raspap_dir" ]; then
        install_error "'$raspap_dir' directory doesn't exist"
    fi

    install_log "Moving configuration file to '$raspap_dir'"
    sudo mv "$webroot_dir"/raspap.php "$raspap_dir" || install_error "Unable to move files to '$raspap_dir'"
    sudo chown -R $raspap_user:$raspap_user "$raspap_dir" || install_error "Unable to change file ownership for '$raspap_dir'"
}

# select iptables or nftables

function network_tables() {
    install_log "Selecting iptables or nftable rules"
    if [ $version -lt 11 ]; then
    install_log "Use iptables"
    sudo apt-get -y install iptables
    tablerouteA='iptables -t nat -A POSTROUTING -s 10.3.141.0\/24 -o lokitun0 -j MASQUERADE #RASPAP'
    tablerouteB='iptables -t nat -A POSTROUTING -j MASQUERADE #RASPAP'
    else
    install_log "Use nftables"
    sudo apt-get -y install nftables
    sudo apt-get -y purge iptables
    sudo systemctl enable nftables.service
    fi
    }

# Set up default configuration
function default_configuration() {
    install_log "Setting up hostapd"
    if [ -f /etc/default/hostapd ]; then
        sudo mv /etc/default/hostapd /tmp/default_hostapd.old || install_error "Unable to remove old /etc/default/hostapd file"
    fi
    sudo mv $webroot_dir/config/default_hostapd /etc/default/hostapd || install_error "Unable to move hostapd defaults file"
    sudo mv $webroot_dir/config/hostapd.conf /etc/hostapd/hostapd.conf || install_error "Unable to move hostapd configuration file"
    sudo mv $webroot_dir/config/dnsmasq.conf /etc/dnsmasq.conf || install_error "Unable to move dnsmasq configuration file"
    sudo mv $webroot_dir/config/dnsmasq.hosts /etc/dnsmasq.hosts || install_error "unable to move dnsmasq hosts file"
    sudo mv $webroot_dir/config/dhcpcd.conf /etc/dhcpcd.conf || install_error "Unable to move dhcpcd configuration file"
    sudo mv $webroot_dir/config/head /etc/resolvconf/resolv.conf.d/head || install_error "Unable to move resolvconf head file"
    sudo mv $webroot_dir/config/nftables.conf /etc/nftables.conf || install_error "unable to move nftables configuration file"
# Add loki-whois service
    sudo mv $webroot_dir/config/loki-whois /usr/local/bin/loki-whois || install_error "unable to move loki-whois binary"
    sudo mv $webroot_dir/config/loki-whois.service /etc/systemd/system/loki-whois.service || install_error "unable to move loki-whois.service to system"
    sudo systemctl enable --now loki-whois #start loki-whois as service

    sudo rm /etc/resolv.conf
    sudo ln -s /etc/resolvconf/run/resolv.conf /etc/resolv.conf
    sudo resolvconf -u || install_error "Unable to update resolv.conf"


    # LokiPAP Batch files relocation and permissions in user loki-network directory

    sudo mv $webroot_dir/config/lokilaunch.sh /var/lib/lokinet/ || install error "Unable to move lokilaunch.sh, install Lokinet first"
    sudo mv $webroot_dir/config/mobile.sh /var/lib/lokinet/ || install error "Unable to move mobile.sh, file not found"

    #changes persmission on lokilaunch.sh and mobile.sh

    sudo chmod 755 /var/lib/lokinet/lokilaunch.sh
    sudo chmod 777 /var/lib/lokinet/mobile.sh

    # Generate required lines for Rasp AP to place into rc.local file.
    # #RASPAP is for removal

    lines=(

    'echo 1 > \/proc\/sys\/net\/ipv4\/ip_forward #RASPAP'
    "$tablerouteA"
    "$tablerouteB"
    # 'if ! [cat \/sys\/class\/net\/eth0\/carrier] ; then'
    '\/var\/lib\/lokinet\/mobile.sh'
    # 'fi #end'

    )

    for line in "${lines[@]}"; do
        if grep "$line" /etc/rc.local > /dev/null; then
            echo "$line: Line already added"
        else
            sudo sed -i "s/^exit 0$/$line\nexit 0/" /etc/rc.local
            echo "Adding line $line"
        fi
    done
}


# Add a single entry to the sudoers file
function sudo_add() {
    sudo bash -c "echo \"www-data ALL=(ALL) NOPASSWD:$1\" | (EDITOR=\"tee -a\" visudo)" \
        || install_error "Unable to patch /etc/sudoers"
}

# Adds www-data user to the sudoers file with restrictions on what the user can execute
function patch_system_files() {
    # add symlink to prevent wpa_cli cmds from breaking with multiple wlan interfaces
    install_log "symlinked wpa_supplicant hooks for multiple wlan interfaces"
    sudo ln -s /usr/share/dhcpcd/hooks/10-wpa_supplicant /etc/dhcp/dhclient-enter-hooks.d/
    # Set commands array
    cmds=(

          #added for forced Lokinet
        "/sbin/ip"
          #
        "/sbin/ifdown"
        "/sbin/ifup"
        "/bin/cat /etc/wpa_supplicant/wpa_supplicant.conf"
        "/bin/cat /etc/wpa_supplicant/wpa_supplicant-wlan[0-9].conf"
        "/bin/cp /tmp/wifidata /etc/wpa_supplicant/wpa_supplicant.conf"
        "/bin/cp /tmp/wifidata /etc/wpa_supplicant/wpa_supplicant-wlan[0-9].conf"
        "/sbin/wpa_cli -i wlan[0-9] scan_results"
        "/sbin/wpa_cli -i wlan[0-9] scan"
        "/sbin/wpa_cli -i wlan[0-9] reconfigure"
	      "/sbin/wpa_cli -i wlan[0-9] select_network"
        "/bin/cp /tmp/hostapddata /etc/hostapd/hostapd.conf"
        "/etc/init.d/hostapd start"
        "/etc/init.d/hostapd stop"
        "/etc/init.d/dnsmasq start"
        "/etc/init.d/dnsmasq stop"
        "/bin/cp /tmp/dhcpddata /etc/dnsmasq.conf"
        "/sbin/shutdown -h now"
        "/sbin/reboot"
        "/sbin/ip link set wlan[0-9] down"
        "/sbin/ip link set wlan[0-9] up"
        "/sbin/ip -s a f label wlan[0-9]"
        "/bin/cp /etc/raspap/networking/dhcpcd.conf /etc/dhcpcd.conf"
        "/etc/raspap/hostapd/enablelog.sh"
        "/etc/raspap/hostapd/disablelog.sh"
        "/var/lib/lokinet/lokilaunch.sh"

    )

    # Check if sudoers needs patching
    if [ $(sudo grep -c www-data /etc/sudoers) -ne 28 ]
    then
        # Sudoers file has incorrect number of commands. Wiping them out.
        install_log "Cleaning sudoers file"
        sudo sed -i '/www-data/d' /etc/sudoers
        install_log "Patching system sudoers file"
        # patch /etc/sudoers file
        for cmd in "${cmds[@]}"
        do
            sudo_add $cmd
            IFS=$'\n'
        done
    else
        install_log "Sudoers file already patched"
    fi

    # Unmask and enable hostapd.service
    sudo systemctl unmask hostapd.service
    sudo systemctl enable hostapd.service

    #crontab daily lokinet updates and log
cat > /var/spool/cron/crontabs/root <<-'EOF'
check daily for lokinet updates and update as required
logfile=/var/log/lokinet_cron_update.txt
0 1 * * 1-7 sudo apt-get update && sudo apt-get -y install lokinet >> "$logfile" 2>&1
0 1 * * 1-7 sudo apt-get -y autoremove >> "$logfile" 2>&1
0 1 * * 1-7 date >> "$logfile"
EOF
    }


# Optimize configuration of php-cgi.
function optimize_php() {
    install_log "Optimize PHP configuration"
    if [ ! -f "$phpcgiconf" ]; then
        install_warning "PHP configuration could not be found."
        return
    fi

    # Backup php.ini and create symlink for restoring.
    datetimephpconf=$(date +%F-%R)
    sudo cp "$phpcgiconf" "$raspap_dir/backups/php.ini.$datetimephpconf"
    sudo ln -sf "$raspap_dir/backups/php.ini.$datetimephpconf" "$raspap_dir/backups/php.ini"

    echo -n "Enable HttpOnly for session cookies (Recommended)? [Y/n]: "
    read answer
    if [ "$answer" != 'n' ] && [ "$answer" != 'N' ]; then
        echo "Php-cgi enabling session.cookie_httponly."
        sudo sed -i -E 's/^session\.cookie_httponly\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/session.cookie_httponly = 1/' "$phpcgiconf"
    fi

    if [ "$php_package" = "php7.0-cgi" ]; then
        echo -n "Enable PHP OPCache? [Y/n]: "
        read answer
        if [ "$answer" != 'n' ] && [ "$answer" != 'N' ]; then
            echo "Php-cgi enabling opcache.enable."
            sudo sed -i -E 's/^;?opcache\.enable\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/opcache.enable = 1/' "$phpcgiconf"
            # Make sure opcache extension is turned on.
            if [ -f "/usr/sbin/phpenmod" ]; then
                sudo phpenmod opcache
            else
                install_warning "phpenmod not found."
            fi
        fi
    fi
}

function install_complete() {
    install_log "Installation completed!"

    echo -n "The system needs to be rebooted as a final step. Reboot now? [y/N]: "
    read answer
    if [[ $answer != "y" ]]; then
        echo "Installation reboot aborted."
        exit 0
    fi
    install_log "Shutting Down"
    echo -n "Allow a minute for reinitialization then connect wifi to SSID loki-access and use default password 'ChangeMe'"
    sleep 8
    sudo shutdown -r now || install_error "Unable to execute shutdown"
}

function install_raspap() {
    display_welcome
    config_installation
    update_system_packages
    install_dependencies
    common_interfaces
    stop_lokinet
    check_for_networkmananger
    optimize_php
    enable_php_lighttpd
    create_raspap_directories
    check_for_old_configs
    download_latest_files
    change_file_ownership
    create_logging_scripts
    move_config_file
    network_tables
    default_configuration
    patch_system_files
    install_complete
}
