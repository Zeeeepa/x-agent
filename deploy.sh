#!/bin/bash

# ========================================
# 智川X-Agent 一键部署脚本
# 中科闻歌企业智能体开发平台
# ========================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}"
}

# 检查Docker是否安装
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose 未安装，请先安装 Docker Compose"
        exit 1
    fi
    
    print_success "Docker 环境检查通过"
}

# 创建必要的目录和卷
setup_volumes() {
    print_info "创建 Docker 数据卷..."
    
    # 创建数据卷
    docker volume create agent-x-data 2>/dev/null || true
    docker volume create agent-x-cicd 2>/dev/null || true
    
    # 创建配置文件目录
    mkdir -p ./code_sdk/{Embedding_model,Code_node,Nl2sql,MCP,Auto_mcp/mcp_file,URL_analysis,URL_to_img}
    
    print_success "数据卷和目录创建完成"
}

# 下载配置文件
download_configs() {
    print_info "准备配置文件..."
    
    if [ ! -f "Agent_X.zip" ]; then
        print_warning "请确保 Agent_X.zip 配置文件包已上传到当前目录"
        print_warning "配置文件包应包含所有算法服务的配置文件"
        read -p "配置文件是否已准备好？(y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_error "请先准备配置文件包后再运行部署脚本"
            exit 1
        fi
    fi
    
    if [ -f "Agent_X.zip" ]; then
        print_info "解压配置文件包..."
        unzip -o Agent_X.zip -d ./code_sdk/
        print_success "配置文件解压完成"
    fi
}

# 拉取所有镜像
pull_images() {
    print_info "拉取 Docker 镜像..."
    
    local images=(
        "ccr.ccs.tencentyun.com/wenge/agent-x:agent-x_no_bge_250815_05"
        "ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_v2"
        "ccr.ccs.tencentyun.com/wenge/agent-x:algorithm_chrome_v2"
        "ccr.ccs.tencentyun.com/wenge/agent-x:reranker.v1"
        "ccr.ccs.tencentyun.com/wenge/agent-x:contentparse.v4.7"
        "ccr.ccs.tencentyun.com/wenge/agent-x:doc_answer_noes_nosql.v1.2.8-build2503143-encrypted"
    )
    
    for image in "${images[@]}"; do
        print_info "拉取镜像: $image"
        docker pull "$image"
    done
    
    print_success "所有镜像拉取完成"
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
    
    # 启动主服务
    print_info "启动主服务 agent-x..."
    docker-compose up -d agent-x
    
    # 等待主服务启动
    print_info "等待主服务启动完成..."
    sleep 30
    
    # 启动算法服务
    print_info "启动算法服务..."
    docker-compose up -d
    
    print_success "所有服务启动完成"
}

# 等待服务就绪
wait_for_services() {
    print_info "等待服务就绪..."
    
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
    echo -e "   查看服务状态: ${YELLOW}docker-compose ps${NC}"
    echo -e "   查看服务日志: ${YELLOW}docker-compose logs -f [服务名]${NC}"
    echo -e "   重启所有服务: ${YELLOW}docker-compose restart${NC}"
    echo -e "   停止所有服务: ${YELLOW}docker-compose down${NC}"
    echo -e "   更新服务: ${YELLOW}docker-compose pull && docker-compose up -d${NC}"
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
    
    echo -e "${CYAN}服务运行状态:${NC}"
    docker-compose ps
    
    echo ""
    echo -e "${CYAN}容器资源使用情况:${NC}"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
}

# 创建管理脚本
create_management_scripts() {
    print_info "创建管理脚本..."
    
    # 创建启动脚本
    cat > start.sh << 'EOF'
#!/bin/bash
echo "启动智川X-Agent服务..."
docker-compose up -d
echo "服务启动完成！"
docker-compose ps
EOF
    
    # 创建停止脚本
    cat > stop.sh << 'EOF'
#!/bin/bash
echo "停止智川X-Agent服务..."
docker-compose down
echo "服务已停止！"
EOF
    
    # 创建重启脚本
    cat > restart.sh << 'EOF'
#!/bin/bash
echo "重启智川X-Agent服务..."
docker-compose restart
echo "服务重启完成！"
docker-compose ps
EOF
    
    # 创建日志查看脚本
    cat > logs.sh << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "查看所有服务日志..."
    docker-compose logs -f
else
    echo "查看 $1 服务日志..."
    docker-compose logs -f "$1"
fi
EOF
    
    # 创建状态检查脚本
    cat > status.sh << 'EOF'
#!/bin/bash
echo "=== 服务运行状态 ==="
docker-compose ps
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
    show_access_info
    
    print_success "智川X-Agent 部署完成！"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

