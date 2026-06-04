# 星渡 (XingDu) Rust 版完整实施计划

> 版本: 3.0 (Rust 重写)  
> 日期: 2026-06-04  
> 基于: DESIGN.md Rust 版全部章节  
> 总工时: **40-50 天（单人开发，每天 2-3 小时）**

---

## 总览

### 演进路线

```
v2.0: 省钱网关          Phase 1-3  ─── 管道 + 压缩 + 路由 + 缓存
  ↓
v3.0: 可靠性网关        Phase 4    ─── Fallback + 熔断 + RAG
  ↓
v4.0: 可观测网关        Phase 5    ─── 指标 + 面板 + 安全
  ↓
v5.0: 智能网关          Phase 6-7  ─── 投机执行 + 多模型投票 + 后处理
  ↓
v6.0: LLM 操作系统      Phase 8    ─── 插件 SDK + Webhook + 多租户
```

### Phase 时间线

```
Phase 1 ─── 6-8 天 ─── 基础设施：项目脚手架 + 管道架构 + 协议适配器 + 配置中心
              │
Phase 2 ─── 6-8 天 ─── 成本节省：工具压缩 + Prompt Cache + 响应缓存
              │
Phase 3 ─── 5-7 天 ─── 智能路由：成本路由 + Token 预算 + 多模型 Fallback
              │
Phase 4 ─── 5-7 天 ─── 可靠性：熔断器 + 请求排队 + 星枢 RAG
              │
Phase 5 ─── 7-9 天 ─── 可观测：指标收集 + Web 面板 + 安全层
              │
Phase 6 ─── 5-6 天 ─── 智能层：投机执行 + 多模型投票
              │
Phase 7 ─── 4-5 天 ─── 响应+请求优化：后处理 + 流控 + 重放
              │
Phase 8 ─── 4-5 天 ─── 生态：插件 SDK + Webhook + 多租户
```

### 依赖关系图

```
Phase 1 (管道架构 + 协议适配 + 配置中心)
  ├── 项目脚手架 ── Cargo workspace 初始化
  ├── 中间件引擎 ── 所有后续 Phase 的基石
  ├── 协议适配器 ── 扩展后端的基础
  └── 配置中心 ─── 所有 Phase 依赖
       │
       ▼
Phase 2 (成本节省) ──── Phase 3 (智能路由)
  ├── 工具压缩            ├── 成本路由
  ├── Prompt Cache        ├── Token 预算
  └── 响应缓存            └── 多模型 Fallback
       │                       │
       ▼                       ▼
Phase 4 (可靠性) ──── 并行 ──── Phase 5 (可观测)
  ├── 熔断器               ├── 指标收集
  ├── 请求排队             ├── Web 面板
  └── 星枢 RAG             └── 安全层
       │                       │
       ▼                       ▼
Phase 6 (智能层) ──── Phase 7 (响应+请求优化)
  ├── 投机执行              ├── 响应后处理
  └── 多模型投票            ├── 流控 + 重放
       │                       │
       ▼                       ▼
Phase 8 (生态 + 高级功能)
  ├── 插件 SDK
  ├── Webhook + 告警
  └── 多租户 + 学习反馈
```

---

## Phase 1：基础设施（项目脚手架 + 管道架构 + 协议适配 + 配置中心）

**目标：** 建立 Rust 项目结构、可插拔中间件管道、灵活的协议适配系统、统一的配置管理。

**预估工时：6-8 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.2（管道）+ §3.1（适配器）+ §3.10（配置）

### 1.1 项目脚手架

初始化 Cargo 项目，搭建模块结构。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 1.1.1 | `cargo init xingdu-rs` + 配置 `Cargo.toml`（依赖声明） | `Cargo.toml` | 0.5h |
| 1.1.2 | 配置 `.cargo/config.toml`（编译优化、target） | `.cargo/config.toml` | 0.3h |
| 1.1.3 | 创建模块目录结构 `src/{config,adapter,pipeline,middleware,server,client,metrics,dashboard,security}` | 全部 `mod.rs` | 0.5h |
| 1.1.4 | 配置 `tracing` 日志（tracing-subscriber + env-filter） | `src/main.rs` | 0.5h |
| 1.1.5 | 配置 `clap` CLI 参数解析 | `src/main.rs` | 0.5h |
| 1.1.6 | 配置 `.gitignore` + `README.md` + `LICENSE` | 项目根目录 | 0.3h |
| 1.1.7 | `cargo check` 确认编译通过 | — | 0.2h |

**依赖清单（Cargo.toml）：**

```toml
[dependencies]
# 异步运行时
tokio = { version = "1", features = ["full"] }

# HTTP Server
axum = { version = "0.7", features = ["macros"] }
tower = { version = "0.4", features = ["full"] }
tower-http = { version = "0.5", features = ["cors", "trace"] }

# HTTP Client
reqwest = { version = "0.12", features = ["json", "stream"] }

# 序列化
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# 日志
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# CLI
clap = { version = "4", features = ["derive"] }

# 错误处理
anyhow = "1"
thiserror = "1"

# 加密
aes-gcm = "0.10"
sha2 = "0.10"
hex = "0.4"

# 其他
chrono = { version = "0.4", features = ["serde"] }
futures = "0.3"
async-trait = "0.1"
parking_lot = "0.12"
dashmap = "5"

[dev-dependencies]
tokio-test = "0.4"
```

**验收标准：**
- [ ] `cargo build` 成功
- [ ] `cargo check` 无 warning
- [ ] 模块目录结构完整
- [ ] `cargo run -- --help` 显示 CLI 帮助

---

### 1.2 配置中心

从环境变量加载所有配置，统一管理。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 1.2.1 | 定义 `Config` 结构体（所有配置项） | `src/config/mod.rs` | 1h |
| 1.2.2 | 实现 `Config::from_env()` 方法 | `src/config/mod.rs` | 1h |
| 1.2.3 | 实现 `Config::validate()` 验证方法 | `src/config/mod.rs` | 0.5h |
| 1.2.4 | 添加 `Arc<RwLock<Config>>` 共享模式 | `src/config/mod.rs` | 0.5h |
| 1.2.5 | 创建 `.env.example` 文件（所有变量） | `.env.example` | 0.5h |
| 1.2.6 | 测试：环境变量解析正确 | `tests/config_test.rs` | 0.5h |

**关键代码：**

```rust
// src/config/mod.rs
use std::env;

#[derive(Debug, Clone)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub dump_dir: String,
    pub max_messages: usize,
    pub auto_retry: bool,
    pub auto_retry_max: u32,
    pub tool_compression: u8,
    pub tool_compression_min: usize,
    pub prompt_cache: bool,
    pub resp_cache: u8,
    pub resp_cache_ttl: u64,
    pub redis_url: String,
    pub starhub_enabled: bool,
    pub starhub_url: String,
    pub starhub_limit: usize,
    pub starhub_timeout: u64,
    pub cost_routing: u8,
    pub cheap_model: String,
    pub expensive_model: String,
    pub token_budget: u8,
    pub fallback_enabled: bool,
    pub fallback_chain: Vec<String>,
    pub fallback_timeout: u64,
    pub fallback_retry_codes: Vec<u16>,
    pub circuit_breaker_threshold: u32,
    pub circuit_breaker_recovery: u64,
    pub auth_enabled: bool,
    pub api_keys: Vec<String>,
    pub ip_whitelist: Vec<String>,
    pub rate_limit: u32,
    pub metrics_enabled: bool,
    pub metrics_sqlite_path: String,
    pub audit_log: bool,
    pub audit_log_path: String,
    pub dashboard_enabled: bool,
    pub dashboard_port: u16,
    // ... 60+ 配置项
}

impl Config {
    pub fn from_env() -> Self {
        Config {
            host: env::var("XINGDU_HOST").unwrap_or_else(|_| "0.0.0.0".into()),
            port: env::var("XINGDU_PORT")
                .unwrap_or_else(|_| "9999".into())
                .parse()
                .unwrap_or(9999),
            // ... 其他配置项
        }
    }
}
```

**验收标准：**
- [ ] 所有环境变量正确解析
- [ ] 缺失环境变量时使用默认值
- [ ] `Config::validate()` 捕获无效配置
- [ ] `Arc<RwLock<Config>>` 支持热重载

---

### 1.3 中间件管道引擎

设计并实现可插拔的中间件管道。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 1.3.1 | 定义 `Middleware` trait（`process_request` / `process_response`） | `src/pipeline/middleware.rs` | 0.5h |
| 1.3.2 | 定义 `RequestContext` / `ResponseContext` 数据结构 | `src/pipeline/mod.rs` | 1h |
| 1.3.3 | 实现 `Pipeline` 引擎（注册中间件、按序执行、异常捕获+降级） | `src/pipeline/mod.rs` | 1.5h |
| 1.3.4 | 实现空中间件作为 placeholder | `src/middleware/` | 0.5h |
| 1.3.5 | 编写管道单元测试 | `tests/pipeline_test.rs` | 1h |

**关键代码：**

```rust
// src/pipeline/middleware.rs
use async_trait::async_trait;

#[async_trait]
pub trait Middleware: Send + Sync {
    fn name(&self) -> &str;

    async fn process_request(&self, ctx: &mut RequestContext) -> Result<(), MiddlewareError> {
        Ok(())
    }

    async fn process_response(&self, ctx: &mut ResponseContext) -> Result<(), MiddlewareError> {
        Ok(())
    }

    fn is_enabled(&self, _config: &crate::config::Config) -> bool {
        true
    }
}

// src/pipeline/mod.rs
pub struct Pipeline {
    request_middlewares: Vec<Arc<dyn Middleware>>,
    response_middlewares: Vec<Arc<dyn Middleware>>,
}

impl Pipeline {
    pub fn new() -> Self {
        Pipeline {
            request_middlewares: Vec::new(),
            response_middlewares: Vec::new(),
        }
    }

    pub fn add_request_middleware(&mut self, mw: Arc<dyn Middleware>) {
        self.request_middlewares.push(mw);
    }

    pub fn add_response_middleware(&mut self, mw: Arc<dyn Middleware>) {
        self.response_middlewares.push(mw);
    }

    pub async fn execute_request(&self, ctx: &mut RequestContext) -> Result<(), PipelineError> {
        for mw in &self.request_middlewares {
            if !mw.is_enabled(&ctx.config) {
                continue;
            }
            if let Err(e) = mw.process_request(ctx).await {
                tracing::warn!(middleware = mw.name(), error = %e, "middleware error");
                ctx.errors.push(e);
            }
        }
        Ok(())
    }

    pub async fn execute_response(&self, ctx: &mut ResponseContext) -> Result<(), PipelineError> {
        for mw in &self.response_middlewares {
            if let Err(e) = mw.process_response(ctx).await {
                tracing::warn!(middleware = mw.name(), error = %e, "middleware error");
            }
        }
        Ok(())
    }
}
```

**验收标准：**
- [ ] 中间件按注册顺序执行
- [ ] 中间件异常被 catch 并记录日志
- [ ] 异常不中断管道后续执行
- [ ] `is_enabled()` 正确跳过禁用的中间件

---

### 1.4 协议适配器系统

设计协议适配器接口，实现 OpenAI ↔ Anthropic 转换。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 1.4.1 | 定义 `Adapter` trait（`request_to_backend` / `response_to_client` / `stream_event_to_client`） | `src/adapter/mod.rs` | 0.5h |
| 1.4.2 | 定义请求/响应数据结构（`OpenAIRequest`, `OpenAIResponse` 等） | `src/adapter/types.rs` | 1h |
| 1.4.3 | 实现 `AnthropicAdapter`（O→A→O 转换） | `src/adapter/anthropic.rs` | 2h |
| 1.4.4 | 实现 `OpenAiAdapter`（直通） | `src/adapter/openai.rs` | 0.5h |
| 1.4.5 | 实现适配器工厂（根据 protocol 选择适配器） | `src/adapter/mod.rs` | 0.5h |
| 1.4.6 | 实现 `BackendConfig` + 后端配置加载 | `src/adapter/mod.rs` | 0.5h |
| 1.4.7 | 编写适配器单元测试（非流式 + 流式） | `tests/adapter_test.rs` | 1.5h |

**关键代码：**

```rust
// src/adapter/mod.rs
use async_trait::async_trait;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Protocol {
    OpenAI,
    Anthropic,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackendConfig {
    pub name: String,
    pub url: String,
    pub protocol: Protocol,
    pub api_key: String,
    pub models: Vec<String>,
}

#[async_trait]
pub trait Adapter: Send + Sync {
    async fn request_to_backend(
        &self,
        request: &OpenAIRequest,
        backend: &BackendConfig,
    ) -> Result<BackendRequest, AdapterError>;

    async fn response_to_client(
        &self,
        response: BackendResponse,
        model: &str,
    ) -> Result<OpenAIResponse, AdapterError>;

    fn stream_event_to_client(
        &self,
        event: BackendStreamEvent,
    ) -> Option<OpenAIStreamEvent>;
}

pub fn create_adapter(protocol: &Protocol) -> Arc<dyn Adapter> {
    match protocol {
        Protocol::OpenAI => Arc::new(OpenAiAdapter),
        Protocol::Anthropic => Arc::new(AnthropicAdapter),
    }
}
```

**验收标准：**
- [ ] Anthropic 适配器正确转换 OpenAI → Anthropic 格式
- [ ] Anthropic 适配器正确转换 Anthropic → OpenAI 响应
- [ ] OpenAI 适配器直通不转换
- [ ] 流式事件转换正确
- [ ] 协议工厂正确分发

---

### 1.5 HTTP 服务器 + 路由

基于 axum 实现 HTTP 服务器和路由。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 1.5.1 | 实现 axum Router（`/v1/chat/completions`） | `src/server/mod.rs` | 1h |
| 1.5.2 | 实现请求处理函数（调用 Pipeline → Adapter → 转发） | `src/server/mod.rs` | 1.5h |
| 1.5.3 | 实现流式响应处理（SSE 转换 + 流式转发） | `src/server/mod.rs` | 1.5h |
| 1.5.4 | 实现 reqwest HTTP 客户端（连接池） | `src/client/mod.rs` | 1h |
| 1.5.5 | 集成 Pipeline 到请求处理流程 | `src/server/mod.rs` | 0.5h |
| 1.5.6 | 测试：非流式 + 流式请求完整流程 | `tests/integration_test.rs` | 2h |

**关键代码：**

```rust
// src/server/mod.rs
use axum::{
    Router,
    routing::post,
    Json,
    response::IntoResponse,
};
use std::sync::Arc;

pub struct AppState {
    pub config: Arc<tokio::sync::RwLock<Config>>,
    pub pipeline: Arc<Pipeline>,
    pub client: reqwest::Client,
}

pub fn create_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/v1/chat/completions", post(handle_chat_completions))
        .with_state(state)
}

async fn handle_chat_completions(
    State(state): State<Arc<AppState>>,
    Json(request): Json<OpenAIRequest>,
) -> impl IntoResponse {
    // 1. 构建 RequestContext
    let mut ctx = RequestContext::new(request, state.config.clone());

    // 2. 执行 Request Pipeline
    if let Err(e) = state.pipeline.execute_request(&mut ctx).await {
        return Err(XingduError::PipelineError(e));
    }

    // 3. 转发后端
    let backend_response = forward_to_backend(&ctx, &state.client).await?;

    // 4. 协议适配器转换
    let adapter = create_adapter(&ctx.backend.protocol);
    let openai_response = adapter.response_to_client(backend_response, &ctx.request.model).await?;

    // 5. 构建 ResponseContext
    let mut resp_ctx = ResponseContext::new(openai_response);

    // 6. 执行 Response Pipeline
    state.pipeline.execute_response(&mut resp_ctx).await.ok();

    Ok(Json(resp_ctx.response))
}
```

**验收标准：**
- [ ] `cargo build` 成功
- [ ] 服务器启动并监听配置端口
- [ ] 非流式请求正常转发并返回
- [ ] 流式请求 SSE 事件正确转换
- [ ] Pipeline 中间件正确执行

---

### 🎯 Phase 1 交付物

| 产出 | 说明 |
|------|------|
| `Cargo.toml` | 依赖配置 |
| `src/config/mod.rs` | 配置中心（~150 行） |
| `src/pipeline/` | 中间件管道引擎（~200 行） |
| `src/adapter/` | 协议适配器（~400 行） |
| `src/server/mod.rs` | HTTP 服务器 + 路由（~200 行） |
| `src/client/mod.rs` | HTTP 客户端（~50 行） |
| `src/main.rs` | 入口 + CLI（~80 行） |
| `.env.example` | 环境变量模板 |
| `tests/` | 单元测试 + 集成测试 |

### ⚠️ Phase 1 技术决策

| 决策 | 选项 | 推荐 |
|------|------|------|
| 项目结构 | 单 crate / workspace | 单 crate（前期简单） |
| 配置热重载 | 定时轮询 / 信号触发 | 定时轮询（简单可靠） |
| 中间件注册 | 编译时 / 运行时 | 运行时（灵活） |
| 错误传播 | anyhow / thiserror | 混合：anyhow 业务 + thiserror API |

### ⚠️ Phase 1 风险点

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| Rust 学习曲线陡峭 | 中 | 中 | 先实现最小可运行版本，逐步优化 |
| Axum 0.7 API 变化 | 低 | 低 | 锁定版本，关注 changelog |
| 流式处理复杂 | 中 | 中 | 先实现非流式，再加流式 |

---

## Phase 2：成本节省（工具压缩 + Prompt Cache + 响应缓存）

**目标：** 显著降低 Token 消耗和 API 调用成本。

**预估工时：6-8 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.3（压缩）+ §3.4（缓存）

### 2.1 工具输出压缩

实现智能压缩算法，对大 JSON、长文本、代码块进行无损/低损压缩。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 2.1.1 | 实现 JSON 智能压缩：扁平化、去冗余 key、数组转表格 | `src/middleware/headroom.rs` | 2h |
| 2.1.2 | 实现长文本截断/摘要：保留首尾 20% | `src/middleware/headroom.rs` | 1.5h |
| 2.1.3 | 实现代码压缩：去注释、合并空行 | `src/middleware/headroom.rs` | 1.5h |
| 2.1.4 | 封装为 Middleware trait 实现 | `src/middleware/headroom.rs` | 0.5h |
| 2.1.5 | 添加压缩统计（压缩率、耗时） | `src/middleware/headroom.rs` | 0.5h |
| 2.1.6 | 添加环境变量支持 | `src/config/mod.rs` | 0.3h |
| 2.1.7 | 测试：多种工具输出格式压缩效果 | `tests/headroom_test.rs` | 1.5h |

**压缩策略（Rust 实现）：**

```rust
// src/middleware/headroom.rs
pub struct ToolCompressionMiddleware {
    min_chars: usize,
}

impl Middleware for ToolCompressionMiddleware {
    fn name(&self) -> &str { "tool_compression" }

    async fn process_request(&self, ctx: &mut RequestContext) -> Result<(), MiddlewareError> {
        for msg in &mut ctx.request.messages {
            if is_tool_result(msg) {
                let content = extract_content(msg);
                if content.len() > self.min_chars {
                    let compressed = compress(&content);
                    replace_content(msg, &compressed);
                }
            }
        }
        Ok(())
    }
}

fn compress(content: &str) -> String {
    if looks_like_json(content) {
        compress_json(content)
    } else if looks_like_code(content) {
        compress_code(content)
    } else {
        compress_text(content)
    }
}
```

**验收标准：**
- [ ] JSON > 1000 字符时压缩率 ≥ 50%
- [ ] 代码块 > 500 字符时压缩率 ≥ 40%
- [ ] 长文本 > 2000 字符时压缩率 ≥ 30%
- [ ] `XINGDU_TOOL_COMPRESSION=0` 时跳过压缩

---

### 2.2 Prompt Cache 对齐

将 system prompt 拆分为静态/动态两部分，利用 `cache_control` 机制。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 2.2.1 | 验证后端对 `cache_control` 参数的支持 | 手动 curl 测试 | 0.5h |
| 2.2.2 | 实现静态/动态 system prompt 拆分 | `src/middleware/cache_align.rs` | 1h |
| 2.2.3 | 封装为 Middleware（重组 system prompt 为 blocks 格式） | `src/middleware/cache_align.rs` | 1h |
| 2.2.4 | 静态块添加 `cache_control` | `src/middleware/cache_align.rs` | 0.3h |
| 2.2.5 | 后端不支持时静默降级 | `src/middleware/cache_align.rs` | 0.3h |
| 2.2.6 | 测试：开启/关闭 cache 验证响应 | `tests/cache_align_test.rs` | 1h |

**验收标准：**
- [ ] 静态 system prompt 正确标记 `cache_control`
- [ ] 后端不支持时降级到字符串格式
- [ ] `XINGDU_PROMPT_CACHE=0` 时行为不变

---

### 2.3 响应缓存

对相同请求直接返回缓存的响应。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 2.3.1 | 实现缓存 Key 生成（sha256） | `src/middleware/cache.rs` | 0.5h |
| 2.3.2 | 实现进程内缓存存储（`DashMap` + TTL） | `src/middleware/cache.rs` | 1h |
| 2.3.3 | 封装为 Middleware（`process_request` 查缓存，`process_response` 写缓存） | `src/middleware/cache.rs` | 1h |
| 2.3.4 | 非流式缓存，流式不缓存 | `src/middleware/cache.rs` | 0.3h |
| 2.3.5 | 实现 Redis 缓存后端（可选） | `src/middleware/cache.rs` | 1.5h |
| 2.3.6 | 添加缓存统计（命中/未命中） | `src/middleware/cache.rs` | 0.3h |
| 2.3.7 | 测试：缓存命中/未命中 | `tests/cache_test.rs` | 1h |

**验收标准：**
- [ ] 相同请求第二次命中缓存
- [ ] 任一字段不同时不走缓存
- [ ] TTL 过期后重新请求
- [ ] `XINGDU_RESP_CACHE=0` 时跳过

---

### 🎯 Phase 2 交付物

| 产出 | 说明 |
|------|------|
| `src/middleware/headroom.rs` | 工具压缩中间件（~250 行） |
| `src/middleware/cache_align.rs` | Prompt Cache 对齐（~100 行） |
| `src/middleware/cache.rs` | 响应缓存（~200 行） |
| `tests/` | 压缩 + 缓存测试 |

### ⚠️ Phase 2 风险点

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| DashScope 不支持 cache_control | **高** | 低 | 降级到字符串格式，无缓存收益但不报错 |
| 压缩丢失关键信息 | 中 | 高 | 保守压缩（MIN_CHARS 过滤短消息） |
| 缓存内存泄漏 | 低 | 中 | TTL + DashMap 容量限制 |

---

## Phase 3：智能路由（成本路由 + Token 预算 + 多模型 Fallback）

**目标：** 根据请求复杂度智能选择模型、控制 Token 预算、故障时自动切换模型。

**预估工时：5-7 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.5（成本路由）+ §3.6（降级）

### 3.1 多模型 Fallback

主模型失败时自动按 fallback 链依次尝试。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 3.1.1 | 定义触发 fallback 的状态码 | `src/middleware/fallback.rs` | 0.3h |
| 3.1.2 | 实现 FallbackMiddleware（失败后遍历链重试） | `src/middleware/fallback.rs` | 1.5h |
| 3.1.3 | 流式请求非首块失败处理 | `src/middleware/fallback.rs` | 0.5h |
| 3.1.4 | Fallback 时自动切换适配器 | `src/middleware/fallback.rs` | 0.5h |
| 3.1.5 | 添加 fallback 日志和 Metrics | `src/middleware/fallback.rs` | 0.3h |
| 3.1.6 | 测试：模拟后端 500 验证切换 | `tests/fallback_test.rs` | 1h |

**验收标准：**
- [ ] 主模型 500/502/503 时自动切换
- [ ] 所有模型失败时返回最后错误
- [ ] 流式请求不触发 fallback

---

### 3.2 成本路由

基于规则判断请求复杂度，简单走便宜模型，复杂走主模型。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 3.2.1 | 实现复杂度评分引擎 | `src/middleware/cost_routing.rs` | 1h |
| 3.2.2 | 实现模型选择逻辑 | `src/middleware/cost_routing.rs` | 0.5h |
| 3.2.3 | 封装为 Middleware | `src/middleware/cost_routing.rs` | 0.5h |
| 3.2.4 | 用户指定 model 时跳过路由 | `src/middleware/cost_routing.rs` | 0.3h |
| 3.2.5 | 测试：简单/复杂请求走不同模型 | `tests/cost_routing_test.rs` | 1h |

**验收标准：**
- [ ] 简单请求走便宜模型
- [ ] 复杂请求走主模型
- [ ] 用户指定 model 时跳过

---

### 3.3 Token 预算控制

监控请求 Token 消耗，接近上限时预警/截断。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 3.3.1 | 维护模型上下文窗口映射表 | `src/middleware/budget.rs` | 0.3h |
| 3.3.2 | 实现 Token 估算（字符数粗略估算） | `src/middleware/budget.rs` | 0.5h |
| 3.3.3 | 实现预算检查（80% 告警 / 95% 截断） | `src/middleware/budget.rs` | 1h |
| 3.3.4 | 封装为 Middleware | `src/middleware/budget.rs` | 0.3h |
| 3.3.5 | 测试：超长上下文场景 | `tests/budget_test.rs` | 1h |

**验收标准：**
- [ ] 达到 80% 阈值时告警日志
- [ ] 达到 95% 阈值时强制截断
- [ ] 未知模型使用保守估计

---

### 🎯 Phase 3 交付物

| 产出 | 说明 |
|------|------|
| `src/middleware/fallback.rs` | Fallback 中间件（~150 行） |
| `src/middleware/cost_routing.rs` | 成本路由中间件（~100 行） |
| `src/middleware/budget.rs` | Token 预算中间件（~100 行） |
| `tests/` | 路由 + 降级测试 |

---

## Phase 4：可靠性增强（熔断器 + 请求排队 + 星枢 RAG）

**目标：** 提升服务健壮性，防止级联故障，增加知识增强能力。

**预估工时：5-7 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.7（星枢 RAG）+ §3.9（熔断器）

### 4.1 熔断器

后端连续失败时自动断开，定期探活恢复。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 4.1.1 | 实现熔断器状态机（`Closed → Open → HalfOpen`） | `src/middleware/circuit_breaker.rs` | 1.5h |
| 4.1.2 | 按后端维度维护独立熔断器实例 | `src/middleware/circuit_breaker.rs` | 0.5h |
| 4.1.3 | 封装为 Middleware | `src/middleware/circuit_breaker.rs` | 0.5h |
| 4.1.4 | 与 Fallback 联动 | `src/middleware/circuit_breaker.rs` | 0.5h |
| 4.1.5 | 测试：模拟连续失败验证状态机 | `tests/circuit_breaker_test.rs` | 1.5h |

**验收标准：**
- [ ] 连续 N 次失败后自动断开
- [ ] 定期探活恢复
- [ ] 与 Fallback 联动

---

### 4.2 请求排队

后端限流时请求入队等待。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 4.2.1 | 实现请求队列（`tokio::sync::Semaphore`） | `src/middleware/request_queue.rs` | 1h |
| 4.2.2 | 实现排队逻辑（并发超阈值入队） | `src/middleware/request_queue.rs` | 1h |
| 4.2.3 | 按后端维度独立队列 | `src/middleware/request_queue.rs` | 0.5h |
| 4.2.4 | 队列满返回 429 | `src/middleware/request_queue.rs` | 0.3h |
| 4.2.5 | 测试：高并发排队行为 | `tests/queue_test.rs` | 1h |

**验收标准：**
- [ ] 并发超阈值时排队
- [ ] 有空位时自动出队
- [ ] 队列满返回 429

---

### 4.3 星枢 RAG 集成

在转发前调用星枢向量搜索，注入知识。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 4.3.1 | 实现星枢 HTTP 客户端 | `src/middleware/starhub.rs` | 1h |
| 4.3.2 | 实现搜索判断逻辑 | `src/middleware/starhub.rs` | 0.5h |
| 4.3.3 | 封装为 Middleware | `src/middleware/starhub.rs` | 0.5h |
| 4.3.4 | 超时/连接失败降级 | `src/middleware/starhub.rs` | 0.3h |
| 4.3.5 | 测试：星枢在线/离线两种场景 | `tests/starhub_test.rs` | 1h |

**验收标准：**
- [ ] 星枢在线时搜索并注入
- [ ] 星枢离线时请求正常转发
- [ ] `XINGDU_STARHUB_ENABLED=0` 时不调用

---

### 🎯 Phase 4 交付物

| 产出 | 说明 |
|------|------|
| `src/middleware/circuit_breaker.rs` | 熔断器（~150 行） |
| `src/middleware/request_queue.rs` | 请求排队（~120 行） |
| `src/middleware/starhub.rs` | 星枢 RAG（~120 行） |
| `tests/` | 熔断/排队/RAG 测试 |

---

## Phase 5：可观测性（指标收集 + Web 面板 + 安全层）

**目标：** 可视化运营数据、安全管理、审计追踪。

**预估工时：7-9 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.8（指标）+ §3.11（面板）+ §3.14（安全）

### 5.1 全局指标收集

实时采集和聚合所有运营指标。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 5.1.1 | 实现 `MetricsCollector`（原子计数器） | `src/metrics/mod.rs` | 1.5h |
| 5.1.2 | 实现 Metrics 中间件 | `src/middleware/metrics.rs` | 1h |
| 5.1.3 | 实现 SQLite 存储层 | `src/metrics/storage.rs` | 2h |
| 5.1.4 | 实现查询接口（`/metrics` JSON API） | `src/metrics/api.rs` | 1h |
| 5.1.5 | 测试：指标收集正确性 | `tests/metrics_test.rs` | 1h |

**验收标准：**
- [ ] 每个请求的指标被记录
- [ ] SQLite 持久化正常
- [ ] 查询接口返回正确数据

---

### 5.2 Web 管理面板

轻量级可视化仪表盘。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 5.2.1 | 实现仪表盘路由（`/dashboard`） | `src/dashboard/mod.rs` | 1h |
| 5.2.2 | 内嵌 HTML + Tailwind + Chart.js | `src/dashboard/templates/` | 2h |
| 5.2.3 | 实现实时统计 API | `src/dashboard/api.rs` | 1h |
| 5.2.4 | 实现成本曲线页面 | `src/dashboard/templates/` | 1h |
| 5.2.5 | 测试：面板页面加载 | 手动测试 | 1h |

**技术方案：**

```rust
// 使用 include_str! 宏编译进二进制
const DASHBOARD_HTML: &str = include_str!("templates/dashboard.html");

// axum 路由
async fn dashboard_handler() -> Html<&'static str> {
    Html(DASHBOARD_HTML)
}
```

**验收标准：**
- [ ] 面板页面正常加载
- [ ] 实时统计数据正确展示
- [ ] 成本曲线可视化

---

### 5.3 安全层

鉴权、限流、审计。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 5.3.1 | 实现 API Key 鉴权中间件 | `src/middleware/auth.rs` | 1h |
| 5.3.2 | 实现 IP 白名单 | `src/middleware/auth.rs` | 0.5h |
| 5.3.3 | 实现请求限流（令牌桶） | `src/middleware/rate_limiter.rs` | 1.5h |
| 5.3.4 | 实现审计日志中间件 | `src/middleware/audit.rs` | 1h |
| 5.3.5 | 注册所有安全中间件到 Pipeline | `src/server/mod.rs` | 0.3h |
| 5.3.6 | 测试：无 key 被拒绝 / 超限流被限 | `tests/security_test.rs` | 1.5h |

**验收标准：**
- [ ] 未提供 API Key 返回 401
- [ ] IP 不在白名单返回 403
- [ ] 超过限流返回 429
- [ ] 审计日志正确记录

---

### 🎯 Phase 5 交付物

| 产出 | 说明 |
|------|------|
| `src/metrics/` | 指标收集 + 存储 + API（~300 行） |
| `src/dashboard/` | Web 面板（~400 行） |
| `src/middleware/auth.rs` | 鉴权中间件（~100 行） |
| `src/middleware/rate_limiter.rs` | 限流中间件（~100 行） |
| `src/middleware/audit.rs` | 审计日志（~80 行） |
| `tests/` | 安全 + 指标测试 |

---

## Phase 6：智能层（投机执行 + 多模型投票）

**目标：** 利用多个模型的协同效应，提升回答质量和成本效益。

**预估工时：5-6 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.12（智能层）

### 6.1 投机执行

便宜模型先生成草稿，贵模型只验证/修正。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 6.1.1 | 实现草稿-验证两阶段流程 | `src/middleware/speculative.rs` | 2h |
| 6.1.2 | 便宜模型草稿 → 贵模型验证 | `src/middleware/speculative.rs` | 1h |
| 6.1.3 | 差异太大时回退 | `src/middleware/speculative.rs` | 0.5h |
| 6.1.4 | 测试：对比投机执行与普通执行 | `tests/speculative_test.rs` | 1h |

**验收标准：**
- [ ] 便宜模型生成草稿
- [ ] 贵模型验证修正
- [ ] 成本节省 ≥ 30%

---

### 6.2 多模型投票

同一请求发给多个模型，取最优结果。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 6.2.1 | 实现并行多模型调用（`tokio::join!`） | `src/middleware/model_voting.rs` | 1.5h |
| 6.2.2 | 实现投票/选择策略 | `src/middleware/model_voting.rs` | 1h |
| 6.2.3 | 只支持非流式 | `src/middleware/model_voting.rs` | 0.3h |
| 6.2.4 | 测试：多模型投票验证 | `tests/voting_test.rs` | 1h |

**验收标准：**
- [ ] 请求同时发给多个模型
- [ ] 按策略选择最优结果
- [ ] 成本增加但准确率提升

---

### 🎯 Phase 6 交付物

| 产出 | 说明 |
|------|------|
| `src/middleware/speculative.rs` | 投机执行（~150 行） |
| `src/middleware/model_voting.rs` | 多模型投票（~120 行） |
| `tests/` | 投机 + 投票测试 |

---

## Phase 7：响应层 + 请求层优化

**目标：** 精细化控制响应输出，增强请求调试能力。

**预估工时：4-5 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.13（后处理）

### 7.1 响应后处理

自动格式化/摘要/脱敏。

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 7.1.1 | 实现响应格式化中间件 | `src/middleware/response_postproc.rs` | 1h |
| 7.1.2 | 实现自动摘要（超长响应压缩） | `src/middleware/response_postproc.rs` | 1h |
| 7.1.3 | 测试：后处理效果 | `tests/postproc_test.rs` | 0.5h |

### 7.2 请求重放 + 优先级

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 7.2.1 | 实现请求重放接口 | `src/middleware/request_replay.rs` | 1h |
| 7.2.2 | 实现请求优先级中间件 | `src/middleware/request_priority.rs` | 0.5h |
| 7.2.3 | 测试：重放 + 优先级 | `tests/replay_test.rs` | 0.5h |

**验收标准：**
- [ ] 响应格式化正常
- [ ] 请求重放返回历史结果
- [ ] 高优先级请求插队

---

## Phase 8：生态 + 高级功能

**目标：** 构建插件生态，支持多租户。

**预估工时：4-5 天**  
**每日投入：2-3 小时**  
**对应 DESIGN.md：** §3.13（插件）

### 8.1 插件 SDK

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 8.1.1 | 定义 Plugin trait | `src/plugin/mod.rs` | 0.5h |
| 8.1.2 | 实现插件加载器（扫描 `plugins/` 目录） | `src/plugin/loader.rs` | 1h |
| 8.1.3 | 编写示例插件 | `plugins/example.rs` | 0.5h |
| 8.1.4 | 测试：加载示例插件 | `tests/plugin_test.rs` | 0.5h |

### 8.2 Webhook + 告警

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 8.2.1 | 实现 Webhook 中间件 | `src/middleware/webhook.rs` | 1h |
| 8.2.2 | 实现告警通道（Slack/Telegram） | `src/alerting/mod.rs` | 1h |
| 8.2.3 | 测试：Webhook + 告警 | `tests/webhook_test.rs` | 0.5h |

### 8.3 多租户

| # | 任务 | 文件 | 预估工时 |
|---|------|------|----------|
| 8.3.1 | 实现租户上下文 | `src/middleware/tenant.rs` | 1h |
| 8.3.2 | 实现租户隔离 | `src/middleware/tenant.rs` | 0.5h |
| 8.3.3 | 测试：多租户隔离 | `tests/tenant_test.rs` | 0.5h |

**验收标准：**
- [ ] 插件正确加载并执行 Hook
- [ ] Webhook 回调正常
- [ ] 多租户配置隔离

---

## 最终目录结构

```
xingdu-rs/
├── Cargo.toml
├── Cargo.lock
├── .env.example
├── .gitignore
├── README.md
├── LICENSE
├── DESIGN.md
├── PLAN.md
├── src/
│   ├── main.rs                    # 入口 + CLI（~100 行）
│   ├── lib.rs                     # 库入口
│   ├── config/
│   │   └── mod.rs                 # 配置中心（~150 行）
│   ├── adapter/
│   │   ├── mod.rs                 # Adapter trait + 工厂
│   │   ├── types.rs               # 请求/响应数据结构
│   │   ├── anthropic.rs           # Anthropic 协议转换
│   │   └── openai.rs              # OpenAI 直通
│   ├── pipeline/
│   │   ├── mod.rs                 # Pipeline + Context
│   │   ├── middleware.rs           # Middleware trait
│   │   └── error.rs               # 管道错误
│   ├── middleware/
│   │   ├── mod.rs                 # 中间件注册
│   │   ├── headroom.rs            # 工具压缩
│   │   ├── cache_align.rs         # Prompt Cache 对齐
│   │   ├── cache.rs               # 响应缓存
│   │   ├── cost_routing.rs        # 成本路由
│   │   ├── budget.rs              # Token 预算
│   │   ├── fallback.rs            # 多模型降级
│   │   ├── circuit_breaker.rs     # 熔断器
│   │   ├── request_queue.rs       # 请求排队
│   │   ├── starhub.rs             # 星枢 RAG
│   │   ├── auth.rs                # 鉴权
│   │   ├── rate_limiter.rs        # 限流
│   │   ├── audit.rs               # 审计日志
│   │   ├── metrics.rs             # 指标收集
│   │   ├── speculative.rs         # 投机执行
│   │   ├── model_voting.rs        # 多模型投票
│   │   ├── response_postproc.rs   # 响应后处理
│   │   ├── request_replay.rs      # 请求重放
│   │   ├── request_priority.rs    # 请求优先级
│   │   ├── webhook.rs             # Webhook
│   │   └── tenant.rs              # 多租户
│   ├── server/
│   │   ├── mod.rs                 # HTTP 服务器 + 路由
│   │   └── sse.rs                 # SSE 流式处理
│   ├── client/
│   │   └── mod.rs                 # reqwest 客户端
│   ├── metrics/
│   │   ├── mod.rs                 # 指标收集器
│   │   ├── storage.rs             # SQLite 存储
│   │   └── api.rs                 # 查询接口
│   ├── dashboard/
│   │   ├── mod.rs                 # 面板路由
│   │   ├── api.rs                 # 面板 API
│   │   └── templates/
│   │       ├── dashboard.html     # 实时流量
│   │       └── cost.html          # 成本曲线
│   ├── plugin/
│   │   ├── mod.rs                 # Plugin trait
│   │   └── loader.rs              # 插件加载器
│   └── alerting/
│       └── mod.rs                 # 告警系统
├── plugins/
│   └── example.rs                 # 示例插件
├── tests/
│   ├── config_test.rs
│   ├── adapter_test.rs
│   ├── pipeline_test.rs
│   ├── headroom_test.rs
│   ├── cache_test.rs
│   ├── fallback_test.rs
│   ├── circuit_breaker_test.rs
│   ├── metrics_test.rs
│   ├── security_test.rs
│   └── integration_test.rs
└── deploy/
    ├── xingdu.service
    └── deploy.sh
```

---

## 环境变量完整清单

| 变量 | 默认值 | Phase | 说明 |
|------|--------|-------|------|
| **基础** | | | |
| `XINGDU_HOST` | `0.0.0.0` | 1 | 监听地址 |
| `XINGDU_PORT` | `9999` | 1 | 监听端口 |
| `XINGDU_DUMP_DIR` | `/tmp/xingdu_dumps` | 1 | dump 目录 |
| `XINGDU_MAX_MESSAGES` | `200` | 1 | 最大消息数 |
| `XINGDU_AUTO_RETRY` | `1` | 1 | 重试开关 |
| `XINGDU_AUTO_RETRY_MAX` | `1` | 1 | 最大重试次数 |
| `XINGDU_LOG_LEVEL` | `info` | 1 | 日志级别 |
| **Phase 2 — 成本节省** | | | |
| `XINGDU_TOOL_COMPRESSION` | `0` | 2 | 工具压缩：0=关 1=智能 |
| `XINGDU_TOOL_COMPRESSION_MIN` | `500` | 2 | 压缩阈值 |
| `XINGDU_PROMPT_CACHE` | `0` | 2 | Prompt Cache |
| `XINGDU_RESP_CACHE` | `0` | 2 | 响应缓存：0=关 1=进程内 |
| `XINGDU_RESP_CACHE_TTL` | `300` | 2 | 缓存 TTL |
| `XINGDU_REDIS_URL` | `""` | 2 | Redis URL |
| **Phase 3 — 智能路由** | | | |
| `XINGDU_FALLBACK_ENABLED` | `0` | 3 | Fallback 开关 |
| `XINGDU_FALLBACK_CHAIN` | `""` | 3 | Fallback 链 |
| `XINGDU_FALLBACK_TIMEOUT` | `30` | 3 | 超时秒数 |
| `XINGDU_FALLBACK_RETRY_CODES` | `429,500,502,503` | 3 | 触发状态码 |
| `XINGDU_COST_ROUTING` | `0` | 3 | 成本路由 |
| `XINGDU_CHEAP_MODEL` | `qwen-turbo` | 3 | 便宜模型 |
| `XINGDU_EXPENSIVE_MODEL` | `qwen3.6-plus` | 3 | 主模型 |
| `XINGDU_TOKEN_BUDGET` | `0` | 3 | Token 预算 |
| **Phase 4 — 可靠性** | | | |
| `XINGDU_CIRCUIT_BREAKER_THRESHOLD` | `5` | 4 | 熔断阈值 |
| `XINGDU_CIRCUIT_BREAKER_RECOVERY` | `30` | 4 | 恢复间隔 |
| `XINGDU_QUEUE_ENABLED` | `0` | 4 | 排队开关 |
| `XINGDU_QUEUE_MAX_CONCURRENT` | `10` | 4 | 最大并发 |
| `XINGDU_STARHUB_ENABLED` | `0` | 4 | 星枢开关 |
| `XINGDU_STARHUB_URL` | `http://localhost:26670/search` | 4 | 星枢 URL |
| `XINGDU_STARHUB_LIMIT` | `5` | 4 | 搜索结果数 |
| `XINGDU_STARHUB_TIMEOUT` | `2` | 4 | 超时秒数 |
| **Phase 5 — 可观测性** | | | |
| `XINGDU_METRICS_ENABLED` | `0` | 5 | 指标开关 |
| `XINGDU_METRICS_SQLITE_PATH` | `/tmp/xingdu_metrics.db` | 5 | SQLite 路径 |
| `XINGDU_DASHBOARD_ENABLED` | `0` | 5 | 面板开关 |
| `XINGDU_AUTH_ENABLED` | `0` | 5 | 鉴权开关 |
| `XINGDU_API_KEYS` | `""` | 5 | API Key 列表 |
| `XINGDU_IP_WHITELIST` | `""` | 5 | IP 白名单 |
| `XINGDU_RATE_LIMIT` | `0` | 5 | 限流 |
| `XINGDU_AUDIT_LOG` | `0` | 5 | 审计开关 |
| **Phase 6 — 智能层** | | | |
| `XINGDU_SPECULATIVE_ENABLED` | `0` | 6 | 投机执行 |
| `XINGDU_VOTING_ENABLED` | `0` | 6 | 多模型投票 |
| **Phase 8 — 生态** | | | |
| `XINGDU_PLUGINS_ENABLED` | `0` | 8 | 插件开关 |
| `XINGDU_WEBHOOK_URL` | `""` | 8 | Webhook URL |
| `XINGDU_TENANT_ENABLED` | `0` | 8 | 多租户开关 |

---

## 风险登记册

| # | 风险 | 影响 | 概率 | 等级 | 缓解措施 |
|---|------|------|------|------|----------|
| R1 | **Rust 学习曲线**导致进度慢 | 中 | 中 | **中** | 先实现最小可运行版本，逐步优化 |
| R2 | **Axum/Reqwest API 变化** | 低 | 低 | 低 | 锁定版本，关注 changelog |
| R3 | **流式处理复杂** | 中 | 中 | 中 | 先实现非流式，再加流式 |
| R4 | **DashScope 不支持 cache_control** | 低 | 高 | 低 | 降级到字符串格式 |
| R5 | **工具压缩丢失信息** | 高 | 低 | 中 | 保守压缩 + MIN_CHARS |
| R6 | **多模型投票成本翻倍** | 高 | 中 | 高 | 默认关闭；只对高价值请求启用 |
| R7 | **面板暴露敏感信息** | 高 | 低 | 中 | 面板需要鉴权 |
| R8 | **并发 bug** | 中 | 低 | 低 | Rust 所有权系统 + 测试覆盖 |
| R9 | **内存泄漏** | 中 | 低 | 低 | DashMap + TTL 双重限制 |

---

## 里程碑

| 里程碑 | Phase | 预计完成 | 可交付成果 |
|--------|-------|----------|-----------|
| **M1: 基建完成** | Phase 1 | Day 8 | 管道架构可运行、协议适配器通过测试 |
| **M2: 省钱网关** | Phase 2-3 | Day 23 | 压缩 + 缓存 + 路由 + 降级 |
| **M3: 可靠网关** | Phase 4 | Day 30 | 熔断器 + 排队 + RAG |
| **M4: 可观测网关** | Phase 5 | Day 39 | 指标 + 面板 + 安全 |
| **M5: 智能网关** | Phase 6-7 | Day 50 | 投机 + 投票 + 后处理 |
| **M6: 生态就绪** | Phase 8 | Day 55 | 插件 + Webhook + 多租户 |

---

## 里程碑依赖关系图

```
Day 0   ─── Phase 1 基建 ──────────────────────────────────
                     │
Day 8   ─── M1 基建完成 ◀───────────────────────────────────
                     │
Day 9   ─── Phase 2 成本节省 ───────────── Phase 3 智能路由
                     │                           │
Day 23  ─── M2 省钱网关 ◀────────────────────────┘
                     │
Day 24  ─── Phase 4 可靠性 ──────────────── Phase 5 可观测
                     │                           │
Day 30  ─── M3 可靠网关 ◀─────────────────────┘
                     │
Day 31                                    ─── Phase 5 可观测
                                                     │
Day 39  ─── M4 可观测网关 ◀───────────────────────────┘
                     │
Day 40  ─── Phase 6 智能层 ──────────────── Phase 7 优化
                     │                           │
Day 50  ─── M5 智能网关 ◀────────────────────────┘
                     │
Day 51  ─── Phase 8 生态 ───────────────────────────────────
                     │
Day 55  ─── M6 生态就绪 ◀───────────────────────────────────
```

---

## 附录：各 Phase 工时汇总

| Phase | 内容 | 任务数 | 最低工时 | 最高工时 |
|-------|------|--------|----------|----------|
| 1 | 基础设施（脚手架+管道+适配器+配置） | 30 | 6 天 | 8 天 |
| 2 | 成本节省（压缩+Cache+缓存） | 20 | 6 天 | 8 天 |
| 3 | 智能路由（Fallback+路由+预算） | 15 | 5 天 | 7 天 |
| 4 | 可靠性（熔断+排队+RAG） | 15 | 5 天 | 7 天 |
| 5 | 可观测（指标+面板+安全） | 20 | 7 天 | 9 天 |
| 6 | 智能层（投机+投票） | 8 | 5 天 | 6 天 |
| 7 | 响应+请求优化 | 6 | 4 天 | 5 天 |
| 8 | 生态+高级功能 | 9 | 4 天 | 5 天 |
| **总计** | **全部模块** | **123** | **42 天** | **55 天** |

---

> **文档版本记录**
>
> | 版本 | 日期 | 变更 |
> |------|------|------|
> | 1.0 | 2026-06-04 | 初稿（Python 版） |
> | 2.0 | 2026-06-04 | 完整版：Python 8 Phase |
> | 3.0 | 2026-06-04 | Rust 重写版：独立项目实施计划 |
