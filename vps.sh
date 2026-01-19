#!/bin/bash
set -euo pipefail

# =============================
# VM Manager v3.0
# Sponsor: Grandpa Academy
# Developer: MD HR
# =============================

# Function to display main header
display_header() {
    clear
    echo ""
    echo "================================================================================"
    echo "                     VIRTUAL MACHINE MANAGER v3.0"
    echo "================================================================================"
    echo ""
    echo "    ██╗   ██╗███╗   ███╗    ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ███████╗██████╗ "
    echo "    ██║   ██║████╗ ████║    ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ██╔════╝██╔══██╗"
    echo "    ██║   ██║██╔████╔██║    ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗█████╗  ██████╔╝"
    echo "    ╚██╗ ██╔╝██║╚██╔╝██║    ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║██╔══╝  ██╔══██╗"
    echo "     ╚████╔╝ ██║ ╚═╝ ██║    ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝███████╗██║  ██║"
    echo "      ╚═══╝  ╚═╝     ╚═╝    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝"
    echo ""
    echo "================================================================================"
    echo " Sponsor: Grandpa Academy   |   Developer: MD HR   |   Version: 3.0"
    echo "================================================================================"
    echo ""
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "🔹 \033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "⚠️  \033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "❌ \033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "✅ \033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "🎯 \033[1;36m[INPUT]\033[0m $message" ;;
        "VM") echo -e "🖥️  \033[1;93m[VM]\033[0m $message" ;;
        "START") echo -e "🚀 \033[1;92m[START]\033[0m $message" ;;
        "STOP") echo -e "🛑 \033[1;91m[STOP]\033[0m $message" ;;
        *) echo "📌 $message" ;;
    esac
}

# Function to validate input
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a number"
                return 1
            fi
            ;;
        "size")
            if ! [[ "$value" =~ ^[0-9]+[GgMm]$ ]]; then
                print_status "ERROR" "Must be a size with unit (e.g., 100G, 512M)"
                return 1
            fi
            ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 22 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (22-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore, and contain only lowercase letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check KVM availability
check_kvm() {
    if [ -e /dev/kvm ]; then
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            return 0
        else
            print_status "WARN" "KVM device exists but no permission. You may need to:"
            echo "    sudo usermod -aG kvm $USER"
            echo "    Then logout and login again"
            return 1
        fi
    else
        return 1
    fi
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img")
    local missing_deps=()
    
    print_status "INFO" "Checking dependencies..."
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian, install with:"
        echo "    sudo apt update && sudo apt install qemu-system-x86 qemu-utils cloud-image-utils wget"
        print_status "INFO" "On CentOS/RHEL, install with:"
        echo "    sudo yum install qemu-kvm qemu-img cloud-utils wget"
        exit 1
    fi
    
    print_status "SUCCESS" "All dependencies are installed"
    
    # Check KVM availability
    echo ""
    if check_kvm; then
        print_status "SUCCESS" "KVM acceleration available - VMs will run fast"
        KVM_AVAILABLE=true
    else
        print_status "WARN" "KVM not available - VMs will use software emulation (slower)"
        print_status "INFO" "To enable KVM:"
        echo "    1. Enable virtualization in BIOS (VT-x for Intel, AMD-V for AMD)"
        echo "    2. Load KVM module: sudo modprobe kvm && sudo modprobe kvm_intel (or kvm_amd)"
        echo "    3. Add user to kvm group: sudo usermod -aG kvm $USER"
        KVM_AVAILABLE=false
    fi
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear previous variables
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED BASE_IMG
        
        # Load the configuration
        source "$config_file"
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
BASE_IMG="$BASE_IMG"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    echo ""
    
    # OS Selection
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                    SELECT OPERATING SYSTEM                       ║"
    echo "╠══════════════════════════════════════════════════════════════════╣"
    echo "║                                                                  ║"
    
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        printf "║   %2d. %-30s %-10s ║\n" "$i" "$os" "($(echo ${OS_OPTIONS[$os]} | cut -d'|' -f1))"
        os_options[$i]="$os"
        ((i++))
    done
    
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    echo ""
    print_status "INFO" "Selected: $os"
    print_status "INFO" "Default username: $DEFAULT_USERNAME"
    print_status "INFO" "Default password: $DEFAULT_PASSWORD"
    echo ""

    # Custom Inputs with validation
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            # Check if VM name already exists
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        echo
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Password cannot be empty"
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory in MB (default: 2048): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        if validate_input "number" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            # Check if port is already in use
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: n): ")" gui_input
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Additional network options
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, press Enter for none): ")" PORT_FORWARDS

    # Set file paths - using separate base image and VM-specific overlay
    BASE_IMG="$VM_DIR/base-$OS_TYPE-$CODENAME.img"
    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Setting up VM image..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Download base image if it doesn't exist
    if [[ -f "$BASE_IMG" ]]; then
        print_status "INFO" "Base image already exists. Skipping download."
    else
        print_status "INFO" "Downloading base image from $IMG_URL..."
        if wget --progress=bar:force "$IMG_URL" -O "$BASE_IMG.tmp" 2>&1; then
            mv "$BASE_IMG.tmp" "$BASE_IMG"
            print_status "SUCCESS" "Base image downloaded successfully"
        else
            print_status "ERROR" "Failed to download image from $IMG_URL"
            rm -f "$BASE_IMG.tmp"
            exit 1
        fi
    fi
    
    # Create VM-specific overlay image (this prevents locking issues)
    print_status "INFO" "Creating VM overlay disk image ($DISK_SIZE)..."
    if qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$IMG_FILE" "$DISK_SIZE" 2>&1; then
        print_status "SUCCESS" "VM overlay image created"
    else
        print_status "ERROR" "Failed to create VM overlay image"
        exit 1
    fi

    # cloud-init configuration
    print_status "INFO" "Creating cloud-init configuration..."
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    lock_passwd: false
    passwd: $(openssl passwd -6 "$PASSWORD" 2>/dev/null || echo '$6$rounds=4096$saltsalt$encrypted')
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
package_update: false
package_upgrade: false
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if cloud-localds "$SEED_FILE" user-data meta-data 2>&1; then
        print_status "SUCCESS" "Cloud-init seed image created"
    else
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' image setup complete."
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if load_vm_config "$vm_name"; then
        if pgrep -f "qemu-system-x86_64.*$IMG_FILE" >/dev/null 2>&1; then
            return 0
        fi
    fi
    return 1
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        # Check if VM is already running
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "VM '$vm_name' is already running!"
            print_status "INFO" "Use option 3 to stop it first, or check with 'ps aux | grep qemu'"
            return 1
        fi
        
        print_status "INFO" "Starting VM: $vm_name"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            print_status "INFO" "The VM image may have been deleted. Please recreate the VM."
            return 1
        fi
        
        # Check if seed file exists
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Base QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -m "$MEMORY"
            -smp "$CPUS"
            -drive "file=$IMG_FILE,format=qcow2,if=virtio,cache=writeback"
            -drive "file=$SEED_FILE,format=raw,if=virtio,readonly=on"
            -boot order=c
            -device virtio-net-pci,netdev=n0
            -netdev "user,id=n0,hostfwd=tcp::$SSH_PORT-:22"
        )
        
        # Add KVM acceleration if available
        if [[ "$KVM_AVAILABLE" == true ]]; then
            qemu_cmd+=(-enable-kvm -cpu host)
            print_status "SUCCESS" "Using KVM acceleration"
        else
            qemu_cmd+=(-cpu qemu64)
            print_status "WARN" "Using software emulation (slow) - KVM not available"
        fi

        # Add port forwards if specified
        if [[ -n "$PORT_FORWARDS" ]]; then
            IFS=',' read -ra forwards <<< "$PORT_FORWARDS"
            local net_id=1
            for forward in "${forwards[@]}"; do
                IFS=':' read -r host_port guest_port <<< "$forward"
                qemu_cmd+=(-netdev "user,id=n${net_id},hostfwd=tcp::$host_port-:$guest_port")
                ((net_id++))
            done
        fi

        # Add GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            qemu_cmd+=(-vga virtio -display gtk,gl=on)
            print_status "INFO" "Starting VM in GUI mode..."
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
            print_status "INFO" "Starting VM in console mode..."
            print_status "INFO" "Press Ctrl+A then X to stop the VM"
        fi

        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )

        echo ""
        print_status "START" "Starting QEMU VM..."
        echo ""
        
        # Run QEMU
        "${qemu_cmd[@]}"
        
        print_status "INFO" "VM $vm_name has been shut down"
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            # Stop VM if running
            if is_vm_running "$vm_name"; then
                print_status "INFO" "Stopping running VM first..."
                stop_vm "$vm_name"
            fi
            
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                   VM DETAILS: $vm_name"
        echo "╠══════════════════════════════════════════════════════════════════╣"
        echo "║                                                                  ║"
        echo "║   Basic Information:                                             ║"
        echo "║   • OS Type:      $OS_TYPE                                        "
        echo "║   • Hostname:     $HOSTNAME                                       "
        echo "║   • Created:      $CREATED                                        "
        echo "║                                                                  ║"
        echo "║   Access Details:                                                ║"
        echo "║   • Username:     $USERNAME                                       "
        echo "║   • Password:     ******                                         "
        echo "║   • SSH Port:     $SSH_PORT                                       "
        echo "║   • SSH Command:  ssh -p $SSH_PORT $USERNAME@localhost            "
        echo "║                                                                  ║"
        echo "║   Resource Allocation:                                           ║"
        echo "║   • Memory:       $MEMORY MB                                      "
        echo "║   • CPU Cores:    $CPUS                                           "
        echo "║   • Disk Size:    $DISK_SIZE                                      "
        echo "║                                                                  ║"
        echo "║   Configuration:                                                 ║"
        echo "║   • GUI Mode:     $GUI_MODE                                       "
        echo "║   • Port Forwards: ${PORT_FORWARDS:-None}                        "
        echo "║                                                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            pkill -TERM -f "qemu-system-x86_64.*$IMG_FILE"
            sleep 3
            if is_vm_running "$vm_name"; then
                print_status "WARN" "VM did not stop gracefully, forcing termination..."
                pkill -9 -f "qemu-system-x86_64.*$IMG_FILE"
                sleep 1
            fi
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to edit VM configuration
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        # Check if VM is running
        if is_vm_running "$vm_name"; then
            print_status "ERROR" "Cannot edit configuration while VM is running"
            print_status "INFO" "Please stop the VM first (option 3)"
            return 1
        fi
        
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo ""
            echo "What would you like to edit?"
            echo "  1) Hostname (Current: $HOSTNAME)"
            echo "  2) Username (Current: $USERNAME)"
            echo "  3) Password (Current: ******)"
            echo "  4) SSH Port (Current: $SSH_PORT)"
            echo "  5) GUI Mode (Current: $GUI_MODE)"
            echo "  6) Port Forwards (Current: ${PORT_FORWARDS:-None})"
            echo "  7) Memory (RAM) (Current: $MEMORY MB)"
            echo "  8) CPU Count (Current: $CPUS)"
            echo "  9) Disk Size (Current: $DISK_SIZE)"
            echo "  0) Back to main menu"
            echo ""
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "Enter new password: ")" new_password
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password cannot be empty"
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
                        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                        if validate_input "port" "$new_ssh_port"; then
                            SSH_PORT="$new_ssh_port"
                            break
                        fi
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, current: $GUI_MODE): ")" gui_input
                        gui_input="${gui_input:-}"
                        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
                            GUI_MODE=true
                            break
                        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            break
                        elif [ -z "$gui_input" ]; then
                            break
                        else
                            print_status "ERROR" "Please answer y or n"
                        fi
                    done
                    ;;
                6)
                    read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory in MB (current: $MEMORY): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        if validate_input "number" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                9)
                    print_status "INFO" "Current disk size: $DISK_SIZE"
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
                        if validate_input "size" "$new_disk_size"; then
                            if qemu-img resize "$IMG_FILE" "$new_disk_size" 2>&1; then
                                DISK_SIZE="$new_disk_size"
                                print_status "SUCCESS" "Disk resized to $new_disk_size"
                            else
                                print_status "ERROR" "Failed to resize disk"
                            fi
                            break
                        fi
                    done
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            # Recreate seed image with new configuration if user/password/hostname changed
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                print_status "INFO" "Updating cloud-init configuration..."
                setup_vm_image
            fi
            
            # Save configuration
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                VM PERFORMANCE: $vm_name"
        echo "╠══════════════════════════════════════════════════════════════════╣"
        echo "║                                                                  ║"
        
        if is_vm_running "$vm_name"; then
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                echo "║   Status:        🟢 Running (PID: $qemu_pid)                    "
                echo "║                                                                  ║"
                echo "║   Process Stats:                                                 "
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz --no-headers 2>/dev/null | while read pid cpu mem sz rss vsz; do
                    echo "║     PID: $pid | CPU: $cpu% | MEM: $mem%                      "
                done
            fi
        else
            echo "║   Status:        🔴 Stopped                                       "
            echo "║                                                                  ║"
            echo "║   Configuration:                                                 "
            echo "║   • Memory:       $MEMORY MB allocated                            "
            echo "║   • CPU Cores:    $CPUS allocated                                 "
            echo "║   • Disk Size:    $DISK_SIZE allocated                           "
        fi
        
        echo "║                                                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to display VM list
display_vm_list() {
    local vms=($(get_vm_list))
    local vm_count=${#vms[@]}
    
    if [ $vm_count -gt 0 ]; then
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                   AVAILABLE VIRTUAL MACHINES                     ║"
        echo "╠══════════════════════════════════════════════════════════════════╣"
        echo "║                                                                  ║"
        echo "║   No.  VM Name            Status      SSH Port    Memory   CPU  ║"
        echo "║   ─────────────────────────────────────────────────────────────  ║"
        
        for i in "${!vms[@]}"; do
            local vm_name="${vms[$i]}"
            local status="🔴 Stopped"
            local ssh_port="2222"
            local memory="2048"
            local cpus="2"
            
            if [[ -f "$VM_DIR/$vm_name.conf" ]]; then
                ssh_port=$(grep '^SSH_PORT=' "$VM_DIR/$vm_name.conf" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "2222")
                memory=$(grep '^MEMORY=' "$VM_DIR/$vm_name.conf" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "2048")
                cpus=$(grep '^CPUS=' "$VM_DIR/$vm_name.conf" | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "2")
                
                if is_vm_running "$vm_name"; then
                    status="🟢 Running"
                fi
            fi
            
            printf "║   %2d.  %-15s  %-10s  %-8s  %-6s  %-4s ║\n" \
                $((i+1)) "$vm_name" "$status" "$ssh_port" "${memory}MB" "$cpus"
        done
        
        echo "║                                                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        display_vm_list
        
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║                      MAIN MENU                                   ║"
        echo "╠══════════════════════════════════════════════════════════════════╣"
        echo "║                                                                  ║"
        echo "║   1. 🆕 Create New Virtual Machine                               ║"
        
        if [ $vm_count -gt 0 ]; then
            echo "║   2. 🚀 Start Virtual Machine                                    ║"
            echo "║   3. 🛑 Stop Virtual Machine                                     ║"
            echo "║   4. 📊 View VM Information                                     ║"
            echo "║   5. ⚙️  Edit VM Configuration                                   ║"
            echo "║   6. 📈 Monitor VM Performance                                  ║"
            echo "║   7. 🗑️  Delete Virtual Machine                                  ║"
        fi
        
        echo "║   8. 🔍 Check System Requirements                                 ║"
        echo "║   0. 🚪 Exit                                                        ║"
        echo "║                                                                  ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available. Create one first."
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                else
                    print_status "ERROR" "No VMs available"
                fi
                ;;
            8)
                check_dependencies
                echo ""
                print_status "INFO" "System Information:"
                echo "  • CPU Cores: $(nproc)"
                echo "  • Total RAM: $(free -h | grep Mem | awk '{print $2}')"
                echo "  • Available Disk: $(df -h . | tail -1 | awk '{print $4}')"
                echo "  • VM Directory: $VM_DIR"
                echo ""
                read -p "$(print_status "INPUT" "Press Enter to continue...")"
                ;;
            0)
                echo ""
                print_status "INFO" "Thank you for using VM Manager!"
                echo "  Sponsor: Grandpa Academy"
                echo "  Developer: MD HR"
                echo ""
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Global variable for KVM availability
KVM_AVAILABLE=false

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
)

# Check dependencies
check_dependencies

# Start the main menu
main_menu
