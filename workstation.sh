#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEFAULT_USER="headless"
DEFAULT_HOME="/home/$DEFAULT_USER"
CONTAINER_NAME="workstation"

# Menu options
MENU_UP="up"
MENU_DOWN="down"
MENU_RESET="reset"

# Runs command as root in container
ws_cmd_root() {
    docker exec -e "DEBIAN_FRONTEND=noninteractive" -u root:root "$CONTAINER_NAME" "$@"
}

# Runs command as user in container
ws_cmd_user() {
    docker exec -u "$DEFAULT_USER:$DEFAULT_USER" "$CONTAINER_NAME" "$@"
}

# Copies file from host to container
ws_cp() {
    docker cp "$1" "$CONTAINER_NAME:$2"
}

# Container first-time setup
ws_setup() {
    local password
    password=$(
    whiptail --title "Workstation" --passwordbox "Type a password for VNC and sudo" 0 0 \
    3>&1 1>&2 2>&3
    )

    # If password is empty, set default password
    if [[ -z "$password" ]]; then
        echo "Using default password"
        password="headless"
    fi

    # Docker run args
    local args
    args=(
        # Deattached
        -d
        # Shared memory size
        --shm-size=256m
        # Exposed ports
        -p "127.0.0.1:36901:6901"
        # Exposed volumes
        -v "$SCRIPT_DIR/docs:/home/headless/Documents"
        # Password for VNC
        -e "VNC_PW=$password"
        # Host and container name
        --name "$CONTAINER_NAME" --hostname "$CONTAINER_NAME"
        # Image used
        accetto/debian-vnc-xfce-firefox-g3
    )

    docker run "${args[@]}"

    # Wait for startup
    sleep 2

    # Copies id_rsa if exists
    if [[ -f "$HOME/.ssh/id_rsa" ]]; then
        echo "id_rsa detected, copying to container"
        ws_cmd_user mkdir "$DEFAULT_HOME/.ssh"
        ws_cp "$HOME/.ssh/id_rsa" "$DEFAULT_HOME/.ssh"
        ws_cp "$HOME/.ssh/id_rsa.pub" "$DEFAULT_HOME/.ssh"
    fi

    # Change sudo password
    ws_cp "$SCRIPT_DIR/installers/sudo.sh" "/tmp/sudo.sh"
    ws_cmd_root bash /tmp/sudo.sh "$DEFAULT_USER" "$password"
}

# Install external packages
ws_pkgs() {
    # Adding backports
    ws_cp "$SCRIPT_DIR/conf/apt/backports.list" "/etc/apt/sources.list.d"
    # Refresh deps first
    ws_cmd_root apt update
    ws_cmd_root apt upgrade -y

    # -- Tools -- #
    ws_cmd_root apt install -y btop curl git gpg

    # -- Shell -- #
    ws_cmd_root apt install -y zsh
    ws_cp "$SCRIPT_DIR/installers/oh-my-zsh.sh" "/tmp/oh-my-zsh.sh"
    ws_cmd_user bash /tmp/oh-my-zsh.sh
    ws_cmd_root chsh "$DEFAULT_USER" -s /usr/bin/zsh

    # -- VSCodium -- #
    ws_cp "$SCRIPT_DIR/installers/vscodium.sh" "/tmp/vscodium.sh"
    ws_cmd_root bash /tmp/vscodium.sh
    ws_cmd_root apt update
    ws_cmd_root apt install -y codium

    # Shortcut
    ws_cp "$SCRIPT_DIR/desktop/VSCodium.desktop" "$DEFAULT_HOME/Desktop"

    # -- Programming lang -- #
    ws_cmd_root apt install -y build-essential php-cli php-xdebug python3 valac
    ws_cmd_root apt install -t bookworm-backports -y golang-go

    ws_cmd_root curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
    ws_cmd_root bash /tmp/nodesource_setup.sh
    ws_cmd_root apt install -y nodejs
    ws_cmd_root npm install --global yarn

    # -- Build tools -- #
    ws_cmd_root apt install -y meson

    # -- DB -- #
    ws_cmd_root apt install -y mariadb-server
}

# Fully installs container
ws_install() {
    echo "Creating container..."
    ws_setup
    echo "Installing dependencies..."
    ws_pkgs
    docker restart "$CONTAINER_NAME" > /dev/null
    echo "Container ready to go!"
}

# Common action handler
menu_handler() {
    local choise
    choise="$1"

    case $choise in
        "$MENU_UP")
            docker start "$CONTAINER_NAME" > /dev/null
            ;;
        "$MENU_DOWN")
            docker stop "$CONTAINER_NAME" > /dev/null
            ;;
        "$MENU_RESET")
            if whiptail --title "Workstation" --yesno "Do you want to continue? This action is PERMANENT!" 0 0; then
                docker stop "$CONTAINER_NAME" > /dev/null
                docker container rm "$CONTAINER_NAME" > /dev/null
                ws_install
            fi
            ;;
    esac
}

# Interactive menu using whiptail
interactive() {
    local choise
    choise=$(
    whiptail --title "Workstation" --menu "Pick a subsection" 0 0 0 \
    	"$MENU_UP" "Start container" \
        "$MENU_DOWN" "Stop container" \
        "$MENU_RESET" "Reset container" \
        3>&2 2>&1 1>&3
    )

    menu_handler "$choise"
}

# Non-interactive mode from arg
non_interactive() {
    menu_handler "$1"
}

main() {
    # Check first if docker is running
    if ! systemctl is-active --quiet docker.service; then
        echo "Docker is not running!"
        exit 1
    fi

    # Check if container exists
    if ! docker inspect "$CONTAINER_NAME" > /dev/null 2>&1; then
        # If the container doesn't exist, run it with default options
        ws_install
        exit 0
    fi

    # If 1st arg exists run non-interative
    if [[ "$#" -ne 1 ]]; then
        interactive
    else
        non_interactive "$1"
    fi
}

main "$@"
