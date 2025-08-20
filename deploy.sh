#!/bin/bash
#
# x-agent Deployment Script
# This script automates the deployment of x-agent as described in the README.md
#

set -e  # Exit immediately if a command exits with a non-zero status

# Text formatting
BOLD="\033[1m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# Banner
echo -e "${BOLD}${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                   x-agent Deployment                      ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# Function to print status messages
print_status() {
    echo -e "${BOLD}${BLUE}[INFO]${RESET} $1"
}

# Function to print success messages
print_success() {
    echo -e "${BOLD}${GREEN}[SUCCESS]${RESET} $1"
}

# Function to print error messages
print_error() {
    echo -e "${BOLD}${RED}[ERROR]${RESET} $1"
}

# Function to print warning messages
print_warning() {
    echo -e "${BOLD}${YELLOW}[WARNING]${RESET} $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check if running as root
is_root() {
    [ "$(id -u)" -eq 0 ]
}

# Function to check if a port is in use
is_port_in_use() {
    if command_exists ss; then
        ss -tuln | grep -q ":$1 "
        return $?
    elif command_exists netstat; then
        netstat -tuln | grep -q ":$1 "
        return $?
    else
        # If neither ss nor netstat is available, assume port is free
        return 1
    fi
}

# Function to check required ports
check_required_ports() {
    local ports=(80 443 8848 3306 6379 9200 9000 9001 10822 1216 1025)
    local ports_in_use=()

    for port in "${ports[@]}"; do
        if is_port_in_use "$port"; then
            ports_in_use+=("$port")
        fi
    done

    if [ ${#ports_in_use[@]} -gt 0 ]; then
        print_warning "The following ports are already in use: ${ports_in_use[*]}"
        print_warning "This may cause conflicts with x-agent services."
        read -p "Do you want to continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "Deployment aborted."
            exit 1
        fi
    fi
}

# Check if script is run with sudo or as root
if ! is_root; then
    print_warning "This script requires elevated privileges to install dependencies and configure services."
    print_warning "Please run this script with sudo or as root."
    exit 1
fi

# Check for required dependencies
print_status "Checking for required dependencies..."

# Check for Docker
if ! command_exists docker; then
    print_status "Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "$SUDO_USER" || true
    print_success "Docker installed successfully."
else
    print_status "Docker is already installed."
fi

# Check for Docker Compose
if ! command_exists docker compose; then
    print_status "Docker Compose not found. Installing Docker Compose..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "$DOCKER_CONFIG/cli-plugins"
    COMPOSE_URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    curl -SL "$COMPOSE_URL" -o "$DOCKER_CONFIG/cli-plugins/docker-compose"
    chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose"
    print_success "Docker Compose installed successfully."
else
    print_status "Docker Compose is already installed."
fi

# Check for unzip
if ! command_exists unzip; then
    print_status "unzip not found. Installing unzip..."
    apt-get update && apt-get install -y unzip
    print_success "unzip installed successfully."
else
    print_status "unzip is already installed."
fi

# Check for curl
if ! command_exists curl; then
    print_status "curl not found. Installing curl..."
    apt-get update && apt-get install -y curl
    print_success "curl installed successfully."
else
    print_status "curl is already installed."
fi

# Check required ports
print_status "Checking if required ports are available..."
check_required_ports

# Create working directory
WORK_DIR="$(pwd)"
print_status "Using working directory: $WORK_DIR"

# Create docker-compose.yml
print_status "Creating docker-compose.yml..."
cat > "$WORK_DIR/docker-compose.yml" << 'EOF'
version: '3.8'
services:
  # ========== 主服务：x-agent ==========
  agent-x:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:agent-x_no_bge_250815_05
    container_name: agent-x
    restart: always
    ports:
      - "80:80"     # 替换为浏览器将要访问的端口，与IP_ADDR参数的端口一致
      - "443:443"	# https
      - "8848:8848" # Nacos
      - "3306:3306" # MySQL
      - "6379:6379" # Redis
      - "9200:9200" # Elasticsearch
      - "9000:9000" # MinIO
      - "9001:9001" # MinIO
    environment:
      - IP_ADDR=127.0.0.1:80 # 替换为浏览器将要访问的 ip 和端口
    volumes:
      - agent-x-data:/u01/isi
      - agent-x-cicd:/app/agent/server

  # ========== 算法服务 ==========
  # 1. 向量模型
  algorithm-vector:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-vector
    restart: always
    ports:
      - "10822:8080"  # 默认端口10822，如果默认端口10822有变动，请修改 mysql 的配置项:use smart_customer_agent; update smart_customer_agent.dense_vector set uri='http://172.17.0.1:10822/analysis' where code = 'local_bge_768';
    volumes:
      - ./code_sdk/Embedding_model/config.yml:/app/config.yml
      - ./code_sdk/Embedding_model/main.py:/app/main.py

  # 2. 工作流代码节点
  algorithm-code-node:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-code-node
    restart: always
    ports:
      - "1216:8080"  #默认端口1216，如果默认端口1216有变动，请修改 nacos 的配置项: workflow.default.codeApi: http://172.17.0.1:1216/execute
    volumes:
      - ./code_sdk/Code_node/main.py:/app/main.py

  # 3. 智能问数（NL2SQL）
  algorithm-nl2sql:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-nl2sql
    restart: always
    ports:
      - "1025:8080"  #默认端口1025，如果默认端口1025有变动，请修改 nacos 的配置项: textToSqlSse: http://172.17.0.1:1025/get_answer_text2sql
    volumes:
      - ./code_sdk/Nl2sql/config.yaml:/app/config.yml
      - ./code_sdk/Nl2sql/main.py:/app/main.py

volumes:
  agent-x-data:
  agent-x-cicd:
EOF
print_success "docker-compose.yml created successfully."

# Extract code_sdk files from Agent_X.zip
print_status "Extracting code_sdk files from Agent_X.zip..."
mkdir -p "$WORK_DIR/code_sdk"

if [ -f "$WORK_DIR/config/Agent_X.zip" ]; then
    unzip -o "$WORK_DIR/config/Agent_X.zip" "Embedding_model/*" -d "$WORK_DIR/code_sdk/"
    unzip -o "$WORK_DIR/config/Agent_X.zip" "Code_node/*" -d "$WORK_DIR/code_sdk/"
    unzip -o "$WORK_DIR/config/Agent_X.zip" "Nl2sql/*" -d "$WORK_DIR/code_sdk/"
    print_success "Code modules extracted successfully."
else
    print_error "Agent_X.zip not found in $WORK_DIR/config/. Please make sure the file exists."
    exit 1
fi

# Set proper permissions for extracted files
print_status "Setting proper permissions for extracted files..."
chmod -R 755 "$WORK_DIR/code_sdk"
print_success "Permissions set successfully."

# Login to Tencent Cloud Container Registry
print_status "Checking Docker registry access..."
if ! docker pull ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2 >/dev/null 2>&1; then
    print_warning "Unable to pull images from Tencent Cloud Container Registry."
    print_warning "You may need to login to the registry."
    read -p "Do you want to login to the Tencent Cloud Container Registry now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker login ccr.ccs.tencentyun.com
    else
        print_warning "Skipping login. Deployment may fail if you don't have access to the registry."
    fi
else
    print_success "Docker registry access confirmed."
fi

# Pull Docker images
print_status "Pulling Docker images (this may take a while)..."
if docker compose pull; then
    print_success "Docker images pulled successfully."
else
    print_error "Failed to pull Docker images. Please check your network connection and registry access."
    exit 1
fi

# Start containers
print_status "Starting containers..."
if docker compose up -d; then
    print_success "Containers started successfully."
else
    print_error "Failed to start containers. Please check the logs for more information."
    exit 1
fi

# Check container status
print_status "Checking container status..."
sleep 10  # Give containers some time to start
if docker compose ps | grep -q "Exit\|exited"; then
    print_error "Some containers have exited. Please check the logs for more information."
    docker compose logs
    exit 1
else
    print_success "All containers are running."
fi

# Get server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
if [ -z "$SERVER_IP" ]; then
    SERVER_IP="127.0.0.1"
fi

# Print success message
echo -e "\n${BOLD}${GREEN}╔═══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║                 x-agent Deployed Successfully              ║${RESET}"
echo -e "${BOLD}${GREEN}╚═══════════════════════════════════════════════════════════╝${RESET}\n"

echo -e "${BOLD}Access Information:${RESET}"
echo -e "  Web UI: ${BOLD}http://$SERVER_IP${RESET} or ${BOLD}http://localhost${RESET}"
echo -e "  MySQL: ${BOLD}$SERVER_IP:3306${RESET}"
echo -e "  Redis: ${BOLD}$SERVER_IP:6379${RESET}"
echo -e "  Elasticsearch: ${BOLD}$SERVER_IP:9200${RESET}"
echo -e "  MinIO: ${BOLD}$SERVER_IP:9000${RESET} (Console: ${BOLD}$SERVER_IP:9001${RESET})"
echo -e "  Nacos: ${BOLD}$SERVER_IP:8848${RESET}"

echo -e "\n${BOLD}Useful Commands:${RESET}"
echo -e "  View container status: ${BOLD}docker compose ps${RESET}"
echo -e "  View logs: ${BOLD}docker compose logs -f [service_name]${RESET}"
echo -e "  Stop containers: ${BOLD}docker compose stop${RESET}"
echo -e "  Start containers: ${BOLD}docker compose start${RESET}"
echo -e "  Remove containers: ${BOLD}docker compose down${RESET}"

echo -e "\n${BOLD}Note:${RESET} If you're accessing the web UI from a different machine,"
echo -e "      you may need to update the IP_ADDR environment variable in docker-compose.yml."

exit 0

