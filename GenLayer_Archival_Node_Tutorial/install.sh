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
INSTALL_DIR="$HOME/genlayer-archive-node"

# Display banner
display_banner() {
    clear
    echo -e "${CYAN}=======================================${NC}"
    echo -e "${GREEN}     GenLayer Archive Node Setup      ${NC}"
    echo -e "${CYAN}=======================================${NC}"
    echo ""
}

# Print functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

# Check if node is installed
is_node_installed() {
    if [ -d "$INSTALL_DIR/genlayer-node-linux-amd64" ] && [ -f "$INSTALL_DIR/genlayer-node-linux-amd64/bin/genlayernode" ]; then
        return 0
    else
        return 1
    fi
}

# Install Archive Node
install_archive_node() {
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

    print_info "Starting GenLayer Archive Node installation..."
    echo ""
    
    # Check system requirements
    print_info "Checking system requirements..."
    
    # Check available RAM
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 15 ]; then
        print_warn "System has less than 16GB RAM. Archive node requires at least 16GB (32GB recommended)"
        echo ""
        echo "Continue anyway?"
        echo "1) Yes"
        echo "2) No"
        read -p "Select option (1-2): " ram_choice
        
        if [ "$ram_choice" != "1" ]; then
            return
        fi
    fi

    print_success "System requirements check passed!"

    # Install dependencies
    print_info "Installing dependencies..."
    sudo apt update > /dev/null 2>&1
    sudo apt install -y wget tar curl git screen jq net-tools bc > /dev/null 2>&1
    print_success "Dependencies installed!"

    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
        print_info "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh > /dev/null 2>&1
        sudo usermod -aG docker $USER
        rm get-docker.sh
        print_warn "Docker installed. You may need to log out and back in for group changes to take effect"
    fi

    # Create working directory
    print_info "Creating installation directory at $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"

    # Download node software
    VERSION="v0.3.6"
    print_info "Downloading GenLayer node version $VERSION..."
    wget -q --show-progress https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}/genlayer-node-linux-amd64-${VERSION}.tar.gz
    tar -xzf genlayer-node-linux-amd64-${VERSION}.tar.gz
    cd genlayer-node-linux-amd64
    print_success "Node software downloaded!"

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

    # Create Docker Compose file
    print_info "Setting up Docker Compose..."
    cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  webdriver:
    image: selenium/standalone-chrome:latest
    ports:
      - "4444:4444"
    environment:
      - SE_NODE_MAX_SESSIONS=5
      - SE_NODE_SESSION_TIMEOUT=86400
    shm_size: 2gb
    restart: unless-stopped
EOF

    # Set up node account
    echo ""
    print_info "Setting up node account..."
    echo ""
    echo -e "${CYAN}=== Create a secure password for your node ===${NC}"
    echo -e "${YELLOW}Password requirements:${NC}"
    echo "• At least 8 characters"
    echo "• Remember this password!"
    echo ""
    
    while true; do
        read -s -p "Enter password: " NODE_PASSWORD
        echo ""
        
        if [ ${#NODE_PASSWORD} -lt 8 ]; then
            print_error "Password must be at least 8 characters!"
            continue
        fi
        
        read -s -p "Confirm password: " NODE_PASSWORD_CONFIRM
        echo ""
        
        if [ "$NODE_PASSWORD" != "$NODE_PASSWORD_CONFIRM" ]; then
            print_error "Passwords don't match! Try again."
            echo ""
        else
            break
        fi
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
    docker compose up -d > /dev/null 2>&1
    sleep 5

    if docker ps | grep -q selenium; then
        print_success "WebDriver started successfully"
    else
        print_error "Failed to start WebDriver"
    fi

    # Create startup script
    print_info "Creating startup script..."
    cat > start-node.sh << EOF
#!/bin/bash
cd "$INSTALL_DIR/genlayer-node-linux-amd64"

# Start Docker container
docker compose up -d

# Get the saved password
NODE_PASSWORD=\$(cat .node_password)

# Kill any existing screen session
screen -S genlayer-archive -X quit > /dev/null 2>&1 || true

# Create a new screen session and run the node in it
screen -S genlayer-archive -d -m bash -c './bin/genlayernode run -c \$(pwd)/configs/node/config.yaml --password "\$NODE_PASSWORD"'

echo "GenLayer node started in screen session 'genlayer-archive'"
EOF
    chmod +x start-node.sh

    # Set up auto-start
    print_info "Setting up auto-start on boot..."
    cat > rc-local-setup.sh << EOF
#!/bin/bash
# Enable rc-local service
cat > /etc/systemd/system/rc-local.service << 'EOFS'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOFS

# Create rc.local file
cat > /etc/rc.local << 'EOFL'
#!/bin/bash
cd $INSTALL_DIR/genlayer-node-linux-amd64
./start-node.sh >> /var/log/genlayer-startup.log 2>&1
exit 0
EOFL

# Make it executable
chmod +x /etc/rc.local

# Enable the service
systemctl enable rc-local.service
EOFS
    chmod +x rc-local-setup.sh
    
    print_info "Running auto-start setup (requires sudo)..."
    sudo bash rc-local-setup.sh

    # Run the node now
    print_info "Starting GenLayer Archive Node..."
    ./start-node.sh
    sleep 5

    echo ""
    print_success "Installation completed!"
    echo ""
    echo -e "${CYAN}=== Installation Summary ===${NC}"
    echo -e "Directory: ${YELLOW}$INSTALL_DIR/genlayer-node-linux-amd64${NC}"
    echo -e "Node Address: ${YELLOW}$NODE_ADDRESS${NC}"
    echo -e "Status: ${GREEN}Running in screen session 'genlayer-archive'${NC}"
    echo ""
    print_info "To view the node logs:"
    echo -e "${YELLOW}screen -r genlayer-archive${NC}"
    echo -e "To detach from screen session: ${YELLOW}Ctrl+A, then D${NC}"
    echo ""
    print_info "To manually start/restart the node:"
    echo -e "${YELLOW}cd $INSTALL_DIR/genlayer-node-linux-amd64${NC}"
    echo -e "${YELLOW}./start-node.sh${NC}"
    echo ""
    read -p "Press Enter to continue to the main menu..."
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

    echo -e "${CYAN}=== GenLayer Archive Node Status ===${NC}"
    echo ""

    cd "$INSTALL_DIR/genlayer-node-linux-amd64" 2>/dev/null || {
        print_error "Installation directory not found"
        read -p "Press Enter to return to main menu..."
        return
    }

    # Check screen session
    if screen -list 2>/dev/null | grep -q "genlayer-archive"; then
        echo -e "Node Process: ${GREEN}✓${NC} Running"
        NODE_RUNNING=true
    else
        echo -e "Node Process: ${RED}✗${NC} Not running"
        NODE_RUNNING=false
    fi

    # Check WebDriver
    if docker ps 2>/dev/null | grep -q selenium; then
        echo -e "WebDriver: ${GREEN}✓${NC} Running"
    else
        echo -e "WebDriver: ${RED}✗${NC} Not running"
    fi

    # Check RPC with timeout
    echo -n "RPC Status: "
    if timeout 5 curl -s -X POST http://localhost:9151 \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /tmp/rpc_check 2>/dev/null; then
        
        if [ -s /tmp/rpc_check ]; then
            BLOCK_HEX=$(cat /tmp/rpc_check | jq -r '.result' 2>/dev/null || echo "null")
            if [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "null" ]; then
                BLOCK_NUMBER=$(echo $BLOCK_HEX | sed 's/0x//' | tr '[:lower:]' '[:upper:]' | xargs -I {} echo "ibase=16; {}" | bc 2>/dev/null || echo "0")
                if [ "$BLOCK_NUMBER" != "0" ]; then
                    echo -e "${GREEN}✓${NC} Active (Block: $BLOCK_NUMBER)"
                else
                    echo -e "${YELLOW}⚠${NC} Invalid block"
                fi
            else
                echo -e "${RED}✗${NC} Invalid response"
            fi
        else
            echo -e "${RED}✗${NC} Empty response"
        fi
        rm -f /tmp/rpc_check
    else
        echo -e "${RED}✗${NC} Not responding"
    fi

    # Check logs
    if [ -d "./data/node/logs" ] && [ "$(ls -A ./data/node/logs 2>/dev/null)" ]; then
        echo -e "Logs: ${GREEN}✓${NC} Available"
    else
        echo -e "Logs: ${YELLOW}⚠${NC} No logs found"
    fi

    echo ""
    echo -e "${CYAN}=== Quick Actions ===${NC}"
    
    if [ "$NODE_RUNNING" = false ]; then
        echo "1) Start node"
        echo "2) View recent logs"
        echo "3) Return to main menu"
        echo ""
        read -p "Select option (1-3): " action
        
        case $action in
            1)
                echo ""
                print_info "Starting node..."
                ./start-node.sh
                sleep 3
                echo ""
                print_success "Node started in screen session 'genlayer-archive'"
                echo ""
                read -p "Press Enter to continue..."
                check_node_status
                ;;
            2)
                if [ -d "./data/node/logs" ]; then
                    echo ""
                    echo -e "${CYAN}=== Recent Logs ===${NC}"
                    tail -n 20 ./data/node/logs/*.log 2>/dev/null || echo "No logs available"
                    echo ""
                    read -p "Press Enter to continue..."
                else
                    print_error "No logs directory found"
                    sleep 2
                fi
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
    else
        echo "1) View node output"
        echo "2) View recent logs"
        echo "3) Check sync progress"
        echo "4) Restart node"
        echo "5) Return to main menu"
        echo ""
        read -p "Select option (1-5): " action

        case $action in
            1)
                if screen -list 2>/dev/null | grep -q "genlayer-archive"; then
                    echo ""
                    print_info "Attaching to screen. Press Ctrl+A, then D to detach."
                    sleep 2
                    screen -r genlayer-archive
                fi
                check_node_status
                ;;
            2)
                if [ -d "./data/node/logs" ]; then
                    echo ""
                    echo -e "${CYAN}=== Recent Logs ===${NC}"
                    tail -n 20 ./data/node/logs/*.log 2>/dev/null || echo "No logs available"
                    echo ""
                    read -p "Press Enter to continue..."
                else
                    print_error "No logs directory found"
                    sleep 2
                fi
                check_node_status
                ;;
            3)
                echo ""
                print_info "Checking sync progress..."
                if timeout 5 curl -s -X POST http://localhost:9151 \
                  -H "Content-Type: application/json" \
                  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /tmp/sync_check 2>/dev/null; then
                    
                    BLOCK_HEX=$(cat /tmp/sync_check | jq -r '.result' 2>/dev/null || echo "null")
                    if [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "null" ]; then
                        BLOCK_NUMBER=$(echo $BLOCK_HEX | sed 's/0x//' | tr '[:lower:]' '[:upper:]' | xargs -I {} echo "ibase=16; {}" | bc 2>/dev/null || echo "0")
                        echo -e "Current block: ${YELLOW}$BLOCK_NUMBER${NC}"
                        echo "Compare with testnet explorer to check sync status"
                    else
                        print_error "Could not get block number"
                    fi
                    rm -f /tmp/sync_check
                else
                    print_error "RPC not responding"
                fi
                echo ""
                read -p "Press Enter to continue..."
                check_node_status
                ;;
            4)
                echo ""
                print_info "Restarting node..."
                if screen -list 2>/dev/null | grep -q "genlayer-archive"; then
                    screen -S genlayer-archive -X quit 2>/dev/null
                fi
                sleep 2
                ./start-node.sh
                sleep 3
                print_success "Node restarted"
                echo ""
                read -p "Press Enter to continue..."
                check_node_status
                ;;
            5)
                return
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                check_node_status
                ;;
        esac
    fi
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

    print_info "Stopping node..."
    
    # Kill screen session
    if screen -list 2>/dev/null | grep -q "genlayer-archive"; then
        screen -S genlayer-archive -X quit 2>/dev/null
        print_success "Screen session terminated"
    fi

    # Remove Docker containers
    cd "$INSTALL_DIR/genlayer-node-linux-amd64" 2>/dev/null
    if [ -f "docker-compose.yml" ]; then
        docker compose down > /dev/null 2>&1
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
            if screen -list 2>/dev/null | grep -q "genlayer-archive"; then
                echo -e "${GREEN}Node: Running${NC}"
            else
                echo -e "${YELLOW}Node: Stopped${NC}"
            fi
        else
            echo -e "${RED}Status: Not Installed${NC}"
        fi
        
        echo ""
        echo "1) Install Archive Node"
        echo "2) Check Node Status"
        echo "3) Delete Node"
        echo "4) Exit"
        echo ""
        read -p "Select option (1-4): " choice

        case $choice in
            1)
                install_archive_node
                ;;
            2)
                check_node_status
                ;;
            3)
                delete_node
                ;;
            4)
                echo ""
                echo "Exiting GenLayer Manager!"
                echo ""
                break
                ;;
            *)
                print_error "Invalid option. Please select 1-4."
                sleep 2
                ;;
        esac
    done
}

# Start the script
main_menu
