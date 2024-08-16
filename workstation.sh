#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEFAULT_USER="headless"
DEFAULT_HOME="/home/$DEFAULT_USER"
CONTAINER_NAME="workstation"

# Runs command as root in container
ws_cmd_root() {
    docker exec -e "DEBIAN_FRONTEND=noninteractive" -u root:root "$CONTAINER_NAME" "$@"
}

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
        -v "./docs:/home/headless/Documents"
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
        ws_cmd_root mkdir "$DEFAULT_HOME/.ssh"
        ws_cp "$HOME/.ssh/id_rsa" "$DEFAULT_HOME/.ssh"
        ws_cp "$HOME/.ssh/id_rsa.pub" "$DEFAULT_HOME/.ssh"
    fi

    # Change sudo password
    ws_cp "$SCRIPT_DIR/scripts/sudo.sh" "/tmp/sudo.sh"
    ws_cmd_root bash /tmp/sudo.sh "$DEFAULT_USER" "$password"
}

# Install external packages
ws_pkgs() {
    # Refresh deps first
    ws_cmd_root apt update
    ws_cmd_root apt upgrade -y

    # -- Tools -- #
    ws_cmd_root apt install -y curl git gpg

    # -- Shell -- #
    ws_cmd_root apt install -y zsh
    ws_cp "$SCRIPT_DIR/scripts/oh-my-zsh.sh" "/tmp/oh-my-zsh.sh"
    ws_cmd_user bash /tmp/oh-my-zsh.sh
    ws_cmd_root chsh "$DEFAULT_USER" -s /usr/bin/zsh

    # -- VSCodium -- #
    ws_cp "$SCRIPT_DIR/scripts/vscodium.sh" "/tmp/vscodium.sh"
    ws_cmd_root bash /tmp/vscodium.sh
    ws_cmd_root apt update
    ws_cmd_root apt install -y codium

    # Shortcut
    ws_cp "$SCRIPT_DIR/desktop/VSCodium.desktop" "$DEFAULT_HOME/Desktop"

    # -- Programming lang -- #
    ws_cmd_root apt install -y build-essential php-cli php-xdebug python3 golang

    ws_cmd_root curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
    ws_cmd_root bash /tmp/nodesource_setup.sh
    ws_cmd_root apt install -y nodejs
    ws_cmd_root npm install --global yarn

    # -- DB -- #
    ws_cmd_root apt install -y mariadb-server
}

ws_install() {
    echo "Creating container..."
    ws_setup
    echo "Installing dependencies..."
    ws_pkgs
    docker restart "$CONTAINER_NAME" > /dev/null
    echo "Container ready to go!"
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

    # Start - Stop controls
    local choise
    choise=$(
    whiptail --title "Workstation" --menu "Pick a subsection" 0 0 0 \
    	"1" "Start container" \
        "2" "Stop container" \
        "3" "Reset container" \
        3>&2 2>&1 1>&3
    )

    case $choise in
        "1")
            docker start "$CONTAINER_NAME"
            ;;
        "2")
            docker stop "$CONTAINER_NAME"
            ;;
        "3")
            docker stop "$CONTAINER_NAME" > /dev/null
            docker container rm "$CONTAINER_NAME" > /dev/null
            ws_install
            ;;
    esac
}

main
