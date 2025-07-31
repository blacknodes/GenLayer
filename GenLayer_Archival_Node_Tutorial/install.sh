#!/bin/bash

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Display banner
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}      GenLayer Archive Node Installer        ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""

# Function to stop existing services
stop_services() {
  print_info "Stopping any existing GenLayer services..."
  pkill -f genlayernode 2>/dev/null || true
  pkill -f genvm-modules 2>/dev/null || true
  
  if [ -d "./genlayer-node-linux-amd64" ]; then
    cd ./genlayer-node-linux-amd64
    docker compose down 2>/dev/null || true
    cd ..
  fi
  
  print_success "All existing services stopped"
}

# Function to install archive node
install_node() {
  # Set version
  VERSION="v0.3.6"
  
  print_info "Downloading GenLayer node version ${VERSION}..."
  wget -q --show-progress https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}/genlayer-node-linux-amd64-${VERSION}.tar.gz
  
  print_info "Extracting archive..."
  tar -xzvf genlayer-node-linux-amd64-${VERSION}.tar.gz
  
  print_info "Entering directory..."
  cd genlayer-node-linux-amd64
  
  print_info "Creating config directory..."
  mkdir -p configs/node
  
  print_info "Creating configuration file..."
  cat > configs/node/config.yaml << 'EOL'
rollup:
  zksyncurl: "https://genlayer-testnet.rpc.caldera.xyz/http"
  zksyncwebsocketurl: "wss://genlayer-testnet.rpc.caldera.xyz/ws"
consensus:
  contractmanageraddress: "0x0761ff3847294eb3234f37Bf63fd7F1CA1E840bB"
  contractmainaddress: "0xe30293d600fF9B2C865d91307826F28006A458f4"
  contractdataaddress: "0x2a50afD9d3E0ACC824aC4850d7B4c5561aB5D27a"
  contractidlenessaddress: "0xD1D09c2743DD26d718367Ba249Ee1629BE88CF33"
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
EOL

  print_info "Creating docker-compose.yml file..."
  cat > docker-compose.yml << 'EOL'
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
EOL

  print_info "Running optional precompilation step..."
  ./third_party/genvm/bin/genvm precompile
  
  print_info "Creating node account..."
  echo ""
  echo -e "${YELLOW}Please enter a password for your node account (minimum 8 characters):${NC}"
  read -s NODE_PASSWORD
  echo ""
  
  if [ ${#NODE_PASSWORD} -lt 8 ]; then
    print_error "Password is too short! Please use at least 8 characters."
    exit 1
  fi
  
  # Save password to file for convenience
  echo "$NODE_PASSWORD" > .node_password
  chmod 600 .node_password
  
  ./bin/genlayernode account new -c $(pwd)/configs/node/config.yaml --password "$NODE_PASSWORD"
  
  print_info "Starting WebDriver container..."
  docker compose up -d
  
  print_success "Installation completed!"
}

# Function to start node
start_node() {
  if [ ! -f ".node_password" ]; then
    echo -e "${YELLOW}Please enter your node password:${NC}"
    read -s NODE_PASSWORD
    echo ""
  else
    NODE_PASSWORD=$(cat .node_password)
  fi
  
  print_info "Starting node in a screen session..."
  print_info "A screen session will be created. Inside it, the node will be started."
  print_info "To detach from screen: Press ${YELLOW}Ctrl+A, then D${NC}"
  print_info "To reattach later: Run ${YELLOW}screen -r genlayer${NC}"
  echo ""
  print_info "Press Enter to continue..."
  read
  
  screen -S genlayer ./bin/genlayernode run -c $(pwd)/configs/node/config.yaml --password "$NODE_PASSWORD"
}

# Function to check node status
check_status() {
  echo -e "${GREEN}=== GenLayer Node Status ===${NC}"
  
  # Check if screen session exists
  if screen -list | grep -q genlayer; then
    echo -e "Node Screen: ${GREEN}Running${NC}"
  else
    echo -e "Node Screen: ${RED}Not running${NC}"
  fi
  
  # Check if Docker container is running
  if docker ps | grep -q webdriver; then
    echo -e "WebDriver: ${GREEN}Running${NC}"
  else
    echo -e "WebDriver: ${RED}Not running${NC}"
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
      echo -e "${GREEN}Responding${NC} (Block: $DECIMAL_BLOCK)"
    else
      echo -e "${GREEN}Responding${NC}"
    fi
  else
    echo -e "${RED}Not responding${NC}"
  fi
  
  echo ""
}

# Function to view logs
view_logs() {
  if [ -d "./data/node/logs" ]; then
    echo -e "${GREEN}=== Recent Logs ===${NC}"
    ls -1 ./data/node/logs/*.log 2>/dev/null | while read logfile; do
      echo -e "${YELLOW}$(basename "$logfile"):${NC}"
      tail -n 10 "$logfile"
      echo ""
    done
  else
    print_error "No logs directory found"
  fi
}

# Function to display help menu
show_help() {
  echo -e "${GREEN}=== Available Commands ===${NC}"
  echo "1. install - Install the GenLayer node"
  echo "2. start   - Start the node in a screen session"
  echo "3. status  - Check node status"
  echo "4. logs    - View recent logs"
  echo "5. help    - Show this help menu"
  echo ""
}

# Main execution
if [ -z "$1" ]; then
  # If no arguments provided, run the full installation
  stop_services
  install_node
  echo ""
  echo -e "${GREEN}=== Installation Complete ===${NC}"
  echo "To start your node, run: $0 start"
  echo "To check status: $0 status"
  echo "To view logs: $0 logs"
  echo ""
else
  # Handle different commands
  case "$1" in
    install)
      stop_services
      install_node
      ;;
    start)
      if [ ! -d "./genlayer-node-linux-amd64" ]; then
        cd ./genlayer-node-linux-amd64 2>/dev/null || {
          print_error "GenLayer node not installed. Run '$0 install' first."
          exit 1
        }
      fi
      start_node
      ;;
    status)
      if [ ! -d "./genlayer-node-linux-amd64" ]; then
        cd ./genlayer-node-linux-amd64 2>/dev/null || {
          print_error "GenLayer node not installed. Run '$0 install' first."
          exit 1
        }
      fi
      check_status
      ;;
    logs)
      if [ ! -d "./genlayer-node-linux-amd64" ]; then
        cd ./genlayer-node-linux-amd64 2>/dev/null || {
          print_error "GenLayer node not installed. Run '$0 install' first."
          exit 1
        }
      fi
      view_logs
      ;;
    help)
      show_help
      ;;
    *)
      print_error "Unknown command: $1"
      show_help
      exit 1
      ;;
  esac
fi
