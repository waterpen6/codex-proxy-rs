# v3.26.1

## 修复与改进

- OpenAI Responses 的 HTTP/SSE 与 WebSocket 即时转发前导事件和压缩进度，移除等待后续输出的暂存，避免上游已有进度却迟迟无法到达客户端；关联 [#405](https://github.com/zyycn/codex-proxy-rs/issues/405)
- 未启用中间件链且仅交付可替换前导时，保留已有的有界重试；修复 WebSocket 先收到响应元数据后，连接寿命限制错误未进入恢复流程的问题
- 管理端 API 请求超时固定为 120 秒，不再读取构建变量 `VITE_API_TIMEOUT_MS`

## 使用说明

- 本版本不调整既有心跳频率和默认空闲超时；SSE 注释与 WebSocket Ping/Pong 不延长官方 Codex 的事件等待期限，上游长时间没有新事件时仍可能超时
- 正文、工具活动、压缩进度或未知事件交付后，网关不再透明重放；中间件链不启用可替换前导的重试例外
