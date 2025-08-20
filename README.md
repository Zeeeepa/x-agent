# 智川X-Agent 企业智能体开发平台

智川X-Agent是中科闻歌推出的一站式企业智能体开发平台，帮助企业零代码快速构建AI应用。

## 🚀 平台特性

- **零代码开发**: 通过可视化拖拽组件快速构建AI应用
- **多模型支持**: 支持雅意、文心一言等多种大模型
- **完整工作流**: 提供知识库管理、工作流编排、应用发布等功能
- **行业适配**: 满足政务、金融、媒体等多行业需求
- **快速部署**: 基于Docker容器化部署，一键启动

## 🏗️ 技术架构

- **前端**: Vue.js
- **后端**: Java
- **算法**: Python
- **数据库**: MySQL
- **中间件**: Elasticsearch, Redis, MinIO, Nginx

## 📦 一键部署

### 前置要求

- Docker >= 20.10
- Docker Compose >= 2.0
- 至少 8GB 内存
- 至少 50GB 磁盘空间

### 快速开始

1. **克隆项目**
```bash
git clone https://github.com/Zeeeepa/x-agent.git
cd x-agent
```

2. **准备配置文件**
```bash
# 确保 Agent_X.zip 配置文件包在当前目录
# 配置文件包包含所有算法服务的配置文件
```

3. **运行部署脚本**
```bash
chmod +x deploy.sh
./deploy.sh
```

4. **访问系统**
- 管理后台: http://127.0.0.1:80/wg-agent-manage/#/appmanage
- 账号: `agent-x`
- 密码: `04p9xa0gAE*%&Op8`

## 🌐 系统访问信息

### 主要应用界面
| 服务 | 地址 | 账号 | 密码 |
|------|------|------|------|
| 管理后台 | http://127.0.0.1:80/wg-agent-manage/#/appmanage | agent-x | 04p9xa0gAE*%&Op8 |

### 系统管理界面
| 服务 | 地址 | 账号 | 密码 |
|------|------|------|------|
| Nacos配置中心 | http://127.0.0.1:8848/nacos/ | nacos | k2j210w5CKKO!&Wh0 |
| MinIO对象存储 | http://127.0.0.1:9000 | admin | 6838BHE%%C472 |

### 数据库连接
| 服务 | 地址 | 账号 | 密码 | 备注 |
|------|------|------|------|------|
| MySQL | 127.0.0.1:3306 | root | 2ievD%GBA6 | 主库: smart_customer_agent |
| Redis | 127.0.0.1:6379 | - | - | 无密码 |
| Elasticsearch | 127.0.0.1:9200 | - | - | 无认证 |

### 算法服务端口
| 服务 | 端口 | 描述 |
|------|------|------|
| 向量模型服务 | 10822 | BGE向量化模型 |
| 工作流代码节点 | 1216 | 代码执行节点 |
| 智能问数(NL2SQL) | 1025 | 自然语言转SQL |
| MCP服务 | 4011 | 模型上下文协议 |
| MCP NL2SQL | 4016 | MCP SQL查询 |
| 网页内容爬取 | 9007 | 单页面内容抓取 |
| 网页截图服务 | 5028 | 网页截图生成 |
| 重排序服务 | 9098 | 搜索结果重排 |
| 文档智能解析 | 9099 | 文档内容解析 |
| 文档切片服务 | 9097 | 文档分块处理 |

## 🛠️ 管理命令

### 服务管理
```bash
# 启动所有服务
./start.sh

# 停止所有服务
./stop.sh

# 重启所有服务
./restart.sh

# 查看服务状态
./status.sh

# 查看服务日志
./logs.sh [服务名]
```

### Docker Compose 命令
```bash
# 查看服务状态
docker-compose ps

# 查看服务日志
docker-compose logs -f [服务名]

# 重启特定服务
docker-compose restart [服务名]

# 停止所有服务
docker-compose down

# 更新服务
docker-compose pull && docker-compose up -d
```

## 🔧 配置说明

### Nacos配置项
部署完成后，需要在Nacos中配置以下关键参数：

```yaml
appframe:
  yayi:
    # 文档智能解析
    contentparsingnewversion:
      uri: http://172.17.0.1:9099/analysis
    # 重排序服务
    rearrange:
      uri: http://172.17.0.1:9098/analysis
    # 文档切片
    knowledgesplit:
      uri: http://172.17.0.1:9097/analysis

# 网页快照
screenshot:
  uploadUrl: http://172.17.0.1:80/smart-agent-api/wos/file/upload
  api: http://172.17.0.1:5028/capture-screenshot

# MCP服务
mcp:
  serviceApi: http://172.17.0.1:4011/service
  queryApi: http://172.17.0.1:4011/query
  buildMcpApi: http://172.17.0.1:4011/deploy_service
  textToSqlSse: http://172.17.0.1:1025/get_answer_text2sql

# 工作流
workflow:
  default:
    codeApi: http://172.17.0.1:1216/execute
    startRewriteModelId: 87026c3464664ad49a8b622ec719fa70
```

### MySQL配置
```sql
-- 更新向量模型配置
USE smart_customer_agent;
UPDATE smart_customer_agent.dense_vector 
SET uri='http://172.17.0.1:10822/analysis' 
WHERE code = 'local_bge_768';
```

## 📋 服务架构

### 主服务容器
- **agent-x**: 主应用服务，包含Web界面、API服务、数据库、缓存等

### 算法服务容器
- **algorithm-vector**: 向量化模型服务
- **algorithm-code-node**: 工作流代码执行节点
- **algorithm-nl2sql**: 自然语言转SQL服务
- **algorithm-mcp**: MCP协议服务
- **algorithm-local-mcp**: 本地MCP服务
- **algorithm-mcp-nl2sql**: MCP SQL查询服务
- **algorithm-url-analysis**: 网页内容分析
- **algorithm-url-to-img**: 网页截图服务
- **algorithm-reranker**: 搜索重排序服务
- **algorithm-content-parse**: 文档解析服务
- **algorithm-doc-answer**: 文档切片服务

## 🎯 快速开始指南

1. **访问管理后台**: http://127.0.0.1:80/wg-agent-manage/#/appmanage
2. **登录系统**: 使用账号 `agent-x` 和密码 `04p9xa0gAE*%&Op8`
3. **创建应用**: 通过可视化界面拖拽组件构建AI应用
4. **配置模型**: 设置知识库、工作流和大模型
5. **发布测试**: 发布和测试您的AI应用

## 🔍 故障排除

### 常见问题

1. **服务启动失败**
   ```bash
   # 检查Docker状态
   docker ps -a
   
   # 查看服务日志
   docker-compose logs [服务名]
   ```

2. **端口冲突**
   ```bash
   # 检查端口占用
   netstat -tlnp | grep [端口号]
   
   # 修改docker-compose.yml中的端口映射
   ```

3. **内存不足**
   ```bash
   # 检查系统资源
   free -h
   df -h
   
   # 清理Docker资源
   docker system prune -a
   ```

4. **配置文件缺失**
   ```bash
   # 确保Agent_X.zip存在
   ls -la Agent_X.zip
   
   # 重新解压配置文件
   unzip -o Agent_X.zip -d ./code_sdk/
   ```

### 日志查看
```bash
# 查看所有服务日志
docker-compose logs -f

# 查看特定服务日志
docker-compose logs -f agent-x
docker-compose logs -f algorithm-vector

# 查看实时日志
docker logs -f [容器名]
```

## 📞 技术支持

如遇到问题，请：
1. 查看服务日志定位问题
2. 检查系统资源是否充足
3. 确认网络连接正常
4. 验证配置文件完整性

## 📄 许可证

本项目遵循相应的开源许可证，具体请查看LICENSE文件。

---

**智川X-Agent** - 让AI应用开发更简单，让企业数字化转型更高效！

