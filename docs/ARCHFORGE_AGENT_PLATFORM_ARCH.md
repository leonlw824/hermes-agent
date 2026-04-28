# ArchForge 企业级智能体平台 — 系统架构设计方案

> **文档版本**: v1.0  
> **架构师**: ArchForge | Nous Research  
> **日期**: 2026-04-28  
> **工程纪律**: Simplicity First · Surgical Changes · Think Before Coding

---

## 目录

1. [总体架构概览](#1-总体架构概览)
2. [技术选型方案](#2-技术选型方案)
3. [核心模块设计](#3-核心模块设计)
4. [数据库核心表设计](#4-数据库核心表设计)
5. [API 设计思路](#5-api-设计思路)
6. [桌面应用 vs 沙箱方案 — 架构决策](#6-桌面应用-vs-沙箱方案--架构决策)
7. [扩展性与安全性方案](#7-扩展性与安全性方案)

---

## 1. 总体架构概览

### 1.1 分层架构图 (文字描述)

```
┌─────────────────────────────────────────────────────────────────────┐
│                       客户端层 (Client Layer)                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────────┐  │
│  │ Web 管理 │  │ Web 对话 │  │ API 调用 │  │ 桌面 Agent 运行时 │  │
│  │  控制台  │  │  界面    │  │ (SDK)    │  │ (Electron/Go)     │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────────┬──────────┘  │
└───────┼──────────────┼─────────────┼─────────────────┼─────────────┘
        │              │             │                 │
┌───────┼──────────────┼─────────────┼─────────────────┼─────────────┐
│       ▼              ▼             ▼                 ▼             │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    API 网关层 (Gateway)                       │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │  │
│  │  │ Nginx/OpenResty│ │ 限流/熔断    │  │ API Key 认证     │  │  │
│  │  │ 反向代理      │  │ (Sentinel)   │  │ (JWT + HMAC)     │  │  │
│  │  └──────────────┘  └──────────────┘  └──────────────────┘  │  │
│  └──────────────────────────┬───────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼───────────────────────────────────┐  │
│  │                   业务服务层 (Service)                         │  │
│  │                                                               │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐  │  │
│  │  │ 公司管理  │ │ 团队管理  │ │ Agent   │ │ 知识库服务     │  │  │
│  │  │ Service  │ │ Service  │ │ Service  │ │ (RAG Pipeline) │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └────────────────┘  │  │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────┐  │  │
│  │  │ 权限服务  │ │ 模型配置  │ │ 统计服务  │ │ 审核发布服务   │  │  │
│  │  │ (AuthZ)  │ │ (Model   │ │ (Analytics)│ │ (Workflow)    │  │  │
│  │  │          │ │  Hub)    │ │           │ │                │  │  │
│  │  └──────────┘ └──────────┘ └──────────┘ └────────────────┘  │  │
│  └──────────────────────────┬───────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼───────────────────────────────────┐  │
│  │                    AI 推理层 (Inference)                       │  │
│  │  ┌────────────┐ ┌────────────┐ ┌──────────┐ ┌────────────┐  │  │
│  │  │ LLM 网关   │ │ 模型路由   │ │ 嵌入服务 │ │ 函数调用   │  │  │
│  │  │ (统一接口) │ │ (多Provider)│ │ (Embed)  │ │ (Tool Use) │  │  │
│  │  └────────────┘ └────────────┘ └──────────┘ └────────────┘  │  │
│  └──────────────────────────┬───────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼───────────────────────────────────┐  │
│  │              基础设施层 / 沙箱执行层 (Sandbox)                  │  │
│  │  ┌──────────────┐ ┌──────────────┐ ┌─────────────────────┐  │  │
│  │  │ gVisor/Firecracker│ Docker     │ │ WebAssembly (WASI) │  │  │
│  │  │ 微VM沙箱     │ │ 容器沙箱    │ │ 轻量沙箱            │  │  │
│  │  └──────────────┘ └──────────────┘ └─────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                             │                                       │
│  ┌──────────────────────────▼───────────────────────────────────┐  │
│  │                  数据/持久化层 (Data)                           │  │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌──────────┐  │  │
│  │  │Postgres│ │ Redis  │ │  MinIO │ │  ES/   │ │ 消息队列  │  │  │
│  │  │(元数据) │ │(缓存/  │ │(文档/  │ │Mlivus  │ │ (Kafka/  │  │  │
│  │  │        │ │ Session)│ │ 知识库)│ │(向量)  │ │  NSQ)    │  │  │
│  │  └────────┘ └────────┘ └────────┘ └────────┘ └──────────┘  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.2 架构设计原则

| 原则 | 说明 |
|------|------|
| **Simplicity First** | 不做过度抽象，12个以内独立服务，避免微服务爆炸 |
| **Surgical Changes** | 模块间通过明确合约(Protobuf/OpenAPI)解耦，单模块变更不影响全局 |
| **Multi-Tenant by Design** | 公司级租户隔离，数据级+存储级双层隔离 |
| **Stateless Horizontally** | 业务服务无状态，Session 外置到 Redis，可任意扩缩 |
| **Fail-Fast & Observable** | 所有模块暴露 Prometheus + OpenTelemetry 端点 |

---

## 2. 技术选型方案

### 2.1 核心技术栈

| 层级 | 技术选型 | 选型理由 |
|------|---------|---------|
| **后端语言** | Go 1.23+ / Rust (性能关键路径) | 编译型、高并发、单一二进制部署、编译期安全检查 |
| **Web 框架** | Gin (Go) + Axum (Rust) | Gin 成熟生态，Axum 类型安全 |
| **API 规范** | OpenAPI 3.1 + Protobuf (内部gRPC) | 外部 REST，内部 gRPC 低延迟 |
| **数据库** | PostgreSQL 16 (主存储) | JSONB 支持动态属性、行级安全(RLS)实现多租户隔离 |
| **缓存** | Redis 7 (Cluster 模式) | Session、热数据、Rate Limiter |
| **对象存储** | MinIO (S3-compatible) | 知识库文件、Agent 技能包、日志归档 |
| **向量数据库** | Milvus 2.4+ | 知识库 RAG 检索，10亿级向量规模 |
| **消息队列** | Apache Kafka 3.x | 审计日志、统计事件流、Agent 异步编排 |
| **前端** | React 18 + Next.js 14 (App Router) | SSR + RSC 混合，管理台和门户统一 |
| **桌面端** | Tauri 2.0 (Rust 内核) | 比 Electron 轻 10 倍，内存 < 50MB，天然安全 |
| **沙箱** | gVisor + WASM (wasmtime) | 内核级隔离 + 轻量沙箱分层 |
| **API 网关** | Apache APISIX / Kong | 动态路由、限流、API Key 认证热加载 |
| **监控** | Grafana + Prometheus + OpenTelemetry | 全链路可观测 |

### 2.2 部署拓扑 (生产环境)

```
                         ┌──────────┐
                         │  DNS/CDN  │
                         │(Cloudflare)│
                         └────┬─────┘
                              │
                         ┌────▼─────┐
                         │  APISIX  │
                         │  Gateway │ (2+ 实例, Active-Active)
                         └────┬─────┘
                              │
          ┌───────────────────┼───────────────────┐
          │                   │                   │
    ┌─────▼──────┐    ┌──────▼──────┐    ┌──────▼──────┐
    │ Web 服务   │    │ API 服务    │    │ WebSocket   │
    │ (Next.js)  │    │ (Go/Gin)    │    │ (Go/Gorilla)│
    │ 2+ 实例    │    │ 4+ 实例     │    │ 2+ 实例     │
    └───────────┘    └──────┬──────┘    └─────────────┘
                            │
          ┌─────────────────┼─────────────────┐
          │                 │                 │
    ┌─────▼──────┐   ┌─────▼──────┐   ┌─────▼──────┐
    │ Agent 引擎  │   │  沙箱池    │   │ RAG 检索   │
    │ (Go/Rust)   │   │(gVisor/VM) │   │ (Milvus)   │
    │ 按需伸缩     │   │ 预热池≥10   │   │ 2+ 实例     │
    └─────────────┘   └────────────┘   └────────────┘
```

---

## 3. 核心模块设计

### 3.1 公司管理模块 (Company Service)

```
┌────────────────────────────────────────────────┐
│  Company Service                               │
│                                                │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ 公司注册  │  │ 租户配置  │  │ 套餐/配额   │  │
│  │ 审核流程  │  │ 品牌设置  │  │ 用量管控    │  │
│  └──────────┘  └──────────┘  └────────────┘  │
│                                                │
│  ┌────────────────────────────────────────────┐ │
│  │ 知识库(公司层) — 统一知识资产管理           │ │
│  │  - 共享知识库: 所有团队继承                 │ │
│  │  - 私有知识库: 仅指定团队可见               │ │
│  │  - 知识库版本管理 + 发布审批                │ │
│  └────────────────────────────────────────────┘ │
└────────────────────────────────────────────────┘
```

**关键设计**:
- 每个公司是一个独立租户，PostgreSQL RLS 行级策略实现数据隔离
- 公司创建走轻量审核流程（注册 → 管理员审核 → 激活）
- 套餐(Plan)通过 `plan_id` 关联，控制 Agent 数量上限、API 调用频率、知识库容量

### 3.2 团队管理模块 (Team Service)

```
┌────────────────────────────────────────────────┐
│  Team Service                                  │
│                                                │
│  团队树形结构: Company → Team → Sub-Team       │
│                                                │
│  ┌──────────┐  ┌──────────┐  ┌────────────┐  │
│  │ 团队CRUD  │  │ 成员管理  │  │ 角色绑定    │  │
│  │          │  │ 邀请/移除 │  │ RBAC 角色   │  │
│  └──────────┘  └──────────┘  └────────────┘  │
│                                                │
│  继承规则: Sub-Team 默认继承上级团队的 Agent    │
│  和知识库权限，允许显式覆写                     │
└────────────────────────────────────────────────┘
```

### 3.3 Agent 管理模块 (Agent Service)

**核心实体关系**:
```
Agent
 ├── Base Info (name, avatar, description, system_prompt)
 ├── Model Binding (model_id + params: temperature, top_p, etc.)
 ├── Knowledge Bindings (多个知识库, 权重可配)
 ├── Skill Bindings (内置技能/自定义技能)
 ├── Tool Definitions (function calling 声明)
 ├── API Key 组 (多个 api_key/api_secret 对)
 ├── 版本历史 (每个审核版本快照)
 └── 使用方式标志 (direct_chat + api_access)
```

**生命周期**:
```
DRAFT → PENDING_REVIEW → APPROVED → PUBLISHED → DEPRECATED
                         → REJECTED → DRAFT (打回修改)
PUBLISHED → (修改) → new DRAFT → ... 版本迭代
```

**审核发布机制**:
- Agent 创建/修改后进入 `PENDING_REVIEW` 状态
- 公司超级管理员或指定审核人审核
- 审核内容：System Prompt 安全审查、知识库绑定合规、权限范围检查
- 审核通过后发布，生成版本号 `v{major}.{minor}.{patch}`
- API 调用方可以指定版本或 `latest`

### 3.4 知识库模块 (Knowledge Service — RAG Pipeline)

```
┌──────────────────────────────────────────────────────────┐
│                  知识库处理流水线                          │
│                                                          │
│  上传                   预处理                    索引    │
│  ┌────┐  ┌──────┐  ┌──────────┐  ┌────────┐  ┌─────┐  │
│  │PDF │  │格式   │  │文档分块   │  │向量     │  │     │  │
│  │Word│─▶│解析   │─▶│(Chunking)│─▶│嵌入     │─▶│Milvus│  │
│  │MD  │  │OCR   │  │重叠策略   │  │(Embed)  │  │索引  │  │
│  │Web │  │(可选) │  │          │  │        │  │     │  │
│  └────┘  └──────┘  └──────────┘  └────────┘  └─────┘  │
│                                                          │
│  检索流程:                                                │
│  User Query → Query Rewrite → 混合检索                    │
│    (向量检索 0.7 + 关键词 BM25 0.3) →                     │
│    ReRank → Context Build → LLM Answer                    │
└──────────────────────────────────────────────────────────┘
```

**公司级知识库管理**:
- 公司级知识库: 所有 Agent 可引用（需授权）
- 团队级知识库: 仅指定团队 Agent 可用
- Agent 级知识库: 仅特定 Agent 绑定
- 支持文件格式: PDF, DOCX, MD, TXT, HTML, CSV, 结构化 JSON
- 每个知识库可设置 `access_scope`: `company | team | agent`

### 3.5 权限模块 (AuthN/AuthZ)

```
┌────────────────────────────────────────────────────────┐
│                   权限模型 (RBAC + ABAC)                 │
│                                                        │
│  用户 ── 角色(一个或多个) ── 权限(权限点)                │
│   │                    │                                │
│   │               ┌────▼────┐                           │
│   │               │ 内置角色 │                           │
│   │               │ - super_admin (平台级)              │
│   │               │ - company_admin (公司管理员)        │
│   │               │ - team_lead (团队负责人)            │
│   │               │ - developer (开发者)                │
│   │               │ - viewer (只读用户)                 │
│   └───────────────┴─────────┘                           │
│                                                        │
│  功能权限点示例:                                        │
│  - agent:create, agent:edit, agent:delete              │
│  - agent:approve, agent:publish                        │
│  - knowledge:create, knowledge:share                   │
│  - team:manage_members, team:edit_settings             │
│  - stats:view_company, stats:export                    │
│                                                        │
│  Agent 权限(数据权限):                                   │
│  - 每个 Agent 独立 ACL: user_id + permission_level     │
│    (owner / editor / user / api_only)                  │
│  - 继承规则: team_lead 自动获得团队内所有 Agent 权限    │
└────────────────────────────────────────────────────────┘
```

**API Key 授权机制**:
```
API Key (前缀标识公司+Agent) + API Secret (HMAC-SHA256)
├── 作用域: 仅绑定到单个 Agent
├── 可设置: IP 白名单、速率限制、过期时间
├── 权限: 等同于 role=api_only，只有对话权限
└── 轮换策略: 支持主/备 Key，无缝轮换
```

### 3.6 模型配置模块 (Model Config Service)

```
┌──────────────────────────────────────────────────────┐
│  Model Config Hub                                    │
│                                                      │
│  平台级模型池 → 公司级可用模型 → Agent 绑定模型        │
│                                                      │
│  模型定义:                                           │
│  {                                                   │
│    "id": "gpt-4o",                                   │
│    "provider": "openai|anthropic|deepseek|local",    │
│    "name": "GPT-4o",                                 │
│    "capabilities": ["chat", "function_calling",      │
│                     "vision", "streaming"],           │
│    "pricing": {"input": 2.5, "output": 10},          │
│    "status": "active|deprecated"                     │
│  }                                                   │
│                                                      │
│  Provider 配置:                                      │
│  - 平台统一管理 API Key (Vault 加密存储)              │
│  - 公司可配置自己的 Provider (BYOK)                  │
│  - 支持模型路由: primary → fallback → failover       │
│                                                      │
│  Agent 级别配置:                                     │
│  - model_id + temperature + max_tokens + top_p       │
│  - system_prompt (支持模板变量: {{company_name}})    │
└──────────────────────────────────────────────────────┘
```

### 3.7 统计模块 (Analytics Service)

```
┌──────────────────────────────────────────────────────┐
│  Analytics Service                                   │
│                                                      │
│  事件流 (实时 → Kafka → 批处理 → OLAP/ClickHouse)     │
│                                                      │
│  统计维度:                                           │
│  ┌────────────┬──────────────────┬────────────────┐  │
│  │ Token 统计  │ Agent 使用统计   │ 性能监控        │  │
│  ├────────────┼──────────────────┼────────────────┤  │
│  │ 公司级总量  │ 调用次数(TTL)    │ P50/P95/P99    │  │
│  │ 团队级用量  │ 活跃用户数(DAU)  │ 响应延迟        │  │
│  │ Agent 级   │ 对话轮次/Avg     │ 错误率          │  │
│  │ 模型级     │ 知识库命中率     │ Token 消耗趋势  │  │
│  │ API Key 级 │ 函数调用统计     │ 模型退避率      │  │
│  └────────────┴──────────────────┴────────────────┘  │
│                                                      │
│  告警规则:                                           │
│  - 单 Agent 调用超预算 → 通知                        │
│  - 错误率 > 5% → 自动切换 Fallback 模型              │
│  - API Key 异常流量 → 自动限流/暂停                   │
└──────────────────────────────────────────────────────┘
```

---

## 4. 数据库核心表设计

### 4.1 PostgreSQL 核心表 (ER 关系)

```
┌─────────────────────────────────────────────────────────────────────┐
│  companies                                                        │
│  ├─ id: UUID PK                                                   │
│  ├─ name: VARCHAR(255)                                            │
│  ├─ slug: VARCHAR(100) UNIQUE  -- 用于子域名/路由                  │
│  ├─ plan_id: UUID FK → plans                                     │
│  ├─ status: ENUM(active, suspended, disabled)                     │
│  ├─ settings: JSONB  -- 品牌设置、默认模型、时区                    │
│  ├─ created_at, updated_at                                       │
│  └─ deleted_at: TIMESTAMPTZ (软删除)                              │
│                                                                    │
│  plans ─── 套餐定义                                                │
│  ├─ max_agents: INT                                               │
│  ├─ max_api_calls_per_min: INT                                    │
│  ├─ max_storage_bytes: BIGINT                                     │
│  └─ allowed_models: TEXT[]                                        │
│                                                                    │
│  teams                                                           │
│  ├─ id: UUID PK                                                   │
│  ├─ company_id: UUID FK → companies                               │
│  ├─ parent_team_id: UUID FK → teams (nullable, 树形层级)           │
│  ├─ name: VARCHAR(255)                                            │
│  ├─ path: LTREE  -- PostgreSQL ltree 实现祖先路径查询              │
│  └─ settings: JSONB                                               │
│                                                                    │
│  users ─── 统一用户表 (多租户共享)                                  │
│  ├─ id: UUID PK                                                   │
│  ├─ email: VARCHAR(255) UNIQUE                                    │
│  ├─ password_hash: VARCHAR(255)                                   │
│  ├─ display_name: VARCHAR(255)                                    │
│  └─ status: ENUM(active, invited, disabled)                       │
│                                                                    │
│  user_company_memberships ─── 用户在公司的角色                      │
│  ├─ user_id: UUID FK → users                                     │
│  ├─ company_id: UUID FK → companies                               │
│  ├─ role_id: UUID FK → roles                                     │
│  └─ UNIQUE(user_id, company_id)                                  │
│                                                                    │
│  team_members ─── 团队成员                                         │
│  ├─ user_id: UUID FK → users                                     │
│  ├─ team_id: UUID FK → teams                                     │
│  ├─ role_id: UUID FK → roles                                     │
│  └─ UNIQUE(user_id, team_id)                                     │
│                                                                    │
│  roles ─── 角色定义                                                │
│  ├─ id: UUID PK                                                   │
│  ├─ company_id: UUID FK → companies (nullable, 平台角色为 NULL)     │
│  ├─ name: VARCHAR(100)                                            │
│  ├─ permissions: TEXT[]  -- ['agent:create', 'agent:approve', ...]│
│  └─ is_system: BOOLEAN DEFAULT false                              │
│                                                                    │
│  agents                                                          │
│  ├─ id: UUID PK                                                   │
│  ├─ company_id: UUID FK → companies                               │
│  ├─ team_id: UUID FK → teams (nullable)                           │
│  ├─ name: VARCHAR(255)                                            │
│  ├─ description: TEXT                                             │
│  ├─ avatar_url: VARCHAR(512)                                      │
│  ├─ system_prompt: TEXT                                           │
│  ├─ model_config_id: UUID FK → model_configs                      │
│  ├─ status: ENUM(draft, pending_review, approved, rejected,       │
│  │             published, deprecated)                             │
│  ├─ version: VARCHAR(20)  -- '1.2.0'                              │
│  ├─ usage_modes: TEXT[]  -- ['direct_chat', 'api']                │
│  ├─ settings: JSONB  -- 温度、max_tokens、启用技能列表             │
│  └─ published_by: UUID FK → users                                │
│                                                                    │
│  agent_versions ─── 版本历史快照                                    │
│  ├─ id: UUID PK                                                   │
│  ├─ agent_id: UUID FK → agents                                    │
│  ├─ version: VARCHAR(20)                                          │
│  ├─ snapshot: JSONB  -- 完整 Agent 配置快照                        │
│  ├─ change_log: TEXT                                              │
│  ├─ reviewer_id: UUID FK → users (nullable)                       │
│  └─ review_comment: TEXT                                          │
│                                                                    │
│  model_configs                                                   │
│  ├─ id: UUID PK                                                   │
│  ├─ company_id: UUID FK → companies (nullable, 平台级为 NULL)      │
│  ├─ model_id: VARCHAR(100)  -- 'gpt-4o', 'claude-sonnet-4'       │
│  ├─ provider: VARCHAR(50)                                         │
│  ├─ params: JSONB  -- {temperature, max_tokens, top_p, ...}       │
│  ├─ fallback_model: UUID FK → model_configs (nullable)            │
│  └─ status: ENUM(active, deprecated)                              │
│                                                                    │
│  knowledge_bases                                                 │
│  ├─ id: UUID PK                                                   │
│  ├─ company_id: UUID FK → companies                               │
│  ├─ name: VARCHAR(255)                                            │
│  ├─ description: TEXT                                             │
│  ├─ access_scope: ENUM(company, team, agent)                      │
│  ├─ chunk_strategy: JSONB  -- {size, overlap, separator}          │
│  ├─ embedding_model: VARCHAR(100)                                 │
│  ├─ document_count: INT                                          │
│  ├─ status: ENUM(processing, ready, error)                        │
│  └─ settings: JSONB                                               │
│                                                                    │
│  knowledge_documents ─── 文档/文件                                  │
│  ├─ id: UUID PK                                                   │
│  ├─ knowledge_base_id: UUID FK → knowledge_bases                  │
│  ├─ filename: VARCHAR(512)                                        │
│  ├─ file_path: VARCHAR(1024)  -- MinIO 路径                       │
│  ├─ file_size: BIGINT                                             │
│  ├─ file_type: VARCHAR(50)                                        │
│  ├─ status: ENUM(pending, processing, indexed, failed)            │
│  └─ chunk_count: INT                                              │
│                                                                    │
│  agent_knowledge_bindings ─── Agent 与知识库的绑定关系               │
│  ├─ agent_id: UUID FK → agents                                    │
│  ├─ knowledge_base_id: UUID FK → knowledge_bases                  │
│  ├─ weight: FLOAT DEFAULT 1.0  -- 检索优先级                      │
│  └─ UNIQUE(agent_id, knowledge_base_id)                          │
│                                                                    │
│  api_keys                                                        │
│  ├─ id: UUID PK                                                   │
│  ├─ agent_id: UUID FK → agents                                    │
│  ├─ created_by: UUID FK → users                                   │
│  ├─ key_prefix: VARCHAR(16)  -- 公钥前缀，用于识别                  │
│  ├─ key_hash: VARCHAR(128)  -- API Secret 的 bcrypt 哈希           │
│  ├─ key_last_four: VARCHAR(4)  -- 显示用                          │
│  ├─ ip_whitelist: INET[]                                          │
│  ├─ rate_limit_per_min: INT DEFAULT 60                           │
│  ├─ expires_at: TIMESTAMPTZ (nullable)                           │
│  └─ status: ENUM(active, revoked)                                │
│                                                                    │
│  conversations ─── 对话记录                                         │
│  ├─ id: UUID PK                                                   │
│  ├─ agent_id: UUID FK → agents                                    │
│  ├─ user_id: UUID FK → users (nullable, API 调用可为 NULL)         │
│  ├─ api_key_id: UUID FK → api_keys (nullable)                     │
│  ├─ session_id: VARCHAR(128)                                      │
│  ├─ model_used: VARCHAR(100)                                      │
│  ├─ tokens_input: INT                                            │
│  ├─ tokens_output: INT                                           │
│  ├─ duration_ms: INT                                              │
│  ├─ messages_count: INT                                           │
│  ├─ status: ENUM(active, completed, expired)                     │
│  └─ metadata: JSONB  -- 来源、客户端信息等                         │
│                                                                    │
│  usage_stats_daily ─── 日聚合统计                                  │
│  ├─ id: UUID PK                                                   │
│  ├─ date: DATE                                                    │
│  ├─ company_id: UUID FK → companies                               │
│  ├─ agent_id: UUID FK → agents (nullable)                        │
│  ├─ api_key_id: UUID FK → api_keys (nullable)                     │
│  ├─ model_id: VARCHAR(100)                                        │
│  ├─ tokens_input_total: BIGINT                                   │
│  ├─ tokens_output_total: BIGINT                                  │
│  ├─ request_count: INT                                           │
│  ├─ unique_users: INT                                            │
│  ├─ avg_duration_ms: FLOAT                                       │
│  └─ error_count: INT                                             │
│                                                                    │
│  agent_execution_logs ─── Agent 执行沙箱日志                        │
│  ├─ id: UUID PK                                                   │
│  ├─ agent_id: UUID FK → agents                                    │
│  ├─ skill_name: VARCHAR(255)                                      │
│  ├─ execution_type: ENUM(sandbox, desktop)                        │
│  ├─ input: JSONB                                                  │
│  ├─ output: JSONB                                                 │
│  ├─ exit_code: INT                                                │
│  ├─ resource_usage: JSONB  -- {cpu_ms, memory_kb, network}        │
│  ├─ security_check: JSONB  -- 沙箱安全检查结果                     │
│  └─ created_at: TIMESTAMPTZ                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### 4.2 索引策略

```sql
-- 多租户隔离核心索引
CREATE INDEX idx_companies_slug ON companies(slug) WHERE deleted_at IS NULL;
CREATE INDEX idx_agents_company_status ON agents(company_id, status);
CREATE INDEX idx_teams_path ON teams USING GIST(path);
CREATE INDEX idx_memberships_user ON user_company_memberships(user_id);

-- 检索性能索引
CREATE INDEX idx_conversations_agent_created ON conversations(agent_id, created_at DESC);
CREATE INDEX idx_kb_bindings_agent ON agent_knowledge_bindings(agent_id);
CREATE INDEX idx_usage_stats_date ON usage_stats_daily(date, company_id);

-- RLS 策略所需的索引
CREATE INDEX idx_api_keys_key_prefix ON api_keys(key_prefix);
CREATE INDEX idx_agent_versions_agent ON agent_versions(agent_id, version DESC);
```

### 4.3 多租户 RLS 策略 (行级安全)

```sql
-- 开启 RLS
ALTER TABLE agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE knowledge_bases ENABLE ROW LEVEL SECURITY;

-- 策略: 用户只能看到自己公司的 Agent
CREATE POLICY tenant_isolation ON agents
    USING (company_id IN (
        SELECT company_id FROM user_company_memberships
        WHERE user_id = current_setting('app.current_user_id')::UUID
    ));

-- 策略: API Key 只能看到绑定 Agent 的信息
CREATE POLICY api_key_scope ON agents
    FOR SELECT
    USING (id IN (
        SELECT agent_id FROM api_keys
        WHERE key_prefix = current_setting('app.api_key_prefix')
    ));
```

---

## 5. API 设计思路

### 5.1 API 风格

```
外部 API: RESTful (JSON over HTTPS)
内部 API: gRPC (Protocol Buffers) — 低延迟、强类型
WebSocket: 对话流式响应
```

### 5.2 端点设计

#### 5.2.1 管理 API (前端控制台)

```
Base URL: https://{company}.platform.com/api/v1

公司:
  GET    /companies/me                    → 当前公司信息
  PATCH  /companies/me                    → 更新公司设置
  GET    /companies/me/usage              → 公司用量概览

团队:
  GET    /teams                           → 团队树
  POST   /teams                           → 创建团队
  GET    /teams/:id                       → 团队详情
  PATCH  /teams/:id                       → 更新团队
  DELETE /teams/:id                       → 删除团队
  GET    /teams/:id/members               → 团队成员列表
  POST   /teams/:id/members               → 添加成员
  DELETE /teams/:id/members/:userId       → 移除成员

Agent:
  GET    /agents                          → Agent 列表 (支持 status, team_id 过滤)
  POST   /agents                          → 创建 Agent (返回 DRAFT)
  GET    /agents/:id                      → Agent 详情 (含当前版本)
  PATCH  /agents/:id                      → 更新 Agent (自动新版本 DRAFT)
  DELETE /agents/:id                      → 软删除
  POST   /agents/:id/submit-review        → 提交审核
  POST   /agents/:id/approve              → 审核通过 (管理员)
  POST   /agents/:id/reject               → 审核驳回
  POST   /agents/:id/publish              → 发布 (approve后)
  GET    /agents/:id/versions             → 版本历史
  GET    /agents/:id/versions/:ver        → 特定版本快照
  POST   /agents/:id/api-keys             → 创建 API Key
  GET    /agents/:id/api-keys             → API Key 列表 (仅显示前缀+末4位)
  DELETE /agents/:id/api-keys/:keyId      → 吊销 API Key

知识库:
  GET    /knowledge-bases                 → 知识库列表 (scope 过滤)
  POST   /knowledge-bases                 → 创建知识库
  GET    /knowledge-bases/:id             → 知识库详情
  PATCH  /knowledge-bases/:id             → 更新配置
  DELETE /knowledge-bases/:id             → 删除
  POST   /knowledge-bases/:id/documents   → 上传文档
  DELETE /knowledge-bases/:id/documents/:docId → 删除文档
  GET    /knowledge-bases/:id/documents   → 文档列表
  POST   /knowledge-bases/:id/reindex     → 重新索引

模型:
  GET    /models                          → 可用模型列表
  GET    /models/:id                      → 模型详情
  POST   /agents/:id/bind-model           → 绑定模型配置

权限:
  GET    /roles                           → 角色列表
  POST   /roles                           → 自定义角色
  PATCH  /roles/:id/permissions           → 更新权限点
  GET    /users/:id/permissions           → 用户权限矩阵

统计:
  GET    /stats/overview                  → 概览 (今日/本周/本月)
  GET    /stats/tokens                    → Token 用量 (时间范围 + 分组)
  GET    /stats/agents                    → Agent 调用排行
  GET    /stats/models                    → 模型使用分布
  GET    /stats/api-keys                  → API Key 级统计
  GET    /stats/export                    → 导出 CSV
```

#### 5.2.2 对话 API (面向终端用户)

```
Base URL: https://api.platform.com/v1

对话 (WebSocket + HTTP SSE):
  POST   /agents/:id/chat                → 发送消息 (SSE 流式返回)
  POST   /agents/:id/chat               ← Request:
  {
    "messages": [
      {"role": "user", "content": "hello"}
    ],
    "stream": true,
    "version": "1.2.0"                    -- 可选，默认 latest
  }

  WebSocket:
  ws://api.platform.com/ws/agents/:id/chat
  → 建立连接, 发送 JSON 消息帧, 接收流式事件

  GET    /agents/:id/conversations        → 历史会话列表
  GET    /agents/:id/conversations/:cid   → 会话详情

API Key 认证:
  Header: X-API-Key: {key_prefix}
  Header: X-API-Signature: HMAC-SHA256(
    timestamp + method + path + body,
    api_secret
  )
  Header: X-Timestamp: {unix_ms}
```

### 5.3 API 响应格式

```json
{
  "code": 0,
  "message": "success",
  "data": { ... },
  "pagination": {
    "page": 1,
    "page_size": 20,
    "total": 156,
    "total_pages": 8
  },
  "trace_id": "req-abc123def456"
}
```

错误响应:
```json
{
  "code": 40001,
  "message": "Agent not found or not accessible",
  "details": {
    "agent_id": "uuid",
    "reason": "agent is in draft status"
  },
  "trace_id": "req-abc123def456"
}
```

### 5.4 错误码范围

| 范围 | 含义 |
|------|------|
| 0 | 成功 |
| 100xx | 认证错误 (token 失效、签名错误) |
| 200xx | 权限错误 (无操作权限、无 Agent 访问权) |
| 300xx | 资源错误 (不存在、已删除、配额超限) |
| 400xx | 参数错误 |
| 500xx | 业务逻辑错误 (审核流状态冲突等) |
| 900xx | 服务内部错误 |

---

## 6. 桌面应用 vs 沙箱方案 — 架构决策

### 6.1 方案对比分析

| 维度 | 方案A: 服务器沙箱 (gVisor/Firecracker) | 方案B: 桌面应用本地执行 (Tauri/Go) |
|------|---------------------------------------|-----------------------------------|
| **安全隔离** | ⭐⭐⭐⭐⭐ 内核级隔离，逃逸难度大 | ⭐⭐⭐ 用户态隔离，依赖 OS 权限控制 |
| **延迟** | ~5-20ms 网络延迟 (需回传) | ⭐⭐⭐⭐⭐ <1ms，本地执行 |
| **网络需求** | 必须联网 | 支持离线执行 |
| **资源成本** | 服务器成本 (CPU/内存/存储) | 客户端成本 (用户机器) |
| **运维复杂度** | 中-高 (沙箱池管理、预热) | 低 (客户端自行管理) |
| **版本管理** | 统一服务端控制，强一致性 | 需更新机制，版本碎片化风险 |
| **审计合规** | 全量日志在服务端，合规强 | 日志需回传，有丢失风险 |
| **适用场景** | 企业级、合规敏感、多用户共享 | 个人开发者、低延迟、离线任务 |
| **技能执行范围** | 受限沙箱：网络受限、文件系统隔离 | 可执行本地文件操作、本地系统命令 |

### 6.2 ArchForge 推荐方案: 混合架构

```
┌─────────────────────────────────────────────────────────────────┐
│                   混合执行架构 Hybrid Execution                   │
│                                                                 │
│  执行类型由 Agent 配置 + 运行时策略决定                           │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  执行决策树                                              │    │
│  │                                                         │    │
│  │  任务请求                                                │    │
│  │    ├─ 需要访问本地文件系统? → 桌面执行 (需用户授权确认)    │    │
│  │    ├─ 需要低延迟 (< 10ms)? → 桌面执行                    │    │
│  │    ├─ 涉及敏感数据/合规要求? → 服务器沙箱                 │    │
│  │    ├─ 需要调用外部 API/网络? → 服务器沙箱                │    │
│  │    └─ 默认 → 服务器沙箱 (安全优先)                       │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  平台默认: 服务器沙箱 (gVisor)                                  │
│  可选: 桌面 Agent 运行时 (企业版/高级版)                        │
│                                                                 │
│  ┌──────────────────────┐    ┌──────────────────────┐          │
│  │  服务器沙箱 (默认)     │    │  桌面运行时 (可选)     │          │
│  │                      │    │                      │          │
│  │  gVisor (OCI兼容)     │    │  Tauri 2.0 应用      │          │
│  │  - 每个 Agent 独立沙箱 │    │  - Rust 内核, <50MB  │          │
│  │  - 预热池: 10-50 实例 │    │  - 本地文件沙箱访问   │          │
│  │  - 执行时间限制: 5min │    │  - 系统资源限制       │          │
│  │  - 网络出站受限白名单  │    │  - 需要平台登录授权   │          │
│  │  - 磁盘写完即销毁     │    │  - 执行日志加密回传   │          │
│  │  - 每实例内存上限 1GB │    │  - 支持离线模式       │          │
│  └──────────────────────┘    └──────────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 桌面应用定位

```
桌面 Agent 运行时 (Tauri App)
├── 主要用途: 本地安全执行 Agent 任务
│   ├── 文件系统操作 (读取/处理本地文件)
│   ├── 本地数据库查询
│   ├── 终端命令执行 (受限白名单)
│   └── 离线场景下的推理缓存
├── 与平台的关系:
│   ├── 登录认证 (OAuth2 Device Code Flow)
│   ├── 接收 Agent 任务推送 (WebSocket)
│   ├── 执行后回传结果摘要和 Token 用量
│   └── 定期同步配置和知识库增量更新
├── 安全机制:
│   ├── 用户态沙箱 (wasmtime + seccomp)
│   ├── 每次执行需用户确认 (无后台静默执行)
│   ├── 操作白名单 + 路径白名单
│   └── 审计日志本地加密存储 + 按策略回传
└── 作为服务器沙箱的补充, 不是替代
```

### 6.4 架构演进路线

```
Phase 1 (MVP):  仅服务器沙箱 (gVisor)
                + Web 管理控制台 + API
                → 快速上线，验证核心场景

Phase 2 (3月):  引入 WASM 轻量沙箱层
                - 纯计算/无 IO 的 Skill 走 WASM
                - 降低服务器成本 40-60%

Phase 3 (6月):  桌面 Agent 运行时 (Tauri)
                - 企业版功能
                - 仅限受信任环境
                - 所有桌面执行强制审计回传
```

---

## 7. 扩展性与安全性方案

### 7.1 扩展性设计

#### 7.1.1 水平扩展策略

| 组件 | 扩展方式 | 说明 |
|------|---------|------|
| API 服务 | 无状态 + HPA | K8s HPA 基于 CPU + QPS 自动扩缩 |
| Agent 引擎 | 任务队列 + Worker 池 | Kafka 消费组，按 Agent 类型分 partition |
| 沙箱池 | 预热 + 弹性伸缩 | 保留 10% 空闲实例，高峰期自动创建 |
| 知识库检索 | 只读副本 + 缓存 | Milvus 多副本 + Redis Cache-Aside |
| 统计 | 写分离 + 物化视图 | 原始数据→Kafka→ClickHouse→预聚合 |

#### 7.1.2 性能基线

```
API 响应:
  - P50: < 50ms (不含 AI 推理)
  - P95: < 200ms
  - P99: < 500ms

对话流式首 Token:
  - P50: < 500ms (含推理)
  - P95: < 2s

知识库检索:
  - P50: < 100ms
  - P99: < 500ms (10万文档级别)

并发:
  - 单 API 实例: 2000 QPS
  - 沙箱池: 每节点 50 沙箱实例
```

### 7.2 安全性方案

#### 7.2.1 安全分层

```
┌──────────────────────────────────────────────────────────────┐
│                    安全纵深防御架构                            │
│                                                              │
│  Layer 1: 网络层                                              │
│  ├── WAF (ModSecurity + CRS 规则集)                          │
│  ├── DDoS 防护 (Cloudflare / AWS Shield)                     │
│  ├── API 速率限制 (每 API Key + 每 IP 双层)                   │
│  └── TLS 1.3 + HSTS                                          │
│                                                              │
│  Layer 2: 认证层                                              │
│  ├── 用户认证: OAuth2 + JWT (RS256, 15min 过期)               │
│  ├── API 认证: HMAC-SHA256 签名验证                           │
│  ├── Refresh Token 轮换 (Rotation)                           │
│  └── MFA (TOTP/WebAuthn) 可选                                 │
│                                                              │
│  Layer 3: 授权层                                              │
│  ├── RBAC: 功能权限校验 (中间件)                               │
│  ├── ABAC: Agent ACL 数据权限 (策略引擎)                      │
│  └── RLS: PostgreSQL 行级安全 (数据隔离底线)                   │
│                                                              │
│  Layer 4: 输入层                                              │
│  ├── Prompt 注入检测 (正则 + LLM Guard)                       │
│  ├── 文档内容安全扫描 (ClamAV + 敏感信息检测)                  │
│  ├── SQL 注入防护 (参数化查询 + ORM)                          │
│  └── 文件上传校验 (类型/大小/内容格式)                         │
│                                                              │
│  Layer 5: 沙箱层                                              │
│  ├── gVisor: 独立内核, 文件系统隔离, 网络受限                   │
│  ├── 执行时间硬限制 (超时 kill)                               │
│  ├── 资源上限 (CPU quota + 内存 max)                          │
│  └── 系统调用白名单 (Seccomp 策略)                            │
│                                                              │
│  Layer 6: 数据层                                              │
│  ├── 静态加密: AES-256 (PostgreSQL TDE, MinIO SSE-S3)        │
│  ├── 传输加密: TLS 1.3 全链路                                 │
│  ├── 密钥管理: HashiCorp Vault (自动轮换, 审计)               │
│  ├── 敏感配置: 数据库字段级加密 (pgcrypto)                    │
│  └── 日志脱敏: 自动识别并脱敏 PII (手机/邮箱/身份证)          │
│                                                              │
│  Layer 7: 审计层                                              │
│  ├── 全操作审计日志 (insert-only 表)                          │
│  ├── 管理员操作即时告警                                      │
│  ├── 异常行为检测 (API Key 异常流量模式)                      │
│  └── 合规报告: SOC 2 / ISO 27001 审计追踪                     │
└──────────────────────────────────────────────────────────────┘
```

#### 7.2.2 Prompt 注入防护

```go
// 伪代码: Prompt 注入检测中间件
func PromptGuard(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        var req ChatRequest
        json.NewDecoder(r.Body).Decode(&req)

        for _, msg := range req.Messages {
            // 1. 规则引擎检测
            if rulesEngine.Match(msg.Content) {
                auditLog.Warn("prompt_injection_blocked", msg)
                http.Error(w, "Message blocked by content policy", 451)
                return
            }
            // 2. LLM Guard 二次检测 (采样率 10%)
            if rand.Float32() < 0.1 {
                score := llmGuard.CheckInjection(msg.Content)
                if score > 0.85 {
                    auditLog.Warn("prompt_injection_ai_detected", msg)
                    // 拦截或标记
                }
            }
        }
        next.ServeHTTP(w, r)
    })
}
```

#### 7.2.3 API Key 安全设计

```
API Key 结构:
  {prefix}.{key_id}.{signature}
  示例: sk_compX_agentY_abc123...def

  prefix:   8位 可识别前缀 (用于日志、限流查找)
  key_id:   8位 数据库查询Key
  signature: 32位 HMAC 签名 (验证完整性)

认证流程:
  1. 解析 X-API-Key header → 提取 key_prefix
  2. 从 Redis/Postgres 查询 key_hash + 元数据
  3. 验证 HMAC-SHA256 签名 (timestamp + method + path + body)
  4. 验证 IP 白名单
  5. 验证速率限制 (Redis Sliding Window)
  6. 注入当前 Agent 上下文到请求中

密钥轮换:
  - 支持主/备双 Key (primary, secondary)
  - 轮换时: 新 Key 设为 secondary → 客户端切换 → 旧 Key 降级 → 删除
  - 自动轮换周期: 90 天 (企业策略可配置)
```

---

## 附录 A: 工程纪律检查清单

```
□ Simplicity First
   - 每个服务职责单一, 不超过 3 个核心实体
   - API 端点总数 < 80 (MVP 阶段)
   - 避免过度抽象: 不引入 Event Sourcing / CQRS 除非必要

□ Surgical Changes
   - 模块间通过 OpenAPI/gRPC 合约通信
   - 修改一个模块无需重启其他模块
   - 数据库变更使用 Migration (golang-migrate)

□ Think Before Coding
   - 每个新功能先输出 ADR (架构决策记录)
   - 每次变更评估对多租户隔离的影响
   - 非功能性需求 (性能/安全/成本) 必须在设计阶段评估
```

## 附录 B: 关键 ADR 索引

| ADR | 决策 | 日期 |
|-----|------|------|
| ADR-001 | 使用 PostgreSQL RLS 实现多租户隔离，而非物理分库 | 2026-04-28 |
| ADR-002 | 混合执行架构: 默认服务器沙箱，桌面运行时为企业级可选 | 2026-04-28 |
| ADR-003 | API 认证使用 HMAC-SHA256 而非 OAuth2 Client Credentials | 2026-04-28 |
| ADR-004 | 知识库 RAG 采用 向量+BM25 混合检索 + ReRank | 2026-04-28 |
| ADR-005 | 统计使用 Kafka + ClickHouse 而非直接写入 PostgreSQL | 2026-04-28 |

---

> **ArchForge 签名**: 本方案遵循 Simplicity First 原则，在 MVP 阶段可将服务压缩至 6 个核心模块（公司、团队、Agent、知识库、对话、统计），后续按需拆分。所有技术选型均优先考虑 Go 生态的成熟度与运维简洁性。
