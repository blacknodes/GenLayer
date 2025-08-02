#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== GenLayer Archive Node Setup ===${NC}"

# Setup directory
INSTALL_DIR=$HOME/genlayer-node
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# Download and extract
VERSION="v0.3.6"
echo -e "${YELLOW}Downloading GenLayer node version $VERSION...${NC}"
wget -q --show-progress https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}/genlayer-node-linux-amd64-${VERSION}.tar.gz
tar -xzf genlayer-node-linux-amd64-${VERSION}.tar.gz
cd genlayer-node-linux-amd64

# Create config
echo -e "${YELLOW}Creating configuration...${NC}"
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

# Create Docker Compose file with specific image
echo -e "${YELLOW}Setting up Docker Compose...${NC}"
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  webdriver-container:
    image: yeagerai/genlayer-genvm-webdriver:0.0.3
    ports:
      - "4444:4444"
    restart: unless-stopped
EOF

# Create account
echo -e "${YELLOW}Creating node account...${NC}"
PASSWORD="YOUR_PASSWORD_HERE" # Replace with your desired password (min 8 chars)
echo "$PASSWORD" > .node_password
chmod 600 .node_password
./bin/genlayernode account new -c $(pwd)/configs/node/config.yaml --password "$PASSWORD"

# Run precompilation
echo -e "${YELLOW}Running precompilation...${NC}"
./third_party/genvm/bin/genvm precompile

# Create service file
echo -e "${YELLOW}Creating systemd service...${NC}"
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
ExecStart=$INSTALL_DIR/genlayer-node-linux-amd64/bin/genlayernode run -c $INSTALL_DIR/genlayer-node-linux-amd64/configs/node/config.yaml --password \"$PASSWORD\"

# Restart policy
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF"

# Create helper script for status checking
echo -e "${YELLOW}Creating status checker script...${NC}"
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

# Enable and start service
echo -e "${YELLOW}Enabling and starting service...${NC}"
sudo systemctl daemon-reload
sudo systemctl enable genlayer-archive
sudo systemctl start genlayer-archive

echo -e "${GREEN}GenLayer Archive Node setup complete!${NC}"
echo "To check status: ./check-status.sh"
echo "To view logs: journalctl -u genlayer-archive -f"
