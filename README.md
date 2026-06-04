# 星渡 (Xingdu)

> LLM API Gateway with Protocol Conversion, Semantic Cache & RAG

星渡是一个高性能 LLM API 网关，支持协议转换（OpenAI ↔ Anthropic ↔ 自定义）、三层缓存架构（精确缓存 + 前缀缓存 + 语义缓存）、星枢 RAG 集成、多后端成本路由和可观测性。

---

## Features

- **协议转换** — 在 OpenAI、Anthropic、DashScope 等 API 格式间透明转换
- **三层缓存** — 精确匹配缓存 / 前缀匹配缓存 / 向量语义缓存（基于内容哈希与余弦相似度）
- **星枢 RAG** — 集成星枢（StarHub）记忆系统，自动注入相关上下文
- **多后端路由** — 成本感知路由，根据 Token 预算自动选择廉价/昂贵模型
- **安全** — API Key 认证、IP 白名单、速率限制、熔断器
- **可观测性** — 结构化日志、Prometheus 指标、SQLite 持久化、审计日志
- **自动重试与 Fallback** — 支持重试链和降级策略
- **Dashboard** — 内置 Web 管理界面

---

## Quick Start

### Prerequisites

- Rust 1.75+
- (可选) Redis — 用于分布式缓存
- (可选) 星枢服务 — 用于 RAG 增强

### Build

```bash
git clone https://github.com/YOUR_USERNAME/xingdu
cd xingdu
cargo build --release
```

### Configure

复制 `.env.example` 为 `.env`，按需修改：

```bash
cp .env.example .env
# 编辑 .env 配置后端 API Key 和模型
```

### Run

```bash
cargo run --release
# 或直接运行编译好的二进制
./target/release/xingdu
```

默认监听 `0.0.0.0:9999`。

---

## Environment Variables

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `XINGDU_HOST` | `0.0.0.0` | 监听地址 |
| `XINGDU_PORT` | `9999` | 监听端口 |
| `XINGDU_BACKEND_NAME` | `dashscope` | 后端名称（dashscope / openai / anthropic） |
| `XINGDU_BACKEND_URL` | — | 后端 API URL |
| `XINGDU_BACKEND_API_KEY` | — | 后端 API Key |
| `XINGDU_BACKEND_MODEL` | — | 模型名称 |
| `XINGDU_RESP_CACHE` | `1` | 启用响应缓存 |
| `XINGDU_RESP_CACHE_TTL` | `21600` | 缓存 TTL（秒） |
| `XINGDU_REDIS_URL` | — | Redis 连接串（空=使用内存缓存） |
| `XINGDU_TOOL_COMPRESSION` | `0` | 启用工具压缩 |
| `XINGDU_PROMPT_CACHE` | `0` | 启用 Prompt 缓存 |
| `XINGDU_STARHUB_ENABLED` | `0` | 启用星枢 RAG |
| `XINGDU_STARHUB_URL` | `http://localhost:26670` | 星枢服务地址 |
| `XINGDU_STARHUB_LIMIT` | `5` | RAG 返回结果数 |
| `XINGDU_STARHUB_TIMEOUT` | `10` | RAG 请求超时（秒） |
| `XINGDU_COST_ROUTING` | `0` | 启用成本路由 |
| `XINGDU_CHEAP_MODEL` | — | 廉价模型 |
| `XINGDU_EXPENSIVE_MODEL` | — | 昂贵模型 |
| `XINGDU_TOKEN_BUDGET` | `0` | Token 预算（0=不限） |
| `XINGDU_FALLBACK_ENABLED` | `0` | 启用 Fallback 链 |
| `XINGDU_AUTH_ENABLED` | `0` | 启用 API Key 认证 |
| `XINGDU_API_KEYS` | — | 允许的 API Key 列表 |
| `XINGDU_IP_WHITELIST` | — | IP 白名单 |
| `XINGDU_RATE_LIMIT` | `0` | 速率限制（请求/秒） |
| `XINGDU_CIRCUIT_BREAKER_THRESHOLD` | `5` | 熔断阈值 |
| `XINGDU_CIRCUIT_BREAKER_RECOVERY` | `60` | 熔断恢复时间（秒） |
| `XINGDU_METRICS_ENABLED` | `0` | 启用指标收集 |
| `XINGDU_AUDIT_LOG` | `0` | 启用审计日志 |
| `XINGDU_DASHBOARD_ENABLED` | `0` | 启用 Dashboard |
| `XINGDU_DASHBOARD_PORT` | `9998` | Dashboard 端口 |

---

## Architecture

```
┌─────────────┐     ┌─────────────────────────────────────────┐
│  客户端      │     │             星渡 (Xingdu)               │
│ (OpenAI SDK) │────▶│                                         │
└─────────────┘     │  ┌─────────┐  ┌──────────────────────┐  │
                    │  │ 路由器   │──▶  协议转换层          │  │
                    │  │(Auth/   │  │  (OpenAI↔Anthropic   │  │
                    │  │ Rate    │  │   ↔DashScope)        │  │
                    │  │ Limit)  │  └──────────┬───────────┘  │
                    │  └────┬────┘             │              │
                    │       │                  ▼              │
                    │  ┌────┴──────────────────────────┐      │
                    │  │        缓存层                   │      │
                    │  │  ┌──────┐ ┌──────┐ ┌──────┐   │      │
                    │  │  │精确  │ │前缀  │ │语义  │   │      │
                    │  │  │缓存  │ │缓存  │ │缓存  │   │      │
                    │  │  └──────┘ └──────┘ └──────┘   │      │
                    │  └──────────────┬─────────────────┘      │
                    │                 ▼                        │
                    │  ┌────────────────────────────┐          │
                    │  │   后端请求层                │          │
                    │  │   (重试 / Fallback / 熔断) │          │
                    │  └────────┬───────────────────┘          │
                    └───────────┼──────────────────────────────┘
                                │
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
          ┌──────────┐   ┌──────────┐   ┌──────────┐
          │ DashScope│   │  OpenAI  │   │ Anthropic│
          │ (阿里云) │   │          │   │          │
          └──────────┘   └──────────┘   └──────────┘

                ┌──────────────────┐
                │   星枢 StarHub   │
                │   (RAG 记忆系统) │
                └──────────────────┘
```

---

## Cache Strategy

### 精确缓存 (Exact Match)

请求体（messages + tools + model）的 SHA-256 哈希完全匹配时返回缓存结果。适用于完全相同的请求重复调用。

### 前缀缓存 (Prefix Match)

根据用户消息的前 N 条计算哈希，匹配前缀相同的请求。适用于同一对话上下文的连续调用。

### 语义缓存 (Semantic Cache)

将用户消息嵌入为向量（通过内容哈希的余弦相似度近似），命中相似度阈值（默认 0.95）时返回缓存结果。适用于语义相似的请求。

缓存存储支持 **内存**（`dashmap`，默认 max_entries=500）和 **Redis** 两种后端。

---

## Dependencies

- **Rust** 1.75+
- **运行时**: Tokio (async runtime), Axum (HTTP framework)
- **缓存**: DashMap (内存), Redis (可选)
- **HTTP 客户端**: reqwest (rustls-tls)
- **序列化**: serde / serde_json
- **可观测性**: tracing / tracing-subscriber

---

## License

MIT