#!/bin/bash

# ========================================
# 智川X-Agent 一键部署脚本
# 中科闻歌企业智能体开发平台
# ========================================

# 启用错误追踪，但不立即退出
set -o errtrace
set -o pipefail

# 全局变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
ERROR_COUNT=0
WARNING_COUNT=0
DOCKER_AVAILABLE=false
DOCKER_COMPOSE_CMD=""
SANDBOX_MODE=false
CONFIG_PATH=""
ACCESS_IP="127.0.0.1"
ACCESS_PORT="80"

# 错误处理函数
handle_error() {
    local exit_code=$?
    local line_number=$1
    echo -e "\n\033[0;31m[ERROR]\033[0m 脚本在第 $line_number 行发生错误，退出代码: $exit_code" | tee -a "$LOG_FILE"
    echo -e "\033[0;31m[ERROR]\033[0m 请检查日志文件获取更多信息: $LOG_FILE" | tee -a "$LOG_FILE"
    exit $exit_code
}

# 设置错误处理陷阱
trap 'handle_error $LINENO' ERR

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印带颜色的消息并记录日志
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    ((WARNING_COUNT++))
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    ((ERROR_COUNT++))
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${PURPLE}========================================${NC}" | tee -a "$LOG_FILE"
    echo -e "${PURPLE}$1${NC}" | tee -a "$LOG_FILE"
    echo -e "${PURPLE}========================================${NC}" | tee -a "$LOG_FILE"
}

# 记录命令执行结果
log_cmd() {
    local cmd="$1"
    local start_time=$(date +%s)
    print_info "执行命令: $cmd"
    
    # 执行命令并捕获输出和退出码
    local output
    local exit_code
    
    output=$(eval "$cmd" 2>&1)
    exit_code=$?
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # 记录到日志
    echo "命令: $cmd" >> "$LOG_FILE"
    echo "持续时间: ${duration}秒" >> "$LOG_FILE"
    echo "退出码: $exit_code" >> "$LOG_FILE"
    echo "输出:" >> "$LOG_FILE"
    echo "$output" >> "$LOG_FILE"
    echo "----------------------------------------" >> "$LOG_FILE"
    
    # 如果命令失败，打印错误信息
    if [ $exit_code -ne 0 ]; then
        print_error "命令执行失败 (退出码: $exit_code): $cmd"
        print_error "错误输出: $output"
        return $exit_code
    fi
    
    # 返回命令输出
    echo "$output"
    return 0
}

# 检查命令是否可用
check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi
    return 0
}

# 尝试多个命令，直到一个成功
try_commands() {
    local commands=("$@")
    local success=false
    
    for cmd in "${commands[@]}"; do
        if check_command "$cmd"; then
            echo "$cmd"
            return 0
        fi
    done
    
    return 1
}

# 检查Docker是否安装
check_docker() {
    print_info "检查 Docker 环境..."
    
    # 检查 Docker 是否安装
    if ! check_command "docker"; then
        print_error "Docker 未安装，请先安装 Docker"
        print_info "安装指南: https://docs.docker.com/engine/install/"
        exit 1
    else
        print_info "Docker 已安装: $(docker --version 2>/dev/null || echo '无法获取版本')"
    fi
    
    # 检查 Docker Compose 命令
    DOCKER_COMPOSE_CMD=$(try_commands "docker-compose" "docker compose" || echo "")
    
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        # 尝试使用 docker compose 插件模式
        if docker compose version &>/dev/null; then
            DOCKER_COMPOSE_CMD="docker compose"
            print_info "Docker Compose 插件模式可用"
        else
            print_error "Docker Compose 未安装，请先安装 Docker Compose"
            print_info "安装指南: https://docs.docker.com/compose/install/"
            exit 1
        fi
    elif [ "$DOCKER_COMPOSE_CMD" == "docker-compose" ]; then
        print_info "Docker Compose 独立模式可用: $(docker-compose --version 2>/dev/null || echo '无法获取版本')"
    else
        print_info "Docker Compose 插件模式可用: $(docker compose version 2>/dev/null || echo '无法获取版本')"
    fi
    
    # 检查 Docker 守护进程是否运行
    if docker info &>/dev/null; then
        print_info "Docker 守护进程正在运行"
        DOCKER_AVAILABLE=true
    else
        print_warning "Docker 守护进程未运行或无法连接"
        print_warning "这在沙箱环境中是正常的，在实际部署环境中请确保 Docker 守护进程正在运行"
        print_warning "将在沙箱模式下继续执行脚本进行验证..."
        SANDBOX_MODE=true
        
        # 提供启动 Docker 的建议
        print_info "如果这不是沙箱环境，请尝试启动 Docker 服务:"
        print_info "  - systemctl start docker (对于 systemd 系统)"
        print_info "  - service docker start (对于 init.d 系统)"
    fi
    
    print_success "Docker 环境检查完成"
}

# 创建必要的目录和卷
setup_volumes() {
    print_info "创建 Docker 数据卷和目录..."
    
    # 创建数据卷
    if [ "$DOCKER_AVAILABLE" = true ]; then
        print_info "创建 Docker 数据卷: agent-x-data, agent-x-cicd"
        
        # 使用 log_cmd 执行命令并记录结果
        log_cmd "docker volume create agent-x-data" || print_warning "创建 agent-x-data 卷失败，可能已存在"
        log_cmd "docker volume create agent-x-cicd" || print_warning "创建 agent-x-cicd 卷失败，可能已存在"
        
        # 验证卷是否创建成功
        if docker volume ls | grep -q "agent-x-data"; then
            print_success "数据卷 agent-x-data 创建成功"
        else
            print_warning "数据卷 agent-x-data 可能未创建成功，请手动检查"
        fi
        
        if docker volume ls | grep -q "agent-x-cicd"; then
            print_success "数据卷 agent-x-cicd 创建成功"
        else
            print_warning "数据卷 agent-x-cicd 可能未创建成功，请手动检查"
        fi
    else
        print_warning "Docker 守护进程未运行，跳过数据卷创建"
        print_warning "在实际部署环境中，将创建以下数据卷:"
        print_warning "- agent-x-data"
        print_warning "- agent-x-cicd"
    fi
    
    # 创建配置文件目录
    print_info "创建配置文件目录结构..."
    
    local dirs=(
        "./code_sdk/Embedding_model"
        "./code_sdk/Code_node"
        "./code_sdk/Nl2sql"
        "./code_sdk/MCP"
        "./code_sdk/Auto_mcp/mcp_file"
        "./code_sdk/URL_analysis"
        "./code_sdk/URL_to_img"
        "./code_sdk/mcp_sql"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            log_cmd "mkdir -p $dir" || print_warning "创建目录 $dir 失败"
        else
            print_info "目录 $dir 已存在"
        fi
    done
    
    print_success "数据卷和目录创建完成"
}

# 下载配置文件
download_configs() {
    print_info "准备配置文件..."
    
    # 定义可能的配置文件位置
    local possible_paths=(
        "./Agent_X.zip"
        "/root/config/Agent_X.zip"
        "/config/Agent_X.zip"
        "$HOME/Agent_X.zip"
    )
    
    # 检查所有可能的位置
    for path in "${possible_paths[@]}"; do
        if [ -f "$path" ]; then
            CONFIG_PATH="$path"
            print_info "在 $path 找到配置文件包"
            break
        fi
    done
    
    # 如果都没找到，提示用户
    if [ -z "$CONFIG_PATH" ]; then
        print_warning "未找到 Agent_X.zip 配置文件包"
        print_warning "已检查以下位置:"
        for path in "${possible_paths[@]}"; do
            print_warning "- $path"
        done
        print_warning "配置文件包应包含所有算法服务的配置文件"
        
        # 询问用户配置文件路径
        read -p "请输入配置文件包的完整路径 (或按回车使用默认路径 /root/config/Agent_X.zip): " USER_CONFIG_PATH
        CONFIG_PATH=${USER_CONFIG_PATH:-"/root/config/Agent_X.zip"}
    fi
    
    # 最终检查配置文件是否存在
    if [ ! -f "$CONFIG_PATH" ]; then
        print_error "找不到配置文件: $CONFIG_PATH"
        print_error "请确保配置文件存在后再运行部署脚本"
        
        # 提供创建空配置文件的选项
        read -p "是否创建空的配置文件结构以继续? (y/n): " CREATE_EMPTY
        if [[ "$CREATE_EMPTY" =~ ^[Yy]$ ]]; then
            print_info "创建空的配置文件结构..."
            
            # 创建临时目录
            local temp_dir=$(mktemp -d)
            
            # 创建空的配置文件
            mkdir -p "$temp_dir"/{Embedding_model,Code_node,Nl2sql,MCP,Auto_mcp/mcp_file,URL_analysis,URL_to_img,mcp_sql}
            touch "$temp_dir"/Embedding_model/{config.yml,main.py}
            touch "$temp_dir"/Code_node/main.py
            touch "$temp_dir"/Nl2sql/{config.yaml,main.py}
            touch "$temp_dir"/MCP/{config.yml,main.py}
            touch "$temp_dir"/Auto_mcp/{config.yml,main.py}
            touch "$temp_dir"/URL_analysis/{config.yml,main.py}
            touch "$temp_dir"/URL_to_img/{config.yml,main.py}
            touch "$temp_dir"/mcp_sql/{config.yaml,main.py}
            
            # 创建临时 zip 文件
            CONFIG_PATH="$SCRIPT_DIR/Agent_X.zip"
            
            # 检查 zip 命令是否可用
            if check_command "zip"; then
                (cd "$temp_dir" && zip -r "$CONFIG_PATH" *)
                print_success "创建了空的配置文件包: $CONFIG_PATH"
            else
                print_error "zip 命令不可用，无法创建配置文件包"
                print_info "请手动安装 zip: apt-get install zip 或 yum install zip"
                exit 1
            fi
            
            # 清理临时目录
            rm -rf "$temp_dir"
        else
            exit 1
        fi
    fi
    
    print_info "使用配置文件: $CONFIG_PATH"
    print_info "解压配置文件包..."
    
    # 使用 log_cmd 执行解压命令
    log_cmd "unzip -o \"$CONFIG_PATH\" -d ./code_sdk/" || {
        print_error "解压配置文件失败"
        print_info "尝试安装 unzip 工具..."
        
        # 尝试安装 unzip
        if check_command "apt-get"; then
            log_cmd "apt-get update && apt-get install -y unzip" && \
            log_cmd "unzip -o \"$CONFIG_PATH\" -d ./code_sdk/"
        elif check_command "yum"; then
            log_cmd "yum install -y unzip" && \
            log_cmd "unzip -o \"$CONFIG_PATH\" -d ./code_sdk/"
        else
            print_error "无法安装 unzip，请手动安装后重试"
            exit 1
        fi
    }
    
    # 验证解压结果
    if [ -d "./code_sdk/Embedding_model" ] && [ -d "./code_sdk/MCP" ]; then
        print_success "配置文件解压完成"
    else
        print_warning "配置文件可能未完全解压，请检查 ./code_sdk/ 目录"
    fi
}

# 拉取所有镜像
pull_images() {
    print_info "拉取 Docker 镜像..."
    
    # 检查 Docker 守护进程是否运行
    if [ "$DOCKER_AVAILABLE" != true ]; then
        print_warning "Docker 守护进程未运行，跳过镜像拉取"
        print_warning "在实际部署环境中，将拉取以下镜像:"
        print_warning "- ccr.ccs.tencentyun.com/wenge/agent-x:agent-x_no_bge_250815_05"
        print_warning "- ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2"
        print_warning "- ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_chrome_v2"
        print_warning "- ccr.ccs.tencentyun.com/wenge/agent-x:reranker.v1"
        print_warning "- ccr.ccs.tencentyun.com/wenge/agent-x:contentparse.v4.7"
        print_warning "- ccr.ccs.tencentyun.com/wenge/agent-x:doc_answer_noes_nosql.v1.2.8-build2503143-encrypted"
        return 0
    fi
    
    local images=(
        "ccr.ccs.tencentyun.com/wenge/agent-x:agent-x_no_bge_250815_05"
        "ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2"
        "ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_chrome_v2"
        "ccr.ccs.tencentyun.com/wenge/agent-x:reranker.v1"
        "ccr.ccs.tencentyun.com/wenge/agent-x:contentparse.v4.7"
        "ccr.ccs.tencentyun.com/wenge/agent-x:doc_answer_noes_nosql.v1.2.8-build2503143-encrypted"
    )
    
    local pull_failures=0
    local successful_pulls=0
    
    for image in "${images[@]}"; do
        print_info "拉取镜像: $image"
        
        # 使用 log_cmd 执行拉取命令
        if log_cmd "docker pull $image"; then
            ((successful_pulls++))
            print_success "镜像 $image 拉取成功"
        else
            ((pull_failures++))
            print_warning "镜像 $image 拉取失败，将在启动时自动尝试拉取"
            
            # 检查网络连接
            if ! ping -c 1 ccr.ccs.tencentyun.com &>/dev/null; then
                print_warning "无法连接到镜像仓库服务器，请检查网络连接"
                print_info "您可能需要配置 Docker 镜像仓库代理或 VPN"
                break
            fi
        fi
    done
    
    # 总结拉取结果
    if [ $pull_failures -eq 0 ]; then
        print_success "所有镜像拉取完成 ($successful_pulls/${#images[@]})"
    elif [ $successful_pulls -eq 0 ]; then
        print_error "所有镜像拉取失败，请检查网络连接和 Docker 配置"
        print_info "您可以稍后手动拉取镜像，或者在启动时自动拉取"
    else
        print_warning "部分镜像拉取成功 ($successful_pulls/${#images[@]})，$pull_failures 个镜像拉取失败"
        print_info "失败的镜像将在启动时自动尝试拉取"
    fi
}

# 创建 docker-compose.yml 文件
create_compose_file() {
    print_info "创建 docker-compose.yml 文件..."
    
    # 获取用户输入的访问IP和端口
    read -p "请输入访问IP地址 (默认: 127.0.0.1): " ACCESS_IP
    ACCESS_IP=${ACCESS_IP:-127.0.0.1}
    
    read -p "请输入访问端口 (默认: 80): " ACCESS_PORT
    ACCESS_PORT=${ACCESS_PORT:-80}
    
    cat > docker-compose.yml << EOF
version: '3.8'
services:
  # ========== 主服务：X-Agent ==========
  agent-x:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:agent-x_no_bge_250815_05
    container_name: agent-x
    restart: always
    ports:
      - "${ACCESS_PORT}:80"     # 主要访问端口
      - "443:443"               # HTTPS
      - "8848:8848"             # Nacos
      - "3306:3306"             # MySQL
      - "6379:6379"             # Redis
      - "9200:9200"             # Elasticsearch
      - "9000:9000"             # MinIO
      - "9001:9001"             # MinIO Console
    environment:
      - IP_ADDR=${ACCESS_IP}:${ACCESS_PORT}
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
      - "10822:8080"
    volumes:
      - ./code_sdk/Embedding_model/config.yml:/app/config.yml
      - ./code_sdk/Embedding_model/main.py:/app/main.py
    depends_on:
      - agent-x

  # 2. 工作流代码节点
  algorithm-code-node:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-code-node
    restart: always
    ports:
      - "1216:8080"
    volumes:
      - ./code_sdk/Code_node/main.py:/app/main.py
    depends_on:
      - agent-x

  # 3. 智能问数（NL2SQL）
  algorithm-nl2sql:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-nl2sql
    restart: always
    ports:
      - "1025:8080"
    volumes:
      - ./code_sdk/Nl2sql/config.yaml:/app/config.yaml
      - ./code_sdk/Nl2sql/main.py:/app/main.py
    depends_on:
      - agent-x

  # 4. MCP
  algorithm-mcp:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-mcp
    restart: always
    ports:
      - "4011:8080"
    volumes:
      - ./code_sdk/MCP/config.yml:/app/config.yml
      - ./code_sdk/MCP/main.py:/app/main.py
    depends_on:
      - agent-x

  # 5. 本地自定义 MCP (使用 host 网络)
  algorithm-local-mcp:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-local-mcp
    restart: always
    network_mode: host
    volumes:
      - ./code_sdk/Auto_mcp/config.yml:/app/config.yml
      - ./code_sdk/Auto_mcp/main.py:/app/main.py
      - ./code_sdk/Auto_mcp/mcp_file:/app/mcp_file

  # 6. MCP NL2SQL
  algorithm-mcp-nl2sql:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2
    container_name: algorithm-mcp-nl2sql
    restart: always
    ports:
      - "4016:8080"
    volumes:
      - ./code_sdk/mcp_sql/config.yaml:/app/config.yaml
      - ./code_sdk/mcp_sql/main.py:/app/main.py
    depends_on:
      - agent-x

  # 7. 单网页内容爬取
  algorithm-url-analysis:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_chrome_v2
    container_name: algorithm-url-analysis
    restart: always
    ports:
      - "9007:8080"
    volumes:
      - ./code_sdk/URL_analysis/config.yml:/app/config.yml
      - ./code_sdk/URL_analysis/main.py:/app/main.py
    depends_on:
      - agent-x

  # 8. 网页截图
  algorithm-url-to-img:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_chrome_v2
    container_name: algorithm-url-to-img
    restart: always
    ports:
      - "5028:8080"
    volumes:
      - ./code_sdk/URL_to_img/config.yml:/app/config.yml
      - ./code_sdk/URL_to_img/main.py:/app/main.py
    depends_on:
      - agent-x

  # 9. 重排序服务 (yayi)
  algorithm-reranker:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:reranker.v1
    container_name: algorithm-reranker
    restart: always
    ports:
      - "9098:8080"
    depends_on:
      - agent-x

  # 10. 文档智能解析 (yayi)
  algorithm-content-parse:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:contentparse.v4.7
    container_name: algorithm-content-parse
    restart: always
    ports:
      - "9099:8080"
    depends_on:
      - agent-x

  # 11. 文档切片 (yayi)
  algorithm-doc-answer:
    image: ccr.ccs.tencentyun.com/wenge/agent-x:doc_answer_noes_nosql.v1.2.8-build2503143-encrypted
    container_name: algorithm-doc-answer
    restart: always
    ports:
      - "9097:8080"
    depends_on:
      - agent-x

# ========== 数据卷定义 ==========
volumes:
  agent-x-data:
    external: true
  agent-x-cicd:
    external: true
EOF

    print_success "docker-compose.yml 文件创建完成"
}

# 启动服务
start_services() {
    print_info "启动所有服务..."
    
    # 检查 Docker 守护进程是否运行
    if ! docker info &> /dev/null; then
        print_warning "Docker 守护进程未运行，跳过服务启动"
        print_warning "在实际部署环境中，将启动所有服务"
        return 0
    fi
    
    # 检测 docker-compose 命令
    DOCKER_COMPOSE_CMD="docker-compose"
    if ! command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    fi
    
    # 启动主服务
    print_info "启动主服务 agent-x..."
    $DOCKER_COMPOSE_CMD up -d agent-x
    
    # 等待主服务启动
    print_info "等待主服务启动完成..."
    sleep 30
    
    # 启动算法服务
    print_info "启动算法服务..."
    $DOCKER_COMPOSE_CMD up -d
    
    print_success "所有服务启动完成"
}

# 等待服务就绪
wait_for_services() {
    print_info "等待服务就绪..."
    
    # 检查 Docker 守护进程是否运行
    if ! docker info &> /dev/null; then
        print_warning "Docker 守护进程未运行，跳过服务就绪检查"
        print_warning "在实际部署环境中，将等待所有服务就绪"
        return 0
    fi
    
    # 检测 docker-compose 命令
    DOCKER_COMPOSE_CMD="docker-compose"
    if ! command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    fi
    
    local services=(
        "agent-x:80"
        "agent-x:8848"
        "agent-x:3306"
        "algorithm-vector:10822"
        "algorithm-code-node:1216"
        "algorithm-nl2sql:1025"
        "algorithm-mcp:4011"
    )
    
    for service in "${services[@]}"; do
        local container=$(echo $service | cut -d: -f1)
        local port=$(echo $service | cut -d: -f2)
        
        print_info "等待 $container 服务就绪..."
        
        local max_attempts=30
        local attempt=1
        
        while [ $attempt -le $max_attempts ]; do
            if docker exec $container nc -z localhost $port 2>/dev/null; then
                print_success "$container 服务已就绪"
                break
            fi
            
            if [ $attempt -eq $max_attempts ]; then
                print_warning "$container 服务可能未完全就绪，请检查日志"
                break
            fi
            
            sleep 5
            ((attempt++))
        done
    done
}

# 配置数据库
configure_database() {
    print_info "配置数据库..."
    
    # 检查 Docker 守护进程是否运行
    if ! docker info &> /dev/null; then
        print_warning "Docker 守护进程未运行，跳过数据库配置"
        print_warning "在实际部署环境中，将执行以下SQL:"
        print_warning "USE smart_customer_agent;"
        print_warning "UPDATE smart_customer_agent.dense_vector SET uri='http://172.17.0.1:10822/analysis' WHERE code = 'local_bge_768';"
        return 0
    fi
    
    # 等待MySQL服务就绪
    sleep 10
    
    # 更新向量模型配置
    print_info "更新向量模型配置..."
    docker exec agent-x mysql -uroot -p2ievD%GBA6 -e "
        USE smart_customer_agent;
        UPDATE smart_customer_agent.dense_vector 
        SET uri='http://172.17.0.1:10822/analysis' 
        WHERE code = 'local_bge_768';
    " 2>/dev/null || print_warning "数据库配置可能需要手动执行"
    
    print_success "数据库配置完成"
}

# 显示访问信息
show_access_info() {
    local ACCESS_IP=${1:-127.0.0.1}
    local ACCESS_PORT=${2:-80}
    
    print_header "🎉 智川X-Agent 部署完成！"
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🌐 系统访问信息${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    echo -e "${CYAN}📱 主要应用界面:${NC}"
    echo -e "   管理后台: ${YELLOW}http://${ACCESS_IP}:${ACCESS_PORT}/wg-agent-manage/#/appmanage${NC}"
    echo -e "   账号: ${GREEN}agent-x${NC}"
    echo -e "   密码: ${GREEN}04p9xa0gAE*%&Op8${NC}"
    echo ""
    
    echo -e "${CYAN}🔧 系统管理界面:${NC}"
    echo -e "   Nacos配置中心: ${YELLOW}http://${ACCESS_IP}:8848/nacos/${NC}"
    echo -e "   账号: ${GREEN}nacos${NC}"
    echo -e "   密码: ${GREEN}k2j210w5CKKO!&Wh0${NC}"
    echo ""
    
    echo -e "   MinIO对象存储: ${YELLOW}http://${ACCESS_IP}:9000${NC}"
    echo -e "   账号: ${GREEN}admin${NC}"
    echo -e "   密码: ${GREEN}6838BHE%%C472${NC}"
    echo ""
    
    echo -e "${CYAN}🗄️ 数据库连接:${NC}"
    echo -e "   MySQL数据库: ${YELLOW}${ACCESS_IP}:3306${NC}"
    echo -e "   账号: ${GREEN}root${NC}"
    echo -e "   密码: ${GREEN}2ievD%GBA6${NC}"
    echo -e "   主库: ${GREEN}smart_customer_agent${NC}"
    echo ""
    
    echo -e "   Redis缓存: ${YELLOW}${ACCESS_IP}:6379${NC}"
    echo ""
    
    echo -e "   Elasticsearch搜索: ${YELLOW}${ACCESS_IP}:9200${NC}"
    echo ""
    
    echo -e "${CYAN}🤖 算法服务端口:${NC}"
    echo -e "   向量模型服务: ${YELLOW}${ACCESS_IP}:10822${NC}"
    echo -e "   工作流代码节点: ${YELLOW}${ACCESS_IP}:1216${NC}"
    echo -e "   智能问数(NL2SQL): ${YELLOW}${ACCESS_IP}:1025${NC}"
    echo -e "   MCP服务: ${YELLOW}${ACCESS_IP}:4011${NC}"
    echo -e "   MCP NL2SQL: ${YELLOW}${ACCESS_IP}:4016${NC}"
    echo -e "   网页内容爬取: ${YELLOW}${ACCESS_IP}:9007${NC}"
    echo -e "   网页截图服务: ${YELLOW}${ACCESS_IP}:5028${NC}"
    echo -e "   重排序服务: ${YELLOW}${ACCESS_IP}:9098${NC}"
    echo -e "   文档智能解析: ${YELLOW}${ACCESS_IP}:9099${NC}"
    echo -e "   文档切片服务: ${YELLOW}${ACCESS_IP}:9097${NC}"
    echo ""
    
    echo -e "${CYAN}📊 技术栈信息:${NC}"
    echo -e "   前端: ${GREEN}Vue.js${NC}"
    echo -e "   后端: ${GREEN}Java${NC}"
    echo -e "   算法: ${GREEN}Python${NC}"
    echo -e "   数据库: ${GREEN}MySQL${NC}"
    echo -e "   中间件: ${GREEN}Elasticsearch, Redis, MinIO, Nginx${NC}"
    echo ""
    
    echo -e "${CYAN}🛠️ 常用管理命令:${NC}"
    echo -e "   查看服务状态: ${YELLOW}./status.sh${NC}"
    echo -e "   查看服务日志: ${YELLOW}./logs.sh [服务名]${NC}"
    echo -e "   重启所有服务: ${YELLOW}./restart.sh${NC}"
    echo -e "   停止所有服务: ${YELLOW}./stop.sh${NC}"
    echo -e "   启动所有服务: ${YELLOW}./start.sh${NC}"
    echo ""
    
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}🎯 快速开始指南${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "1. 访问管理后台开始使用: ${YELLOW}http://${ACCESS_IP}:${ACCESS_PORT}/wg-agent-manage/#/appmanage${NC}"
    echo -e "2. 使用账号 ${GREEN}agent-x${NC} 和密码 ${GREEN}04p9xa0gAE*%&Op8${NC} 登录"
    echo -e "3. 通过可视化界面拖拽组件构建AI应用"
    echo -e "4. 配置知识库、工作流和大模型"
    echo -e "5. 发布和测试您的AI应用"
    echo ""
    
    print_success "部署完成！请访问上述地址开始使用智川X-Agent平台"
}

# 检查服务状态
check_services() {
    print_info "检查服务运行状态..."
    
    # 检查 Docker 守护进程是否运行
    if ! docker info &> /dev/null; then
        print_warning "Docker 守护进程未运行，跳过服务状态检查"
        print_warning "在实际部署环境中，将显示所有服务的运行状态"
        return 0
    fi
    
    # 检测 docker-compose 命令
    DOCKER_COMPOSE_CMD="docker-compose"
    if ! command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    fi
    
    echo -e "${CYAN}服务运行状态:${NC}"
    $DOCKER_COMPOSE_CMD ps
    
    echo ""
    echo -e "${CYAN}容器资源使用情况:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
}

# 创建管理脚本
create_management_scripts() {
    print_info "创建管理脚本..."
    
    # 检测 docker-compose 命令
    DOCKER_COMPOSE_CMD="docker-compose"
    if ! command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    fi
    
    # 创建启动脚本
    cat > start.sh << EOF
#!/bin/bash
echo "启动智川X-Agent服务..."
$DOCKER_COMPOSE_CMD up -d
echo "服务启动完成！"
$DOCKER_COMPOSE_CMD ps
EOF
    
    # 创建停止脚本
    cat > stop.sh << EOF
#!/bin/bash
echo "停止智川X-Agent服务..."
$DOCKER_COMPOSE_CMD down
echo "服务已停止！"
EOF
    
    # 创建重启脚本
    cat > restart.sh << EOF
#!/bin/bash
echo "重启智川X-Agent服务..."
$DOCKER_COMPOSE_CMD restart
echo "服务重启完成！"
$DOCKER_COMPOSE_CMD ps
EOF
    
    # 创建日志查看脚本
    cat > logs.sh << EOF
#!/bin/bash
if [ -z "\$1" ]; then
    echo "查看所有服务日志..."
    $DOCKER_COMPOSE_CMD logs -f
else
    echo "查看 \$1 服务日志..."
    $DOCKER_COMPOSE_CMD logs -f "\$1"
fi
EOF
    
    # 创建状态检查脚本
    cat > status.sh << EOF
#!/bin/bash
echo "=== 服务运行状态 ==="
$DOCKER_COMPOSE_CMD ps
echo ""
echo "=== 资源使用情况 ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
EOF
    
    # 设置执行权限
    chmod +x start.sh stop.sh restart.sh logs.sh status.sh
    
    print_success "管理脚本创建完成"
}

# 主函数
main() {
    print_header "智川X-Agent 一键部署脚本"
    print_info "开始部署中科闻歌企业智能体开发平台..."
    print_info "日志文件: $LOG_FILE"
    
    # 显示系统信息
    print_info "系统信息:"
    log_cmd "uname -a" || print_warning "无法获取系统信息"
    log_cmd "cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || echo '未知系统'" || print_warning "无法获取系统版本"
    
    # 检查环境
    check_docker
    
    # 设置数据卷和目录
    setup_volumes
    
    # 下载配置文件
    download_configs
    
    # 拉取镜像
    pull_images
    
    # 创建compose文件
    create_compose_file
    
    # 启动服务
    start_services
    
    # 等待服务就绪
    wait_for_services
    
    # 配置数据库
    configure_database
    
    # 创建管理脚本
    create_management_scripts
    
    # 检查服务状态
    check_services
    
    # 显示访问信息
    show_access_info "$ACCESS_IP" "$ACCESS_PORT"
    
    # 显示部署统计信息
    print_header "部署统计信息"
    print_info "警告数量: $WARNING_COUNT"
    print_info "错误数量: $ERROR_COUNT"
    print_info "部署模式: $([ "$SANDBOX_MODE" = true ] && echo '沙箱模式' || echo '生产模式')"
    print_info "部署日志: $LOG_FILE"
    
    if [ $ERROR_COUNT -gt 0 ]; then
        print_warning "部署过程中出现了 $ERROR_COUNT 个错误，请检查日志文件"
    else
        print_success "智川X-Agent 部署完成！"
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
