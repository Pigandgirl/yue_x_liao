# Yue Liao - 隐私文件传输与聊天系统

<div align="center">

![Yue Liao Logo](https://img.shields.io/badge/Yue_Liao-Privacy_First-6366F1?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter)
![Go](https://img.shields.io/badge/Go-1.21-00ADD8?style=for-the-badge&logo=go)
![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker)

**一个注重隐私的即时通讯与文件传输平台**

[特性](#特性) • [架构](#架构) • [快速开始](#快速开始) • [技术栈](#技术栈) • [项目结构](#项目结构)

</div>

---

## 🎯 特性

- **端到端加密** - 所有消息和文件均采用 AES-256 加密
- **私有化部署** - 支持 Docker 一键部署，完全掌控数据
- **实时通讯** - 基于 WebSocket 的即时消息推送
- **大文件传输** - 支持加密分块上传，最高达 100MB
- **跨平台支持** - iOS、Android 双平台支持
- **现代化 UI** - Material Design 3 设计语言

## 🏗 架构

```
┌─────────────────────────────────────────────────────────────┐
│                        客户端层                               │
│  ┌─────────────────┐         ┌─────────────────┐          │
│  │  Flutter App    │         │   Flutter App    │          │
│  │    (iOS)        │         │   (Android)      │          │
│  └────────┬────────┘         └────────┬────────┘          │
└───────────┼───────────────────────────┼───────────────────┘
            │                           │
            └─────────────┬─────────────┘
                          │
            ┌─────────────▼─────────────┐
            │       Nginx Gateway       │
            │    (API Gateway & SSL)    │
            └─────────────┬─────────────┘
                          │
┌─────────────────────────┼─────────────────────────────────┐
│                    服务层                                     │
│  ┌─────────────┐  ┌────▼────┐  ┌─────────────┐            │
│  │  WebSocket  │  │   Go    │  │   File      │            │
│  │   Server   │◄─┤   API   │─►│  Service    │            │
│  └─────────────┘  └────┬────┘  └──────┬──────┘            │
└────────────────────────┼─────────────┼────────────────────┘
                         │             │
┌────────────────────────┼─────────────┼────────────────────┐
│                    数据层                                  │
│  ┌─────────────┐  ┌────▼────┐  ┌────▼────┐               │
│  │   Redis    │  │ Postgres │  │  MinIO  │               │
│  │  Session   │  │   DB    │  │  Files  │               │
│  └─────────────┘  └─────────┘  └─────────┘               │
└──────────────────────────────────────────────────────────┘
```

## 🚀 快速开始

### 前置要求

- Docker & Docker Compose
- Go 1.21+
- Flutter 3.x (仅客户端开发需要)

### 1. 克隆项目

```bash
git clone https://github.com/pigandgirl/yue_liao.git
cd yue_liao
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件，修改密码和密钥
```

### 3. 启动服务

```bash
docker-compose up -d
```

### 4. 验证服务

```bash
# 检查服务状态
docker-compose ps

# 查看日志
docker-compose logs -f api
```

访问以下地址确认服务运行正常：
- API 健康检查: http://localhost:8080/health
- MinIO 控制台: http://localhost:9001

## 💻 开发

### 后端开发

```bash
cd backend/services/api

# 安装依赖
go mod download

# 运行服务
go run main.go
```

### 前端开发

```bash
cd frontend/yue_liao_app

# 安装依赖
flutter pub get

# 运行应用
flutter run
```

## 🛠 技术栈

### 后端

| 技术 | 版本 | 用途 |
|------|------|------|
| Go | 1.21 | API 服务 |
| Fiber | v2.52 | Web 框架 |
| PostgreSQL | 15 | 主数据库 |
| Redis | 7 | 会话缓存 |
| MinIO | Latest | S3 兼容存储 |
| Nginx | Alpine | API 网关 |

### 前端

| 技术 | 版本 | 用途 |
|------|------|------|
| Flutter | 3.x | 跨平台框架 |
| Provider | 6.1 | 状态管理 |
| web_socket_channel | 2.4 | WebSocket |
| crypto | 3.0 | 加密支持 |
| flutter_secure_storage | 9.0 | 安全存储 |

## 📁 项目结构

```
yue_liao/
├── docker-compose.yml          # Docker 编排配置
├── .env.example                # 环境变量模板
├── README.md                   # 项目文档
│
├── backend/                    # 后端服务
│   └── services/
│       └── api/               # Go API 服务
│           ├── main.go        # 应用入口
│           ├── Dockerfile     # Docker 镜像
│           └── go.mod         # Go 依赖
│
├── gateway/                    # 网关配置
│   └── nginx/
│       ├── nginx.conf         # 主配置
│       └── conf.d/            # 路由配置
│
└── frontend/                   # 移动端应用
    └── yue_liao_app/          # Flutter 项目
        ├── lib/
        │   ├── core/          # 核心模块
        │   │   ├── config/    # 配置
        │   │   ├── services/  # 服务（加密、WebSocket）
        │   │   └── theme/     # 主题
        │   └── features/      # 功能模块
        │       ├── auth/      # 认证
        │       ├── chat/      # 聊天
        │       └── file/      # 文件传输
        └── pubspec.yaml      # 依赖配置
```

## 🔐 安全

- 所有敏感配置通过环境变量管理
- 密码使用 SHA-256 哈希存储
- 文件使用 AES-256-GCM 加密
- JWT Token 认证
- HTTPS 强制（生产环境）

## 📄 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 创建 Pull Request

---

<div align="center">

**Made with ❤️ by [pigandgirl](https://github.com/pigandgirl)**

</div>
