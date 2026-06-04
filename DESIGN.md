# 星渡 (XingDu) Rust 版架构设计文档

> 版本: 3.0 (Rust 重写)  
> 日期: 2026-06-04  
> 状态: 草案评审  
> 技术栈: Rust + tokio + axum + reqwest

---

## 目录

1. [系统概述](#1-系统概述)
2. [整体架构](#2-整体架构)
3. [模块设计](#3-模块设计)
   - 3.1 协议适配器
   - 3.2 中间件管道
   - 3.3 工具压缩
   - 3.4 响应缓存
   - 3.5 成本路由器
   - 3.6 多模型降级
   - 3.7 星枢 RAG 集成
   - 3.8 指标收集
   - 3.9 熔断器
   - 3.10 配置中心
   - 3.11 Web 管理面板
   - 3.12 审计日志
   - 3.13 插件系统
   - 3.14 安全层
4. [数据流](#4-数据流)
5. [错误处理策略](#5-错误处理策略)
6. [并发模型](#6-并发模型)
7. [参考 ll-vpn 设计模式](#7-参考-ll-vpn-设计模式)
8. [向后兼容策略](#8-向后兼容策略)

---

## 1. 系统概述

### 1.1 星渡是什么

星渡是一个 **LLM API 网关/代理**，用 Rust 重写以获得：
- 更低延迟（消除 Python GIL 和解释器开销）
- 更高吞吐（异步 I/O + 零拷贝）
- 更小内存占用（无 Python 运行时）
- 更强可靠性（所有权系统防止数据竞争）

### 1.2 核心定位

```
星渡 = LLM 世界的 nginx + kubernetes + prometheus

管调度、管网络、管监控、管安全、管成本。
所有 AI 流量都经过它，所有优化都在它身上做，所有模型都通过它调度。
```

### 1.3 与 ll-vpn 的关系

| 项目 | 定位 | 关系 |
|------|------|------|
| ll-vpn | 去中心化 VPN | 独立项目 |
| 星渡 | LLM API 网关 | 独立项目 |

**参考 ll-vpn 的设计模式，不合并代码：**
- 中间件管道 → 参考 ll-vpn 的命令分发模式
- 配置管理 → 参考 ll-vpn 的环境变量读取方式
- 错误处理 → anyhow + thiserror（同 ll-vpn）
- 异步模式 → tokio（同 ll-vpn）

---

## 2. 整体架构

### 2.1 系统架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        客户端 (Client)                                │
│              OpenAI /v1/chat/completions 协议                         │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    星渡 Gateway (Rust)                                │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    axum HTTP Server                          │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌──────────────┐ │   │
│  │  │ 路由器  │→ │ 安全层  │→ │ 管道引擎 │→ │ 协议适配器   │ │   │
│  │  │ Router  │  │ Auth    │  │Pipeline │  │ Adapter      │ │   │
│  │  └─────────┘  └─────────┘  └─────────┘  └──────────────┘ │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    中间件管道 (Pipeline)                      │   │
│  │                                                             │   │
│  │  Request Pipeline:                                          │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │   │
│  │  │ 星枢 │→│ 压缩 │→│Cache │→│截断 │→│路由  │→│预算  │ │   │
│  │  │ RAG  │ │Head  │ │对齐  │ │      │ │Cost  │ │Token │ │   │
│  │  └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ └──────┘ │   │
│  │                                                             │   │
│  │  Response Pipeline:                                         │   │
│  │  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                    │   │
│  │  │缓存  │→│指标  │→│审计  │→│后处理│                    │   │
│  │  │写入  │ │收集  │ │日志  │ │      │                    │   │
│  │  └──────┘ └──────┘ └──────┘ └──────┘                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    可靠性层                                   │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │   │
│  │  │ 熔断器   │  │ 请求排队  │  │ 多模型   │                  │   │
│  │  │Circuit   │  │ Queue    │  │ Fallback │                  │   │
│  │  │Breaker   │  │          │  │          │                  │   │
│  │  └──────────┘  └──────────┘  └──────────┘                  │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    可观测层                                   │   │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  │   │
│  │  │ 指标收集  │  │ Web 面板  │  │ 审计日志  │  │ 告警     │  │   │
│  │  │ Metrics  │  │Dashboard │  │ Audit    │  │ Alerting │  │   │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘  │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    配置中心 (Config)                          │   │
│  │  环境变量 → Config struct → Arc<RwLock<Config>>              │   │
│  │  60+ 配置项，支持热重载                                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    后端 (Backends)                                    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ DashScope│  │ MiniMax  │  │ DeepSeek │  │ 未来扩展  │          │
│  │(Anthropic│  │(Anthropic│  │(OpenAI   │  │          │          │
│  │ 协议)    │  │ 协议)    │  │ 协议)    │  │          │          │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘          │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 模块依赖关系图

```
                    ┌─────────────┐
                    │  main.rs    │
                    │  入口 + CLI  │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   config    │ ← 所有模块依赖
                    │  配置中心    │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──────┐ ┌──▼────┐ ┌────▼─────┐
       │   server    │ │client │ │ pipeline │
       │  HTTP 服务  │ │HTTP   │ │ 管道引擎  │
       └──────┬──────┘ │请求   │ └────┬─────┘
              │         └───────┘      │
              │                    ┌───▼────────┐
              │                    │ middleware  │
              │                    │  各中间件    │
              │                    └───┬────────┘
              │                        │
       ┌──────▼──────┐          ┌─────▼────────┐
       │   adapter   │          │  reliability  │
       │  协议适配器  │          │  熔断/排队     │
       └─────────────┘          └──────────────┘
```

---

## 3. 模块设计

### 3.1 协议适配器 (adapter)

#### 职责
将 OpenAI 格式请求转换为后端协议格式（Anthropic/OpenAI 直通），并将后端响应转换回 OpenAI 格式。

#### 设计模式

```rust
// src/adapter/mod.rs

/// 协议类型枚举
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum Protocol {
    OpenAI,      // 直通，不转换
    Anthropic,   // O→A→O 转换
}

/// 协议适配器 trait
#[async_trait]
pub trait Adapter: Send + Sync {
    /// 将 OpenAI 请求转换为后端格式
    async fn request_to_backend(
        &self,
        request: &OpenAIRequest,
        backend: &BackendConfig,
    ) -> Result<BackendRequest, AdapterError>;

    /// 将后端响应转换为 OpenAI 格式
    async fn response_to_client(
        &self,
        response: BackendResponse,
        model: &str,
    ) -> Result<OpenAIResponse, AdapterError>;

    /// 将 SSE 流式事件转换为 OpenAI 格式
    fn stream_event_to_client(
        &self,
        event: BackendStreamEvent,
    ) -> Option<OpenAIStreamEvent>;
}

/// Anthropic 适配器
pub struct AnthropicAdapter;

/// OpenAI 直通适配器
pub struct OpenAiAdapter;

impl Adapter for AnthropicAdapter { ... }
impl Adapter for OpenAiAdapter { ... }
```

#### 文件结构

```
src/adapter/
├── mod.rs              # Adapter trait + Protocol 枚举
├── anthropic.rs        # Anthropic 协议转换
├── openai.rs           # OpenAI 直通
├── types.rs            # 请求/响应数据结构
└── error.rs            # 适配器错误类型
```

#### 关键数据结构

```rust
// src/adapter/types.rs

/// OpenAI 格式请求（客户端永远发这个）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenAIRequest {
    pub model: String,
    pub messages: Vec<OpenAIMessage>,
    pub temperature: Option<f64>,
    pub top_p: Option<f64>,
    pub max_tokens: Option<u32>,
    pub stream: Option<bool>,
    pub tools: Option<Vec<Value>>,
    pub tool_choice: Option<Value>,
}

/// OpenAI 格式消息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenAIMessage {
    pub role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<Vec<Value>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_call_id: Option<String>,
}

/// 后端请求（各协议不同）
pub enum BackendRequest {
    OpenAI(Value),
    Anthropic(Value),
}

/// 后端响应
pub enum BackendResponse {
    OpenAI(Value),
    Anthropic(Value),
}
```

---

### 3.2 中间件管道 (pipeline)

#### 职责
提供可插拔的请求/响应处理链，所有优化模块都作为中间件运行。

#### 设计模式（参考 ll-vpn 命令分发）

```rust
// src/pipeline/mod.rs

use std::sync::Arc;
use tokio::sync::RwLock;

/// 请求上下文（可变，中间件可修改）
#[derive(Debug, Clone)]
pub struct RequestContext {
    pub request: OpenAIRequest,
    pub backend: BackendConfig,
    pub adapter: Arc<dyn Adapter>,
    pub extensions: HashMap<String, Value>,  // 中间件间传递数据
    pub errors: Vec<MiddlewareError>,         // 收集错误但不中断
    pub skip_upstream: bool,                  // 标记跳过上游（如缓存命中）
}

/// 响应上下文
#[derive(Debug, Clone)]
pub struct ResponseContext {
    pub response: OpenAIResponse,
    pub latency_ms: u64,
    pub status_code: u16,
    pub extensions: HashMap<String, Value>,
}

/// 中间件 trait（参考 ll-vpn 的命令分发模式）
#[async_trait]
pub trait Middleware: Send + Sync {
    /// 中间件名称（用于日志和调试）
    fn name(&self) -> &str;

    /// 处理请求（转发前）
    async fn process_request(&self, ctx: &mut RequestContext) -> Result<(), MiddlewareError>;

    /// 处理响应（转发后）
    async fn process_response(&self, ctx: &mut ResponseContext) -> Result<(), MiddlewareError>;

    /// 是否启用（基于配置）
    fn is_enabled(&self, config: &Config) -> bool;
}

/// 管道引擎
pub struct Pipeline {
    request_middlewares: Vec<Arc<dyn Middleware>>,
    response_middlewares: Vec<Arc<dyn Middleware>>,
}

impl Pipeline {
    /// 执行请求管道
    pub async fn execute_request(&self, ctx: &mut RequestContext) -> Result<(), PipelineError> {
        for mw in &self.request_middlewares {
            if !mw.is_enabled(&ctx.config) {
                continue;
            }
            match mw.process_request(ctx).await {
                Ok(()) => {}
                Err(e) => {
                    tracing::warn!(middleware = mw.name(), error = %e, "middleware error, continuing");
                    ctx.errors.push(e);
                }
            }
        }
        Ok(())
    }

    /// 执行响应管道
    pub async fn execute_response(&self, ctx: &mut ResponseContext) -> Result<(), PipelineError> {
        for mw in &self.response_middlewares {
            match mw.process_response(ctx).await {
                Ok(()) => {}
                Err(e) => {
                    tracing::warn!(middleware = mw.name(), error = %e, "middleware error, continuing");
                }
            }
        }
        Ok(())
    }
}
```

#### 管道顺序

```
请求入站 → [鉴权] → [限流] → [星枢 RAG] → [工具压缩] → [Cache 对齐]
→ [消息合并] → [截断] → [Token 预算] → [成本路由] → 转发后端
→ [熔断器检查] → [Fallback]

响应出站 → [缓存写入] → [指标收集] → [审计日志] → [后处理] → 返回客户端
```

#### 文件结构

```
src/pipeline/
├── mod.rs              # Pipeline + RequestContext + ResponseContext
├── middleware.rs        # Middleware trait 定义
└── error.rs            # 管道错误类型
```

---

### 3.3 工具压缩 (middleware/headroom)

#### 职责
拦截 `tool_result` 类型的消息，对工具调用的输出进行智能压缩。

#### 压缩策略

```rust
pub struct ToolCompressionMiddleware;

impl Middleware for ToolCompressionMiddleware {
    async fn process_request(&self, ctx: &mut RequestContext) -> Result<(), MiddlewareError> {
        for msg in &mut ctx.request.messages {
            if is_tool_result(msg) {
                let content = extract_content(msg);
                if content.len() > self.min_chars {
                    let compressed = compress(&content, self.strategy);
                    replace_content(msg, &compressed);
                }
            }
        }
        Ok(())
    }
}

/// 压缩策略
enum CompressionStrategy {
    JsonFlatten,     // JSON 扁平化：去冗余 key，数组转表格
    TextTruncate,    // 文本截断：保留首尾 20%
    CodeSimplify,    // 代码简化：去注释，合并空行
    Smart,           // 自动检测内容类型
}
```

#### 压缩流程

```
遍历 messages:
  role == "tool" 或 content.type == "tool_result"
    → 检测内容类型 (JSON / Code / Text)
    → 选择压缩策略
    → 执行压缩（不超过 MIN_CHARS 阈值跳过）
    → 替换原始 content
```

#### 环境变量

```
XINGDU_TOOL_COMPRESSION=0      # 0=关闭, 1=智能压缩
XINGDU_TOOL_COMPRESSION_MIN=500  # 超过此字符数才压缩
```

---

### 3.4 响应缓存 (middleware/cache)

#### 职责
对完全相同的请求直接返回缓存的响应，避免重复调用 LLM API。

#### 缓存 Key 设计

```rust
use sha2::{Sha256, Digest};

fn compute_cache_key(request: &OpenAIRequest) -> String {
    let mut hasher = Sha256::new();
    hasher.update(request.model.as_bytes());
    hasher.update(b"\0");
    hasher.update(serde_json::to_string(&request.messages).unwrap().as_bytes());
    hasher.update(b"\0");
    hasher.update(serde_json::to_string(&request.temperature).unwrap().as_bytes());
    hasher.update(b"\0");
    hasher.update(serde_json::to_string(&request.tools).unwrap().as_bytes());
    format!("{:x}", hasher.finalize())
}
```

#### 缓存存储

```
Phase 1: 进程内 HashMap + TTL（tokio::sync::RwLock<HashMap<String, CacheEntry>>）
Phase 2: 可选 Redis（通过 XINGDU_REDIS_URL 配置）
```

#### 环境变量

```
XINGDU_RESP_CACHE=0              # 0=关闭, 1=进程内, 2=Redis
XINGDU_RESP_CACHE_TTL=300        # 缓存 TTL（秒）
XINGDU_REDIS_URL=                # Redis URL
```

---

### 3.5 成本路由器 (middleware/cost_routing)

#### 职责
根据请求复杂度自动选择不同成本的模型。

#### 路由逻辑

```rust
pub struct CostRoutingMiddleware;

impl CostRoutingMiddleware {
    fn classify_complexity(&self, request: &OpenAIRequest) -> Complexity {
        let total_chars: usize = request.messages.iter()
            .map(|m| content_length(m))
            .sum();

        let has_tools = request.tools.is_some() && !request.tools.as_ref().unwrap().is_empty();

        if has_tools || total_chars > 8000 {
            Complexity::High
        } else if total_chars < 800 {
            Complexity::Low
        } else {
            Complexity::Medium
        }
    }
}

enum Complexity {
    Low,      // → 便宜模型
    Medium,   // → 主模型
    High,     // → 主模型
}
```

#### 环境变量

```
XINGDU_COST_ROUTING=0            # 0=关闭, 1=规则
XINGDU_CHEAP_MODEL=qwen-turbo
XINGDU_EXPENSIVE_MODEL=qwen3.6-plus
XINGDU_COST_ROUTING_THRESHOLD=5
```

---

### 3.6 多模型降级 (middleware/fallback)

#### 职责
主模型失败时自动按 fallback 链依次尝试。

#### 设计

```rust
pub struct FallbackMiddleware {
    fallback_chain: Vec<BackendConfig>,
    retry_codes: HashSet<u16>,
    timeout: Duration,
}

impl FallbackMiddleware {
    async fn execute_with_fallback(&self, request: &OpenAIRequest) -> Result<OpenAIResponse, FallbackError> {
        let mut last_error = None;

        // 尝试主模型
        match self.try_backend(request, &self.primary_backend).await {
            Ok(resp) => return Ok(resp),
            Err(e) if self.should_fallback(&e) => {
                last_error = Some(e);
            }
            Err(e) => return Err(e),
        }

        // 依次尝试 fallback
        for backend in &self.fallback_chain {
            match self.try_backend(request, backend).await {
                Ok(resp) => return Ok(resp),
                Err(e) => {
                    last_error = Some(e);
                    continue;
                }
            }
        }

        Err(last_error.unwrap())
    }
}
```

#### 环境变量

```
XINGDU_FALLBACK_ENABLED=0        # 0=关闭, 1=启用
XINGDU_FALLBACK_CHAIN=qwen3.6,qwen-plus,MiniMax-M3
XINGDU_FALLBACK_TIMEOUT=30
XINGDU_FALLBACK_RETRY_CODES=429,500,502,503
```

---

### 3.7 星枢 RAG 集成 (middleware/starhub)

#### 职责
在转发前调用星枢向量搜索，将相关知识注入 system prompt。

#### 设计

```rust
pub struct StarhubMiddleware {
    client: reqwest::Client,
    url: String,
    limit: usize,
    timeout: Duration,
}

impl Middleware for StarhubMiddleware {
    async fn process_request(&self, ctx: &mut RequestContext) -> Result<(), MiddlewareError> {
        let query = extract_search_query(&ctx.request.messages)?;

        let results = match self.search(&query).await {
            Ok(r) => r,
            Err(_) => return Ok(()),  // 静默降级
        };

        if !results.is_empty() {
            inject_rag_context(&mut ctx.request, &results);
        }

        Ok(())
    }
}
```

#### 环境变量

```
XINGDU_STARHUB_ENABLED=0
XINGDU_STARHUB_URL=http://localhost:26670/search
XINGDU_STARHUB_LIMIT=5
XINGDU_STARHUB_TIMEOUT=2
XINGDU_STARHUB_MIN_QUERY_LEN=10
```

---

### 3.8 指标收集 (metrics)

#### 职责
实时采集和聚合所有运营指标。

#### 设计

```rust
use std::sync::atomic::{AtomicU64, AtomicI64, Ordering};
use std::sync::Arc;

/// 指标收集器（零开销设计：原子操作）
pub struct MetricsCollector {
    total_requests: AtomicU64,
    total_tokens_input: AtomicU64,
    total_tokens_output: AtomicU64,
    total_cost_cents: AtomicI64,  // 以分为单位
    error_count: AtomicU64,
    cache_hits: AtomicU64,
    cache_misses: AtomicU64,
    fallback_count: AtomicU64,
}

impl MetricsCollector {
    pub fn record_request(&self, model: &str, tokens_in: u64, tokens_out: u64, cost: f64, latency_ms: u64) {
        self.total_requests.fetch_add(1, Ordering::Relaxed);
        self.total_tokens_input.fetch_add(tokens_in, Ordering::Relaxed);
        self.total_tokens_output.fetch_add(tokens_out, Ordering::Relaxed);
        self.total_cost_cents.fetch_add((cost * 100.0) as i64, Ordering::Relaxed);
        // ... 延迟直方图
    }
}
```

#### 指标类型

| 指标 | 类型 | 说明 |
|------|------|------|
| 请求总数 | Counter | 按模型、后端、时间 |
| Token 消耗 | Counter | 输入/输出/总计 |
| 延迟 | Histogram | 请求耗时分布 |
| 成本 | Counter | 按模型计费 |
| 错误率 | Counter | 按错误类型 |
| 缓存命中率 | Gauge | 实时命中率 |
| Fallback 次数 | Counter | 触发切换次数 |
| 压缩率 | Gauge | 压缩前后对比 |

#### 环境变量

```
XINGDU_METRICS_ENABLED=0
XINGDU_METRICS_SQLITE_PATH=/tmp/xingdu_metrics.db
```

---

### 3.9 熔断器 (middleware/circuit_breaker)

#### 职责
后端连续失败时自动断开，定期探活恢复。

#### 状态机

```
正常 (Closed)
  │ 连续失败 N 次
  ▼
断开 (Open) ──→ 快速失败（返回 503）
  │ 定期探活（每 30s）
  ▼
半开 (Half-Open)
  │ 探活成功 → Closed
  │ 探活失败 → Open
  ▼
恢复 (Closed)
```

#### 设计

```rust
use std::sync::Arc;
use tokio::sync::RwLock;
use std::collections::HashMap;

pub struct CircuitBreakerMiddleware {
    breakers: Arc<RwLock<HashMap<String, CircuitBreaker>>>,
    threshold: u32,
    recovery_interval: Duration,
}

struct CircuitBreaker {
    state: CircuitState,
    failure_count: u32,
    last_failure: Instant,
}

enum CircuitState {
    Closed,
    Open { opened_at: Instant },
    HalfOpen,
}
```

#### 环境变量

```
XINGDU_CIRCUIT_BREAKER_THRESHOLD=5   # 0=禁用
XINGDU_CIRCUIT_BREAKER_RECOVERY=30
```

---

### 3.10 配置中心 (config)

#### 职责
统一管理所有环境变量配置，支持热重载。

#### 设计

```rust
use std::env;

/// 全局配置（Arc<RwLock<Config>> 共享）
#[derive(Debug, Clone)]
pub struct Config {
    // --- 基础 ---
    pub host: String,
    pub port: u16,
    pub dump_dir: String,
    pub max_messages: usize,
    pub auto_retry: bool,
    pub auto_retry_max: u32,

    // --- 工具压缩 ---
    pub tool_compression: u8,
    pub tool_compression_min: usize,

    // --- Prompt Cache ---
    pub prompt_cache: bool,

    // --- 响应缓存 ---
    pub resp_cache: u8,
    pub resp_cache_ttl: u64,
    pub redis_url: String,

    // --- 星枢 ---
    pub starhub_enabled: bool,
    pub starhub_url: String,
    pub starhub_limit: usize,
    pub starhub_timeout: u64,

    // --- 成本路由 ---
    pub cost_routing: u8,
    pub cheap_model: String,
    pub expensive_model: String,

    // --- Token 预算 ---
    pub token_budget: u8,

    // --- Fallback ---
    pub fallback_enabled: bool,
    pub fallback_chain: Vec<String>,
    pub fallback_timeout: u64,

    // --- 熔断器 ---
    pub circuit_breaker_threshold: u32,
    pub circuit_breaker_recovery: u64,

    // --- 安全 ---
    pub auth_enabled: bool,
    pub api_keys: Vec<String>,
    pub ip_whitelist: Vec<String>,
    pub rate_limit: u32,

    // --- 指标 ---
    pub metrics_enabled: bool,

    // --- 审计 ---
    pub audit_log: bool,

    // --- Web 面板 ---
    pub dashboard_enabled: bool,

    // ... 60+ 配置项
}

impl Config {
    /// 从环境变量加载配置
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

    /// 热重载（从环境变量重新读取）
    pub async fn reload(config: Arc<RwLock<Config>>) {
        let new = Config::from_env();
        let mut guard = config.write().await;
        *guard = new;
        tracing::info!("config reloaded");
    }
}
```

#### 环境变量命名规范

```
所有变量使用 XINGDU_* 前缀
布尔值：0/1 或 true/false
数值：直接字符串解析
列表：逗号分隔
```

---

### 3.11 Web 管理面板 (dashboard)

#### 职责
提供实时仪表盘，可视化运营数据。

#### 设计

```
axum 路由：
  GET  /dashboard           → 重定向到 /dashboard/
  GET  /dashboard/          → 仪表盘主页
  GET  /dashboard/api/stats → 实时统计 JSON
  GET  /dashboard/api/cost  → 成本数据 JSON
  GET  /dashboard/api/logs  → 请求日志 JSON
```

#### 技术方案

```
后端：axum 路由 + JSON API
前端：内嵌 HTML + Tailwind CSS + Chart.js (CDN)
静态文件：include_str! 宏编译进二进制（零部署）
```

#### 环境变量

```
XINGDU_DASHBOARD_ENABLED=0
XINGDU_DASHBOARD_PORT=19999
```

---

### 3.12 审计日志 (middleware/audit)

#### 职责
完整记录每次请求：时间、IP、模型、Token 数、成本。

#### 设计

```rust
pub struct AuditMiddleware {
    log_path: PathBuf,
}

impl Middleware for AuditMiddleware {
    async fn process_response(&self, ctx: &mut ResponseContext) -> Result<(), MiddlewareError> {
        let entry = AuditEntry {
            timestamp: chrono::Utc::now(),
            request_id: ctx.extensions.get("request_id").cloned(),
            model: ctx.extensions.get("model").cloned(),
            tokens_in: ctx.extensions.get("tokens_in").cloned(),
            tokens_out: ctx.extensions.get("tokens_out").cloned(),
            cost: ctx.extensions.get("cost").cloned(),
            latency_ms: ctx.latency_ms,
            status_code: ctx.status_code,
        };

        // 异步写入文件
        self.write_entry(entry).await?;
        Ok(())
    }
}
```

#### 环境变量

```
XINGDU_AUDIT_LOG=0
XINGDU_AUDIT_LOG_PATH=/tmp/xingdu_audit.log
```

---

### 3.13 插件系统 (plugin)

#### 职责
支持动态加载第三方扩展。

#### 设计（Phase 8，WASM 插件）

```rust
/// 插件接口（WASM 沙箱）
pub trait Plugin: Send + Sync {
    fn name(&self) -> &str;
    fn version(&self) -> &str;
    fn on_request(&self, ctx: &mut RequestContext) -> Result<(), PluginError>;
    fn on_response(&self, ctx: &mut ResponseContext) -> Result<(), PluginError>;
}

/// 插件加载器
pub struct PluginLoader {
    plugins_dir: PathBuf,
    loaded: Vec<Arc<dyn Plugin>>,
}
```

#### 环境变量

```
XINGDU_PLUGINS_ENABLED=0
XINGDU_PLUGINS_DIR=plugins
```

---

### 3.14 安全层 (middleware/auth)

#### 职责
API Key 鉴权、IP 白名单、请求限流、请求签名。

#### 设计

```rust
pub struct AuthMiddleware {
    api_keys: HashSet<String>,
    ip_whitelist: HashSet<String>,
    rate_limiter: RateLimiter,
}

impl Middleware for AuthMiddleware {
    async fn process_request(&self, ctx: &mut RequestContext) -> Result<(), MiddlewareError> {
        // 1. API Key 验证
        let key = extract_bearer_token(&ctx.request)?;
        if !self.api_keys.contains(&key) {
            return Err(MiddlewareError::Unauthorized);
        }

        // 2. IP 白名单
        let client_ip = extract_client_ip(&ctx.request)?;
        if !self.ip_whitelist.is_empty() && !self.ip_whitelist.contains(&client_ip) {
            return Err(MiddlewareError::Forbidden);
        }

        // 3. 限流
        if !self.rate_limiter.allow(&client_ip) {
            return Err(MiddlewareError::TooManyRequests);
        }

        Ok(())
    }
}
```

#### 环境变量

```
XINGDU_AUTH_ENABLED=0
XINGDU_API_KEYS=
XINGDU_IP_WHITELIST=
XINGDU_RATE_LIMIT=0
```

---

## 4. 数据流

### 4.1 非流式请求完整流程

```
Client POST /v1/chat/completions
  │
  ▼
axum Router 匹配
  │
  ▼
┌─────────────────────────┐
│   安全层检查             │
│   Auth → Rate Limit     │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   构建 RequestContext    │
│   解析 OpenAI 格式请求   │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   Request Pipeline       │
│   星枢 RAG → 压缩       │
│   → Cache 对齐           │
│   → 截断 → Token 预算    │
│   → 成本路由             │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   协议适配器转换         │
│   OpenAI → Anthropic    │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   熔断器检查             │
│   → 请求排队             │
│   → reqwest 转发后端     │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   等待后端响应           │
│   (tokio::select!)      │
│   + Fallback 超时重试    │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   协议适配器转换         │
│   Anthropic → OpenAI    │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   Response Pipeline      │
│   缓存写入 → 指标        │
│   → 审计日志             │
└─────────┬───────────────┘
          │
          ▼
Client 收到 OpenAI 格式响应
```

### 4.2 流式请求完整流程

```
Client POST /v1/chat/completions (stream=true)
  │
  ▼
相同的安全层 + Pipeline
  │
  ▼
┌─────────────────────────┐
│   协议适配器转换         │
│   OpenAI → Anthropic    │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   reqwest::Response     │
│   .bytes_stream()       │
│   (异步流式读取)         │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   tokio::sync::mpsc     │
│   channel               │
│   (SSE 事件转换)         │
│   Anthropic → OpenAI    │
└─────────┬───────────────┘
          │
          ▼
┌─────────────────────────┐
│   axum SSE Response     │
│   StreamBody            │
│   (直接流式返回客户端)   │
└─────────────────────────┘
```

---

## 5. 错误处理策略

### 5.1 错误类型层次

```
XingduError (thiserror)
  ├── ConfigError        # 配置解析错误
  ├── AdapterError       # 协议转换错误
  │   ├── InvalidFormat
  │   └── UnsupportedProtocol
  ├── PipelineError      # 管道执行错误
  ├── BackendError       # 后端请求错误
  │   ├── ConnectionFailed
  │   ├── Timeout
  │   ├── RateLimited
  │   └── ServerError
  ├── CacheError         # 缓存操作错误
  ├── MetricsError       # 指标收集错误
  ├── SecurityError      # 安全层错误
  │   ├── Unauthorized
  │   ├── Forbidden
  │   └── TooManyRequests
  └── PluginError        # 插件错误
```

### 5.2 降级策略

```
每个中间件 try包裹:
  Ok → 继续
  Err → 记录日志 + 标记 ctx.errors + 继续（不中断管道）

关键错误（后端失败）:
  → 尝试 Fallback
  → 所有模型失败 → 返回最后一个错误
```

### 5.3 错误返回格式

```rust
// 统一 JSON 错误响应
#[derive(Serialize)]
struct ErrorResponse {
    error: ErrorBody,
}

#[derive(Serialize)]
struct ErrorBody {
    message: String,
    r#type: String,
    code: Option<String>,
}

impl IntoResponse for XingduError {
    fn into_response(self) -> Response {
        let status = match &self {
            XingduError::SecurityError(SecurityError::Unauthorized) => StatusCode::UNAUTHORIZED,
            XingduError::SecurityError(SecurityError::Forbidden) => StatusCode::FORBIDDEN,
            XingduError::SecurityError(SecurityError::TooManyRequests) => StatusCode::TOO_MANY_REQUESTS,
            XingduError::BackendError(BackendError::Timeout) => StatusCode::GATEWAY_TIMEOUT,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        };

        let body = ErrorResponse {
            error: ErrorBody {
                message: self.to_string(),
                r#type: "server_error".into(),
                code: None,
            },
        };

        (status, Json(body)).into_response()
    }
}
```

---

## 6. 并发模型

### 6.1 异步运行时

```rust
// 使用 tokio 多线程运行时
#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() -> anyhow::Result<()> {
    // ...
}
```

### 6.2 共享状态

```
Arc<RwLock<Config>>        → 配置（读多写少）
Arc<MetricsCollector>       → 指标（原子操作）
Arc<RwLock<CircuitBreaker>> → 熔断器状态
Arc<Pipeline>               → 管道（不可变）
Arc<CacheStore>             → 缓存存储
```

### 6.3 连接池

```rust
// reqwest 连接池（复用 TCP 连接）
let client = reqwest::Client::builder()
    .pool_max_idle_per_host(20)
    .pool_idle_timeout(Duration::from_secs(30))
    .timeout(Duration::from_secs(60))
    .build()?;
```

### 6.4 背压控制

```rust
// 请求排队：使用 tokio::sync::Semaphore
let semaphore = Arc::new(Semaphore::new(max_concurrent));

async fn handle_request(semaphore: Arc<Semaphore>) -> Result<Response> {
    let _permit = semaphore.acquire().await?;
    // 处理请求
}
```

---

## 7. 参考 ll-vpn 设计模式

### 7.1 中间件管道 → ll-vpn 命令分发

```
ll-vpn:
  command::execute_cmd(&args, &resolver, &vpn_router)
    → match cmd { "ping" => ..., "nodes" => ..., _ => ... }

星渡:
  pipeline::execute_request(&mut ctx)
    → for mw in middlewares { mw.process_request(&mut ctx) }
```

### 7.2 配置管理 → ll-vpn 环境变量

```
ll-vpn:
  let port = env::var("LL_VPN_PORT").unwrap_or_else(|_| "9877".into());

星渡:
  Config::from_env()
    → 所有 XINGDU_* 环境变量统一读取
```

### 7.3 错误处理 → ll-vpn anyhow

```
ll-vpn:
  use anyhow::{Result, Context};
  fs::read(path).context("failed to read file")?;

星渡:
  use anyhow::{Result, Context};
  reqwest::get(url).await.context("failed to fetch backend")?;
```

### 7.4 异步模式 → ll-vpn tokio

```
ll-vpn:
  tokio::spawn(async move { ... });

星渡:
  tokio::spawn(async move {
      pipeline.execute_request(&mut ctx).await
  });
```

---

## 8. 向后兼容策略

### 8.1 核心原则

1. **所有新增功能默认关闭** —— `XINGDU_*=0` 时行为与原版一致
2. **不修改 API 签名** —— `/v1/chat/completions` 输入输出不变
3. **失败静默降级** —— 中间件异常不阻断主流程
4. **配置向后兼容** —— 环境变量命名与 Python 版一致

### 8.2 降级矩阵

| 模块 | 异常行为 | 降级策略 | 对用户影响 |
|------|----------|----------|------------|
| 星枢 RAG | 超时/连接失败 | 跳过 RAG 注入 | 无 |
| 工具压缩 | 压缩异常 | 返回原文本 | 无 |
| 响应缓存 | 缓存不可用 | 跳过缓存 | 无 |
| 成本路由 | 判断异常 | 走主模型 | 无 |
| Fallback | 所有模型失败 | 返回最后错误 | 最终错误 |
| 熔断器 | 状态异常 | 降级为 Closed | 无 |
| 安全层 | 鉴权异常 | 放行（宽松模式） | 低风险 |

### 8.3 Rust 特有优势

```
所有权系统:
  - 编译期防止数据竞争
  - 无 Python GIL 限制
  - 零成本抽象

类型系统:
  - 所有 API 输入/输出有明确类型
  - 编译期检查配置项拼写
  - 消除运行时类型错误

错误处理:
  - 强制处理所有 Result
  - 不会忘记 try/except
  - 编译器提醒未处理错误
```

---

> **文档版本记录**
>
> | 版本 | 日期 | 变更 |
> |------|------|------|
> | 1.0 | 2026-06-04 | 初稿（Python 版） |
> | 2.0 | 2026-06-04 | 扩展：全功能网关设计 |
> | 3.0 | 2026-06-04 | Rust 重写版本：独立项目架构设计 |
