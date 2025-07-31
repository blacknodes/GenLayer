## Installation Script (install.sh)

#!/bin/bash

# GenLayer Archive Node Installation Script by BlackNodes
# Usage: source <(curl -s https://raw.githubusercontent.com/YOUR_USERNAME/genlayer-archive-node/main/install.sh)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display the animated text
display_banner() {
    # Install Ruby and RubyGems if not already installed
    if ! command -v gem &> /dev/null; then
        echo "Installing Ruby for animation effects..."
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y ruby-full > /dev/null 2>&1 || { echo "Failed to install Ruby"; exit 1; }
    fi

    # Install figlet if not already installed
    if ! command -v figlet &> /dev/null; then
        echo "Installing figlet..."
        sudo apt-get install -y figlet > /dev/null 2>&1 || { echo "Failed to install figlet"; exit 1; }
    fi

    # Install lolcat using gem if not already installed
    if ! command -v lolcat &> /dev/null; then
        echo "Installing lolcat..."
        sudo gem install lolcat > /dev/null 2>&1 || { echo "Failed to install lolcat"; exit 1; }
    fi

    # Clear screen and display the animated text
    clear
    figlet -f slant "GenLayer Archive Node" | lolcat
    figlet -f digital "by BlackNodes" | lolcat
    echo ""
    echo "========================================================================" | lolcat
    echo ""
    sleep 2
}

# Print colored output
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

# Display banner
display_banner

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
        exit 1
    fi
fi

# Check disk space
AVAILABLE_SPACE=$(df -BG ~ | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt 100 ]; then
    print_warn "Less than 100GB available disk space. Archive nodes require significant storage"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

print_success "System requirements check passed!"
echo ""

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
    print_warn "Docker installed. You may need to log out and back in for group changes to take effect"
    rm get-docker.sh
fi

# Create working directory
INSTALL_DIR="$HOME/genlayer-archive-node"
print_info "Creating installation directory at $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Download node software
VERSION="v0.3.6"
print_info "Downloading GenLayer node version $VERSION..."
wget -q --show-progress https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}/genlayer-node-linux-amd64-${VERSION}.tar.gz
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
print_success "Configuration created!"

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
echo -e "${CYAN}=== IMPORTANT: Create a secure password for your node ===${NC}"
echo "This password will be used to encrypt your node's private key"
echo ""
read -s -p "Enter password for node account: " NODE_PASSWORD
echo ""
read -s -p "Confirm password: " NODE_PASSWORD_CONFIRM
echo ""

if [ "$NODE_PASSWORD" != "$NODE_PASSWORD_CONFIRM" ]; then
    print_error "Passwords do not match!"
    exit 1
fi

# Create account
./bin/genlayernode account new -c $(pwd)/configs/node/config.yaml --password "$NODE_PASSWORD" > account_info.txt 2>&1
NODE_ADDRESS=$(grep "New address:" account_info.txt | awk '{print $3}')
print_success "Node account created: $NODE_ADDRESS"
echo -e "${YELLOW}Account details saved to: $INSTALL_DIR/genlayer-node-linux-amd64/account_info.txt${NC}"

# Start WebDriver
print_info "Starting WebDriver container..."
docker compose up -d > /dev/null 2>&1

# Wait for WebDriver to start
sleep 5

# Verify WebDriver is running
if docker ps | grep -q selenium; then
    print_success "WebDriver started successfully"
else
    print_error "Failed to start WebDriver"
    exit 1
fi

# Create start script
print_info "Creating helper scripts..."
cat > start-node.sh << EOF
#!/bin/bash
cd $INSTALL_DIR/genlayer-node-linux-amd64

# Check if WebDriver is running
if ! docker ps | grep -q selenium; then
    echo "Starting WebDriver..."
    docker compose up -d
    sleep 5
fi

# Optional: Set LLM API key if you have one
# export HEURISTKEY="your-api-key-here"

# Check if node is already running
if screen -list | grep -q "genlayer-archive"; then
    echo "Node is already running in screen session 'genlayer-archive'"
    echo "Use 'screen -r genlayer-archive' to attach"
    exit 0
fi

# Start node in screen
screen -dmS genlayer-archive ./bin/genlayernode run -c \$(pwd)/configs/node/config.yaml --password "$NODE_PASSWORD"

echo "GenLayer Archive Node started in screen session 'genlayer-archive'"
echo "Use 'screen -r genlayer-archive' to attach to the session"
echo "Use './monitor-node.sh' to check node status"
EOF

chmod +x start-node.sh

# Create monitoring script
cat > monitor-node.sh << 'EOF'
#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}=== GenLayer Archive Node Monitor ===${NC}"
echo ""

# Check if node is running
if screen -list | grep -q "genlayer-archive"; then
    echo -e "${GREEN}✓${NC} Node is running in screen session"
else
    echo -e "${RED}✗${NC} Node is not running"
fi

# Check WebDriver
if docker ps | grep -q selenium; then
    echo -e "${GREEN}✓${NC} WebDriver is running"
else
    echo -e "${RED}✗${NC} WebDriver is not running"
fi

# Check RPC endpoint
echo ""
echo "Checking RPC endpoint..."
BLOCK_RESPONSE=$(curl -s -X POST http://localhost:9151 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' 2>/dev/null)

if [ -n "$BLOCK_RESPONSE" ]; then
    BLOCK_HEX=$(echo $BLOCK_RESPONSE | jq -r '.result' 2>/dev/null)
    if [ -n "$BLOCK_HEX" ] && [ "$BLOCK_HEX" != "null" ]; then
        BLOCK_NUMBER=$(printf "%d" $BLOCK_HEX 2>/dev/null)
        echo -e "${GREEN}✓${NC} RPC is responding"
        echo -e "  Current block: ${YELLOW}$BLOCK_NUMBER${NC}"
    else
        echo -e "${RED}✗${NC} RPC returned invalid response"
    fi
else
    echo -e "${RED}✗${NC} RPC is not responding"
fi

# Check health endpoint
echo ""
echo "Health Status:"
HEALTH_RESPONSE=$(curl -s http://localhost:9153/health 2>/dev/null)
if [ -n "$HEALTH_RESPONSE" ]; then
    echo "$HEALTH_RESPONSE" | jq . 2>/dev/null || echo -e "${RED}✗${NC} Invalid health response"
else
    echo -e "${RED}✗${NC} Health endpoint not responding"
fi

# Check disk usage
echo ""
echo "Disk Usage:"
df -h | grep -E "Filesystem|$HOME" | awk '{printf "%-20s %s/%s (%s)\n", $6, $3, $2, $5}'

# Check memory usage
echo ""
echo "Memory Usage:"
free -h | grep -E "Mem:|Swap:" | awk '{printf "%-10s Total: %s Used: %s Free: %s\n", $1, $2, $3, $4}'

# Show recent logs
echo ""
echo -e "${BLUE}Recent Log Entries:${NC}"
if [ -d "./data/node/logs" ]; then
    tail -n 5 ./data/node/logs/*.log 2>/dev/null | grep -E "INF|WRN|ERR" || echo "No recent logs found"
else
    echo "Log directory not found"
fi
EOF

chmod +x monitor-node.sh

# Create stop script
cat > stop-node.sh << 'EOF'
#!/bin/bash

echo "Stopping GenLayer Archive Node..."

# Kill the screen session
if screen -list | grep -q "genlayer-archive"; then
    screen -S genlayer-archive -X quit
    echo "✓ Node stopped"
else
    echo "✗ Node was not running"
fi

# Optionally stop WebDriver
read -p "Stop WebDriver container? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker compose down
    echo "✓ WebDriver stopped"
fi
EOF

chmod +x stop-node.sh

# Create logs viewing script
cat > view-logs.sh << 'EOF'
#!/bin/bash

LOG_DIR="./data/node/logs"

if [ ! -d "$LOG_DIR" ]; then
    echo "Log directory not found at $LOG_DIR"
    exit 1
fi

echo "GenLayer Archive Node Logs"
echo "=========================="
echo ""
echo "1) View latest logs (tail -f)"
echo "2) View error logs only"
echo "3) View warning logs only"
echo "4) Search logs"
echo "5) Exit"
echo ""
read -p "Select option: " option

case $option in
    1)
        tail -f $LOG_DIR/*.log
        ;;
    2)
        grep -E "ERR|ERROR" $LOG_DIR/*.log | tail -50
        ;;
    3)
        grep -E "WRN|WARN" $LOG_DIR/*.log | tail -50
        ;;
    4)
        read -p "Enter search term: " search_term
        grep -i "$search_term" $LOG_DIR/*.log | tail -50
        ;;
    5)
        exit 0
        ;;
    *)
        echo "Invalid option"
        ;;
esac
EOF

chmod +x view-logs.sh

# Summary
echo ""
echo "" | lolcat
figlet -f small "Installation Complete!" | lolcat
echo "" | lolcat
echo "========================================================================" | lolcat
echo ""
print_success "GenLayer Archive Node installation completed!"
echo ""
echo -e "${CYAN}=== Installation Details ===${NC}"
echo -e "${BLUE}Installation directory:${NC} $INSTALL_DIR"
echo -e "${BLUE}Node address:${NC} $NODE_ADDRESS"
echo -e "${BLUE}RPC endpoint:${NC} http://localhost:9151"
echo -e "${BLUE}Health endpoint:${NC} http://localhost:9153/health"
echo -e "${BLUE}Metrics endpoint:${NC} http://localhost:9153/metrics"
echo ""
echo -e "${CYAN}=== Available Commands ===${NC}"
echo -e "${GREEN}Start node:${NC} ./start-node.sh"
echo -e "${GREEN}Monitor node:${NC} ./monitor-node.sh"
echo -e "${GREEN}View logs:${NC} ./view-logs.sh"
echo -e "${GREEN}Stop node:${NC} ./stop-node.sh"
echo -e "${GREEN}Attach to node:${NC} screen -r genlayer-archive"
echo ""
echo -e "${CYAN}=== Useful Monitoring Commands ===${NC}"
echo ""
echo "# Check current block number:"
echo "curl -X POST http://localhost:9151 -H \"Content-Type: application/json\" -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}' | jq -r '.result' | xargs printf '%d\n'"
echo ""
echo "# Check node health:"
echo "curl http://localhost:9153/health | jq ."
echo ""
echo "# View real-time logs:"
echo "tail -f $INSTALL_DIR/genlayer-node-linux-amd64/data/node/logs/*.log"
echo ""
echo "# Check sync progress (compare with testnet explorer):"
echo "watch -n 5 'curl -s -X POST http://localhost:9151 -H \"Content-Type: application/json\" -d \"{\\\"jsonrpc\\\":\\\"2.0\\\",\\\"method\\\":\\\"eth_blockNumber\\\",\\\"params\\\":[],\\\"id\\\":1}\" | jq -r \".result\" | xargs printf \"Current Block: %d\n\"'"
echo ""
echo "# Monitor resource usage:"
echo "htop"
echo ""
echo "# Check disk usage:"
echo "df -h | grep -E \"Filesystem|$HOME\""
echo ""
echo "# View network connections:"
echo "sudo netstat -tlnp | grep -E '9151|9153|4444'"
echo ""
echo -e "${YELLOW}=== IMPORTANT ===${NC}"
echo -e "${RED}Save your password in a secure location!${NC}"
echo -e "${YELLOW}Account info saved at:${NC} $INSTALL_DIR/genlayer-node-linux-amd64/account_info.txt"
echo ""

# Ask if user wants to start the node now
echo ""
read -p "$(echo -e ${GREEN}Start the archive node now? ${NC})(y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cd $INSTALL_DIR/genlayer-node-linux-amd64
    ./start-node.sh
    sleep 5
    echo ""
    ./monitor-node.sh
    echo ""
    echo -e "${GREEN}Node is running!${NC} Use ${CYAN}screen -r genlayer-archive${NC} to view the node output"
fi

echo ""
echo "========================================================================" | lolcat
echo "Thank you for using BlackNodes GenLayer Archive Node installer!" | lolcat
echo "========================================================================" | lolcat
