# GenLayer Archive Node Setup Guide

This guide provides instructions for setting up a GenLayer Archive Node.


<img width="722" height="280" alt="image" src="https://github.com/user-attachments/assets/6a3570ad-313f-4f10-9a5d-1b4ecf14ecd0" />



## Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+ (64-bit)
- **RAM**: 16 GB minimum (32 GB recommended)
- **CPU**: 8 cores/16 threads minimum
- **Storage**: 256 GB+ SSD
- **Network**: 100 Mbps minimum
- **Architecture**: AMD64 only

### Required Ports
- `9151` - JSON-RPC endpoint
- `9153` - Metrics endpoint  
- `4444` - WebDriver (Selenium)

## Quick Install

Run this command for automated installation:

```bash
bash <(curl -s https://raw.githubusercontent.com/blacknodes/GenLayer/refs/heads/main/GenLayer_Archival_Node_Tutorial/install.sh)
```

## Manual Installation

### Step 1: Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y wget tar curl git screen jq bc

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo apt install -y docker-compose
```

### Step 2: Download Node Software

```bash
# Create installation directory
mkdir -p ~/genlayer-node
cd ~/genlayer-node

# Download and extract GenLayer node
VERSION="v0.3.6"
wget https://storage.googleapis.com/gh-af/genlayer-node/bin/amd64/${VERSION}/genlayer-node-linux-amd64-${VERSION}.tar.gz
tar -xzvf genlayer-node-linux-amd64-${VERSION}.tar.gz
cd genlayer-node-linux-amd64
```

### Step 3: Configure the Node

```bash
# Create config directory
mkdir -p configs/node

# Create config.yaml file
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
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  webdriver-container:
    image: yeagerai/genlayer-genvm-webdriver:0.0.3
    ports:
      - "4444:4444"
    restart: unless-stopped
EOF
```

### Step 4: Create Node Account and Run Precompilation

```bash
# Run precompilation (optional but recommended)
./third_party/genvm/bin/genvm precompile

# Create node account - replace YOUR_PASSWORD with a secure password (min 8 chars)
read -s -p "Enter password for node account: " NODE_PASSWORD
echo "$NODE_PASSWORD" > .node_password
chmod 600 .node_password
./bin/genlayernode account new -c $(pwd)/configs/node/config.yaml --password "$NODE_PASSWORD"
```

### Step 5: Create Systemd Service

```bash
# Create systemd service file
sudo bash -c "cat > /etc/systemd/system/genlayer-archive.service << EOF
[Unit]
Description=GenLayer Archive Node
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$HOME/genlayer-node/genlayer-node-linux-amd64
Environment=\"HEURISTKEY=dummy-key\"
Environment=\"COMPUT3KEY=dummy-key\"
Environment=\"IOINTELLIGENCE_API_KEY=dummy-key\"

# First ensure Docker container is running
ExecStartPre=/usr/bin/docker-compose up -d

# Then start the node
ExecStart=$HOME/genlayer-node/genlayer-node-linux-amd64/bin/genlayernode run -c $HOME/genlayer-node/genlayer-node-linux-amd64/configs/node/config.yaml --password \"$NODE_PASSWORD\"

# Restart policy
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF"

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable genlayer-archive
sudo systemctl start genlayer-archive
```

### Step 6: Create Helper Scripts

```bash
# Create status checker script
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
```

## Management Commands

### Check Status
```bash
cd ~/genlayer-node/genlayer-node-linux-amd64
./check-status.sh
```

### View Logs
```bash
# View service logs
journalctl -u genlayer-archive -f

# View file logs
tail -f ~/genlayer-node/genlayer-node-linux-amd64/data/node/logs/*.log
```

### Manage Service
```bash
# Start service
sudo systemctl start genlayer-archive

# Stop service
sudo systemctl stop genlayer-archive

# Restart service
sudo systemctl restart genlayer-archive

# Check service status
sudo systemctl status genlayer-archive
```

## RPC Examples

Query the current block number:
```bash
curl -X POST http://localhost:9151 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

Get block by number:
```bash
curl -X POST http://localhost:9151 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_getBlockByNumber","params":["latest", true],"id":1}'
```

## Troubleshooting

### Node fails to start
Check if the Docker WebDriver container is running:
```bash
docker ps | grep webdriver
```

If not running, start it:
```bash
cd ~/genlayer-node/genlayer-node-linux-amd64
docker-compose up -d
```

### LLM module errors
If you see errors related to the LLM module, ensure all environment variables are set:
```bash
export HEURISTKEY="dummy-key"
export COMPUT3KEY="dummy-key"
export IOINTELLIGENCE_API_KEY="dummy-key"
```

### Check logs for errors
```bash
journalctl -u genlayer-archive -n 100
```

## License

[MIT](LICENSE)

## Disclaimer

This is unofficial community-provided documentation. Please refer to the official GenLayer documentation for the most up-to-date information.
