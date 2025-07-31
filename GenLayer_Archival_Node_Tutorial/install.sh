#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="$HOME/genlayer-archive-node"

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
    figlet -f slant "GenLayer Manager" | lolcat
    figlet -f digital "by BlackNodes" | lolcat
    echo ""
    echo "========================================================================" | lolcat
    echo ""
}

# Print functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
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

# Install Archive Node
install_archive_node() {
    display_banner
    
    # Check if already installed
    if is_node_installed; then
        print_warn "GenLayer Archive Node is already installed at $INSTALL_DIR"
        read -p "Do you want to reinstall? This will delete existing data (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
        delete_node
    fi

    print_info "Starting GenLayer Archive Node installation..."
    
    # Check system requirements
    print_info "Checking system requirements..."

    # Check OS
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        print_error "This script only supports Linux systems"
        exit 1
    fi

    # Check architecture
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        print_error "Only AMD64 architecture is supported"
        exit 1
    fi

    # Check available RAM
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 15 ]; then
        print_warn "System has less than 16GB RAM. Archive node requires at least 16GB (32GB recommended)"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
    fi

    print_success "System requirements check passed!"

    # Install dependencies
    print_info "Installing dependencies..."
    sudo apt update > /dev/null 2>&1
    sudo apt install -y wget tar curl git screen jq net-tools > /dev/null 2>&1
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
    echo ""
    read -s -p "Enter password for node account: " NODE_PASSWORD
    echo ""
    read -s -p "Confirm password: " NODE_PASSWORD_CONFIRM
    echo ""

    if [ "$NODE_PASSWORD" != "$NODE_PASSWORD_CONFIRM" ]; then
        print_error "Passwords do not match!"
        exit 1
    fi

    # Save password to file (encrypted would be better, but keeping it simple)
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

    # Automatically start the node
print_info "Starting GenLayer Archive Node..."
cd "$INSTALL_DIR/genlayer-node-linux-amd64"

# Create screen session
screen -S genlayer-archive -d -m

# Send the node start command to the screen session
screen -S genlayer-archive -X stuff "./bin/genlayernode run -c $(pwd)/configs/node/config.yaml --password \"$NODE_PASSWORD\"\n"

sleep 3

# Check if screen session was created and node is running
if screen -list | grep -q "genlayer-archive"; then
    print_success "Node started successfully in screen session 'genlayer-archive'"
    echo ""
    echo -e "${CYAN}=== Node Management Commands ===${NC}"
    echo -e "View node output: ${YELLOW}screen -r genlayer-archive${NC}"
    echo -e "Detach from screen: Press ${YELLOW}Ctrl+A${NC}, then ${YELLOW}D${NC}"
    echo -e "Stop node: Attach to screen and press ${YELLOW}Ctrl+C${NC}"
else
    print_error "Failed to start node in screen session"
fi
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

    cd "$INSTALL_DIR/genlayer-node-linux-amd64"

    # Check if screen session exists
    if screen -list | grep -q "genlayer-archive"; then
        echo -e "Node Process: ${GREEN}✓${NC} Running"
    else
        echo -e "Node Process: ${RED}✗${NC} Not running"
    fi

    # Check WebDriver
    if docker ps 2>/dev/null | grep -q selenium; then
        echo -e "WebDriver: ${GREEN}✓${NC} Running"
    else
        echo -e "WebDriver: ${RED}✗${NC} Not running"
    fi

    # Check RPC endpoint
    BLOCK_RESPONSE=$(curl -s -X POST http://localhost:9151 \
      -H "Content-Type: application/json" \
      -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)

    if [ -n "$BLOCK_RESPONSE" ]; then
        BLOCK_HEX=$(echo $BLOCK_RESPONSE | jq -r '.result' 2>/dev/null)
        if [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "null" ]; then
            BLOCK_NUMBER=$(printf "%d" $BLOCK_HEX 2>/dev/null)
            echo -e "RPC Status: ${GREEN}✓${NC} Active (Block: $BLOCK_NUMBER)"
        else
            echo -e "RPC Status: ${RED}✗${NC} Invalid response"
        fi
    else
        echo -e "RPC Status: ${RED}✗${NC} Not responding"
    fi

    # Check health endpoint
    HEALTH_RESPONSE=$(curl -s http://localhost:9153/health 2>/dev/null)
    if [ -n "$HEALTH_RESPONSE" ]; then
        echo -e "Health API: ${GREEN}✓${NC} Responding"
    else
        echo -e "Health API: ${RED}✗${NC} Not responding"
    fi

    # Check if logs exist
    if [ -d "./data/node/logs" ] && [ "$(ls -A ./data/node/logs 2>/dev/null)" ]; then
        echo -e "Logs: ${GREEN}✓${NC} Available"
        
        # Show last error if any
        LAST_ERROR=$(grep -E "ERR|ERROR" ./data/node/logs/*.log 2>/dev/null | tail -1)
        if [ -n "$LAST_ERROR" ]; then
            echo -e "\nLast Error:"
            echo -e "${RED}$LAST_ERROR${NC}"
        fi
    else
        echo -e "Logs: ${YELLOW}⚠${NC} No logs found"
    fi

    echo ""
    echo -e "${CYAN}Quick Commands:${NC}"
    echo "• View node output: screen -r genlayer-archive"
    echo "• Check current block: curl -s -X POST http://localhost:9151 -H \"Content-Type: application/json\" -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' | jq -r '.result' | xargs printf '%d\n'"
    echo "• View logs: tail -f $INSTALL_DIR/genlayer-node-linux-amd64/data/node/logs/*.log"
    
    echo ""
    read -p "Press Enter to return to main menu..."
}

# Delete Node
delete_node() {
    display_banner
    
    if ! is_node_installed; then
        print_error "GenLayer Archive Node is not installed!"
        echo ""
        read -p "Press Enter to return to main menu..."
        return
    fi

    echo -e "${RED}=== WARNING: Delete GenLayer Archive Node ===${NC}"
    echo ""
    echo "This will permanently delete:"
    echo "• All node data and blockchain sync"
    echo "• Node configuration"
    echo "• Account information"
    echo "• Docker containers"
    echo ""
    read -p "Are you sure you want to delete everything? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        print_info "Deletion cancelled"
        read -p "Press Enter to return to main menu..."
        return
    fi

    print_info "Stopping node processes..."
    
    # Kill screen session if exists
    if screen -list | grep -q "genlayer-archive"; then
        screen -S genlayer-archive -X quit
        print_success "Screen session terminated"
    fi

    # Stop and remove Docker containers
    cd "$INSTALL_DIR/genlayer-node-linux-amd64" 2>/dev/null
    if [ -f "docker-compose.yml" ]; then
        docker compose down > /dev/null 2>&1
        print_success "Docker containers removed"
    fi

    # Remove installation directory
    print_info "Removing installation directory..."
    rm -rf "$INSTALL_DIR"
    print_success "All files deleted"

    echo ""
    print_success "GenLayer Archive Node has been completely removed!"
    echo ""
    read -p "Press Enter to return to main menu..."
}

# Main menu
main_menu() {
    while true; do
        display_banner
        
        echo -e "${CYAN}=== Main Menu ===${NC}"
        echo ""
        echo "1) Install Archive Node"
        echo "2) Check Node Status"
        echo "3) Delete Node"
        echo "4) Exit"
        echo ""
        read -p "Select an option (1-4): " choice

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
                echo "Thank you for using BlackNodes GenLayer Manager!" | lolcat
                echo ""
                exit 0
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
