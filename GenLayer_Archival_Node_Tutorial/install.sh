#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="$HOME/genlayer-node"

# Function to display the animated banner
display_banner() {
    # Install dependencies for animation if not present
    if ! command -v figlet &> /dev/null || ! command -v lolcat &> /dev/null; then
        echo "Installing animation dependencies..."
        sudo apt-get update > /dev/null 2>&1
        
        if ! command -v gem &> /dev/null; then
            sudo apt-get install -y ruby-full > /dev/null 2>&1
        fi
        
        if ! command -v figlet &> /dev/null; then
            sudo apt-get install -y figlet > /dev/null 2>&1
        fi
        
        if ! command -v lolcat &> /dev/null; then
            sudo gem install lolcat > /dev/null 2>&1
        fi
    fi

    clear
    figlet -f slant "GenLayer" | lolcat
    figlet -f digital "Archive Node" | lolcat
    echo ""
    echo "========================================================================" | lolcat
    echo ""
}

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if node is installed
is_node_installed() {
    if [ -d "$INSTALL_DIR/genlayer-node-linux-amd64" ] && [ -f "$INSTALL_DIR/genlayer-node-linux-amd64/bin/genlayernode" ]; then
        return 0
    else
        return 1
    fi
}

# Check and install dependencies
check_dependencies() {
    print_info "Checking and installing dependencies..."
    
    # Update package lists
    sudo apt-get update > /dev/null 2>&1
    
    # Install basic dependencies
    PACKAGES_TO_INSTALL=""
    
    if ! command -v wget &> /dev/null; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL wget"
    fi
    
    if ! command -v curl &> /dev/null; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL curl"
    fi
    
    if ! command -v jq &> /dev/null; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL jq"
    fi
    
    if ! command -v screen &> /dev/null; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL screen"
    fi
    
    if ! command -v bc &> /dev/null; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL bc"
    fi
    
    if ! command -v lz4 &> /dev/null; then
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL liblz4-tool"
    fi
    
    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        print_info "Docker not found. Installing Docker..."
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL docker.io"
    fi
    
    # Install docker-compose if not present
    if ! command -v docker-compose &> /dev/null; then
        print_info "Docker Compose not found. Installing docker-compose..."
        PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL docker-compose"
    fi
    
    # Install packages if needed
    if [ ! -z "$PACKAGES_TO_INSTALL" ]; then
        print_info "Installing required packages: $PACKAGES_TO_INSTALL"
        sudo apt-get install -y $PACKAGES_TO_INSTALL > /dev/null 2>&1
    fi
    
    # Make sure Docker service is running
    if ! sudo systemctl is-active --quiet docker; then
        print_info "Starting Docker service..."
        sudo systemctl start docker
    fi
    
    # Add current user to Docker group if not already
    if ! groups | grep -q docker; then
        print_info "Adding user to Docker group..."
        sudo usermod -aG docker $USER
        print_warn "You may need to log out and back in for group changes to take effect"
    fi
    
    print_success "All dependencies installed and configured!"
}

# Stop existing services
stop_services() {
    print_info "Stopping any existing GenLayer services..."
    
    # Stop systemd service if it exists
    if systemctl is-active --quiet genlayer-archive; then
        sudo systemctl stop genlayer-archive
        print_success "Stopped genlayer-archive service"
    fi
    
    # Stop any running GenLayer nodes
    pkill -f genlayernode 2>/dev/null || true
    pkill -f genvm-modules 2>/dev/null || true
    
    # If installation directory exists, stop Docker containers
    if [ -d "$INSTALL_DIR/genlayer-node-linux-amd64" ]; then
        cd "$INSTALL_DIR/genlayer-node-linux-amd64"
        if [ -f "docker-compose.yml" ]; then
            docker-compose down 2>/dev/null || true
        fi
        cd - > /dev/null
    fi
    
    print_success "All existing services stopped"
}

# Apply snapshot
apply_snapshot() {
    print_info "Applying GenLayer snapshot..."
    
    # Stop the service
    systemctl stop genlayer-archive.service 2>/dev/null || true
    
    # Remove existing database
    rm -rf $HOME/genlayer-node/genlayer-node-linux-amd64/data/node/genlayer.db
    
    # Download snapshot
    wget -O genlayer_snapshot.tar.lz4 https://files5.blacknodes.net/genlayer/genlayer-archive.tar.lz4
    
    # Create directory if needed
    mkdir -p $HOME/genlayer-node/genlayer-node-linux-amd64/data/node
    
    # Extract snapshot
    lz4 -cd genlayer_snapshot.tar.lz4 | tar xf - -C $HOME/genlayer-node/genlayer-node-linux-amd64/data/node
    
    # Clean up
    rm -f genlayer_snapshot.tar.lz4
    
    # Start the service
    systemctl start genlayer-archive.service
    
    print_success "Snapshot applied successfully!"
}

# Install Archive Node
install_archive_node() {
    local with_snapshot=$1
    
    display_banner
    
    # Check if already installed
    if is_node_installed; then
        print_warn "GenLayer Archive Node is already installed at $INSTALL_DIR"
        echo ""
        echo -e "${YELLOW}What would you like to do?${NC}"
        echo "1) Keep existing installation"
        echo "2) Reinstall (delete all data)"
        echo ""
        read -p "Select option (1-2): " reinstall_choice
        
        case $reinstall_choice in
            1)
                print_info "Keeping existing installation"
                if [ "$with_snapshot" = "true" ]; then
                    echo ""
                    print_info "Applying snapshot to existing installation..."
                    apply_snapshot
                fi
                sleep 2
                return
                ;;
            2)
                delete_node silent
                ;;
            *)
                print_error "Invalid option"
                sleep 2
                return
                ;;
        esac
    fi

    if [ "$with_snapshot" = "true" ]; then
        print_info "Starting GenLayer Archive Node installation with snapshot..."
    else
        print_info "Starting GenLayer Archive Node installation..."
    fi
    echo ""
    
    # Check system requirements
    print_info "Checking system requirements..."

    # Check available RAM
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 15 ]; then
        print_warn "System has less than 16GB RAM. Archive node requires at least 16GB RAM (32GB recommended)"
        echo ""
        echo "Continue anyway?"
        echo "1) Yes"
        echo "2) No"
        read -p "Select option (1-2): " ram_choice
        
        if [ "$ram_choice" != "1" ]; then
            return
        fi
    fi

    # Check dependencies
    check_dependencies

    # Create working directory
    print_info "Creating installation directory at $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Download node software
    VERSION="v0.3.9"
    print_info "Downloading GenLayer node version $VERSION..."
    wget -q --show-progress https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}/genlayer-node-linux-amd64-${VERSION}.tar.gz
    
    print_info "Extracting archive..."
    tar -xzf genlayer-node-linux-amd64-${VERSION}.tar.gz
    cd genlayer-node-linux-amd64
    
    print_success "Node software downloaded and extracted!"

    # Create configuration
    print_info "Creating archive node configuration..."
    mkdir -p configs/node
    cat > configs/node/config.yaml << 'EOF'
rollup:
  zksyncurl: "https://genlayer-testnet.rpc.caldera.xyz/http"
  zksyncwebsocketurl: "wss://genlayer-testnet.rpc.caldera.xyz/ws"
consensus:
  contractmanageraddress: "0x0761ff3847294eb3234f37Bf63fd7F1CA1E840bB"
  contractmainaddress: "0xe30293d600fF9B2C865d91307826F28006A458f4"
  contractdataaddress: "0x2a50afD9d3E0ACC824aC4850d7B4c5561aB5D27a"
  contractidlenessaddress: "0xD1D09c2743DD26d718367Ba249Ee1629BE88CF33"
  contractstakingaddress: "0x143d20974FA35f72B8103f54D8A47F2991940d99"
  genesis: 817855
datadir: "./data/node"
logging:
  level: "INFO"
  json: false
  file:
    enabled: true
    level: "DEBUG"
    folder: logs
    maxsize: 500
    maxage: 7
    maxbackups: 10
    localtime: false
    compress: true
node:
  mode: "archive"
  rpc:
    port: 9151
    endpoints:
      groups:
        ethereum: true
        debug: true
      methods:
        eth_blockNumber: true
        eth_getBlockByNumber: true
        eth_getBlockByHash: true
        eth_sendRawTransaction: false
        eth_getTransactionByHash: true
        eth_getTransactionReceipt: true
        eth_getLogs: true
        eth_getCode: true
        eth_getBalance: true
        eth_getStorageAt: true
        eth_call: true
        gen_getContractState: true
        gen_getContractSchema: true
        gen_getTransactionStatus: true
        gen_getTransactionReceipt: true
  ops:
    port: 9153
    endpoints:
      metrics: true
      health: true
  dev:
    disableSubscription: false
genvm:
  bin_dir: ./third_party/genvm/bin
  manage_modules: true
merkleforest:
  maxdepth: 16
  dbpath: "./data/node/merkle/forest/data.db"
  indexdbpath: "./data/node/merkle/index.db"
merkletree:
  maxdepth: 16
  dbpath: "./data/node/merkle/tree/"
EOF

    # Create Docker Compose file with the correct image
    print_info "Setting up Docker Compose..."
    cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  webdriver-container:
    image: yeagerai/genlayer-genvm-webdriver:0.0.3
    ports:
      - "4444:4444"
    restart: unless-stopped
EOF

    # Run precompilation (optional but recommended)
    print_info "Running precompilation step (this may take some time)..."
    ./third_party/genvm/bin/genvm precompile

    # Set up node account
    print_info "Creating node account..."
    echo ""
    echo -e "${YELLOW}Please enter a password for your node account (minimum 8 characters):${NC}"
    
    while true; do
        read -s NODE_PASSWORD
        echo ""
        
        if [ ${#NODE_PASSWORD} -lt 8 ]; then
            print_error "Password must be at least 8 characters! Try again."
            continue
        fi
        
        break
    done

    # Save password to file
    echo "$NODE_PASSWORD" > .node_password
    chmod 600 .node_password

    # Create account
    ./bin/genlayernode account new -c $(pwd)/configs/node/config.yaml --password "$NODE_PASSWORD" > account_info.txt 2>&1
    NODE_ADDRESS=$(grep "New address:" account_info.txt | awk '{print $3}')
    print_success "Node account created: $NODE_ADDRESS"
    
    # Start WebDriver
    print_info "Starting WebDriver container..."
    docker-compose up -d
    sleep 5

    if docker ps | grep -q webdriver; then
        print_success "WebDriver started successfully"
    else
        print_error "Failed to start WebDriver. Continuing anyway..."
    fi

    # Create systemd service file with required environment variables
    print_info "Creating systemd service..."
    sudo bash -c "cat > /etc/systemd/system/genlayer-archive.service << EOF
[Unit]
Description=GenLayer Archive Node
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/genlayer-node-linux-amd64
Environment=\"HEURISTKEY=dummy-key\"
Environment=\"COMPUT3KEY=dummy-key\"
Environment=\"IOINTELLIGENCE_API_KEY=dummy-key\"

# First ensure Docker container is running
ExecStartPre=/usr/bin/docker-compose up -d

# Then start the node
ExecStart=$INSTALL_DIR/genlayer-node-linux-amd64/bin/genlayernode run -c $INSTALL_DIR/genlayer-node-linux-amd64/configs/node/config.yaml --password \"$NODE_PASSWORD\"

# Restart policy
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF"

    # Create helper scripts
    print_info "Creating helper scripts..."
    
    # Script to check status
    cat > check-status.sh << 'EOF'
#!/bin/bash
echo -e "\033[0;32m=== GenLayer Node Status ===\033[0m"

# Check if service is running
if systemctl is-active --quiet genlayer-archive; then
    echo -e "Service: \033[0;32mRunning\033[0m"
else
    echo -e "Service: \033[0;31mNot running\033[0m"
fi

# Check if Docker container is running
if docker ps | grep -q webdriver; then
    echo -e "WebDriver: \033[0;32mRunning\033[0m"
else
    echo -e "WebDriver: \033[0;31mNot running\033[0m"
fi

# Check RPC endpoint
echo -n "RPC Status: "
if curl -s -X POST http://localhost:9151 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | grep -q "result"; then
  
  BLOCK=$(curl -s -X POST http://localhost:9151 \
    -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
    grep -o '"result":"[^"]*"' | cut -d'"' -f4 | sed 's/0x//')
  
  if [ -n "$BLOCK" ]; then
    DECIMAL_BLOCK=$((16#$BLOCK))
    echo -e "\033[0;32mResponding\033[0m (Block: $DECIMAL_BLOCK)"
  else
    echo -e "\033[0;32mResponding\033[0m"
  fi
else
  echo -e "\033[0;31mNot responding\033[0m"
fi
EOF
    chmod +x check-status.sh
    
    # Script to view logs
    cat > view-logs.sh << 'EOF'
#!/bin/bash
echo -e "\033[0;32m=== GenLayer Node Logs ===\033[0m"
echo ""
echo -e "\033[0;32m=== Service Logs (Last 50 lines) ===\033[0m"
journalctl -u genlayer-archive -n 50 --no-pager

if [ -d "./data/node/logs" ]; then
  echo ""
  echo -e "\033[0;32m=== File Logs (Last 20 lines per file) ===\033[0m"
  ls -1 ./data/node/logs/*.log 2>/dev/null | while read logfile; do
    echo -e "\033[1;33m$(basename "$logfile"):\033[0m"
    tail -n 20 "$logfile"
    echo ""
  done
fi
EOF
    chmod +x view-logs.sh

    # Create service management script
    cat > manage-service.sh << 'EOF'
#!/bin/bash
echo -e "\033[0;32m=== GenLayer Service Management ===\033[0m"
echo ""
echo "1) Start service"
echo "2) Stop service"
echo "3) Restart service"
echo "4) View service status"
echo "5) Exit"
echo ""
read -p "Select option (1-5): " choice

case $choice in
    1)
        echo "Starting service..."
        systemctl start genlayer-archive
        sleep 2
        systemctl status genlayer-archive --no-pager
        ;;
    2)
        echo "Stopping service..."
        systemctl stop genlayer-archive
        sleep 2
        systemctl status genlayer-archive --no-pager
        ;;
    3)
        echo "Restarting service..."
        systemctl restart genlayer-archive
        sleep 2
        systemctl status genlayer-archive --no-pager
        ;;
    4)
        systemctl status genlayer-archive --no-pager
        ;;
    5)
        exit 0
        ;;
    *)
        echo -e "\033[0;31mInvalid option\033[0m"
        exit 1
        ;;
esac
EOF
    chmod +x manage-service.sh
    
    # Enable and start service
    print_info "Enabling and starting systemd service..."
    sudo systemctl daemon-reload
    sudo systemctl enable genlayer-archive
    sudo systemctl start genlayer-archive
    sleep 5
    
    # Apply snapshot if requested
    if [ "$with_snapshot" = "true" ]; then
        print_info "Stopping service to apply snapshot..."
        sudo systemctl stop genlayer-archive
        
        print_info "Applying snapshot (this will overwrite the database)..."
        rm -rf ./data/node/genlayer.db
        wget -O genlayer_snapshot.tar.lz4 https://files5.blacknodes.net/genlayer/genlayer-archive.tar.lz4
        mkdir -p ./data/node
        lz4 -cd genlayer_snapshot.tar.lz4 | tar xf - -C ./data/node
        rm -f genlayer_snapshot.tar.lz4
        
        print_info "Starting service with snapshot data..."
        sudo systemctl start genlayer-archive
        sleep 5
        
        print_success "Snapshot applied successfully!"
    fi
    
    # Check if service started successfully
    if systemctl is-active --quiet genlayer-archive; then
        print_success "Service started successfully!"
    else
        print_error "Service failed to start. Check logs with 'journalctl -u genlayer-archive'"
    fi

    echo ""
    print_success "Installation completed!"
    echo ""
    echo -e "${CYAN}=== Installation Summary ===${NC}"
    echo -e "Directory: ${YELLOW}$INSTALL_DIR${NC}"
    echo -e "Node Address: ${YELLOW}$NODE_ADDRESS${NC}"
    echo -e "Service Name: ${YELLOW}genlayer-archive${NC}"
    if [ "$with_snapshot" = "true" ]; then
        echo -e "Snapshot: ${GREEN}Applied${NC}"
    fi
    echo ""
    echo -e "${CYAN}=== Management Commands ===${NC}"
    echo -e "Check status: ${YELLOW}./check-status.sh${NC}"
    echo -e "View logs: ${YELLOW}./view-logs.sh${NC}"
    echo -e "Manage service: ${YELLOW}./manage-service.sh${NC}"
    echo ""
    
    read -p "Press Enter to return to main menu..."
}

# Check Node Status
check_node_status() {
    display_banner
    
    if ! is_node_installed; then
        print_error "GenLayer Archive Node is not installed!"
        echo ""
        read -p "Press Enter to return to main menu..."
        return
    fi

    cd "$INSTALL_DIR/genlayer-node-linux-amd64" 2>/dev/null || {
        print_error "Installation directory not found"
        read -p "Press Enter to return to main menu..."
        return
    }

    # Run the status script
    ./check-status.sh

    echo ""
    echo -e "${CYAN}=== Quick Actions ===${NC}"
    echo "1) View logs"
    echo "2) Manage service"
    echo "3) Return to main menu"
    echo ""
    read -p "Select option (1-3): " action
    
    case $action in
        1)
            ./view-logs.sh
            read -p "Press Enter to continue..."
            check_node_status
            ;;
        2)
            ./manage-service.sh
            read -p "Press Enter to continue..."
            check_node_status
            ;;
        3)
            return
            ;;
        *)
            print_error "Invalid option"
            sleep 1
            check_node_status
            ;;
    esac
}

# Delete Node
delete_node() {
    local silent_mode=$1
    
    if [ "$silent_mode" != "silent" ]; then
        display_banner
    fi
    
    if ! is_node_installed; then
        if [ "$silent_mode" != "silent" ]; then
            print_error "GenLayer Archive Node is not installed!"
            echo ""
            read -p "Press Enter to return to main menu..."
        fi
        return
    fi

    if [ "$silent_mode" != "silent" ]; then
        echo -e "${RED}=== WARNING: Delete GenLayer Archive Node ===${NC}"
        echo ""
        echo "This will permanently delete:"
        echo "• All blockchain data"
        echo "• Node configuration"
        echo "• Account information"
        echo "• Docker containers"
        echo "• Systemd service"
        echo ""
        echo -e "${RED}This cannot be undone!${NC}"
        echo ""
        echo "Type 'DELETE' to confirm:"
        read -p "> " confirmation
        
        if [ "$confirmation" != "DELETE" ]; then
            print_info "Deletion cancelled"
            sleep 2
            return
        fi
    fi

    print_info "Stopping service..."
    sudo systemctl stop genlayer-archive 2>/dev/null || true
    sudo systemctl disable genlayer-archive 2>/dev/null || true
    sudo rm -f /etc/systemd/system/genlayer-archive.service
    sudo systemctl daemon-reload
    print_success "Service removed"
    
    # Kill any running processes
    pkill -f genlayernode 2>/dev/null || true
    pkill -f genvm-modules 2>/dev/null || true

    # Remove Docker containers
    cd "$INSTALL_DIR/genlayer-node-linux-amd64" 2>/dev/null
    if [ -f "docker-compose.yml" ]; then
        docker-compose down > /dev/null 2>&1
        print_success "Docker containers removed"
    fi

    # Delete files
    print_info "Removing all files..."
    rm -rf "$INSTALL_DIR"
    print_success "All files deleted"

    if [ "$silent_mode" != "silent" ]; then
        echo ""
        print_success "GenLayer Archive Node completely removed!"
        echo ""
        read -p "Press Enter to return to main menu..."
    fi
}

# Main menu
main_menu() {
    while true; do
        display_banner
        
        echo -e "${CYAN}=== Main Menu ===${NC}"
        echo ""
        
        if is_node_installed; then
            echo -e "${GREEN}Status: Installed${NC}"
            if systemctl is-active --quiet genlayer-archive; then
                echo -e "${GREEN}Service: Running${NC}"
            else
                echo -e "${YELLOW}Service: Stopped${NC}"
            fi
        else
            echo -e "${RED}Status: Not Installed${NC}"
        fi
        
        echo ""
        echo "1) Install Archive Node"
        echo "2) Install Archive Node with Snapshot"
        echo "3) Check Node Status"
        echo "4) Delete Node"
        echo "5) Exit"
        echo ""
        read -p "Select option (1-5): " choice

        case $choice in
            1)
                install_archive_node false
                ;;
            2)
                install_archive_node true
                ;;
            3)
                check_node_status
                ;;
            4)
                delete_node
                ;;
            5)
                echo ""
                echo "Thank you for using GenLayer Archive Node Setup!" | lolcat
                echo ""
                break
                ;;
            *)
                print_error "Invalid option. Please select 1-5."
                sleep 2
                ;;
        esac
    done
}

# Start the script
main_menu
