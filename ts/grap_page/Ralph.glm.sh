
#!/bin/bash

# Ralph Loop - 后台循环运行脚本
# 每次运行固定时间后自动终止并重启

set -u

# 配置参数
MAX_ITERATIONS=${MAX_ITERATIONS:-50}      # 最大循环次数
RUN_DURATION=${RUN_DURATION:-600}          # 每次运行时长 (秒)，默认 5 分钟
DELAY_BASE=${DELAY_BASE:-600}              # 延迟基础时间 (秒)
DELAY_VARIANCE=${DELAY_VARIANCE:-301}      # 延迟随机范围 (秒)

# 环境变量配置
export ANTHROPIC_AUTH_TOKEN=2cdc9755e8554b7d81d9c64741ca6e66.AQ5gwB1UCLFMSQlk
export ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=65536

# 清理函数
cleanup() {
    if [ -n "${CLAUDE_PID:-}" ] && kill -0 "$CLAUDE_PID" 2>/dev/null; then
        echo "正在终止 claude 进程 (PID: $CLAUDE_PID)..."
        kill -TERM "$CLAUDE_PID" 2>/dev/null
        sleep 2
        # 如果进程还在，强制终止
        if kill -0 "$CLAUDE_PID" 2>/dev/null; then
            kill -9 "$CLAUDE_PID" 2>/dev/null
        fi
    fi
}

# 注册退出清理
trap cleanup EXIT INT TERM

count=0
echo "Ralph Loop 启动 - 最大循环次数：$MAX_ITERATIONS, 每次运行时长：${RUN_DURATION}秒"

while [ $count -lt $MAX_ITERATIONS ]; do
    count=$((count + 1))
    echo "=========================================="
    echo "第 $count 次循环开始 ($(date '+%Y-%m-%d %H:%M:%S'))"
    echo "=========================================="

    # 后台启动 claude
    cat PROMPT.md | claude --dangerously-skip-permissions --model glm-4.7 --continue &
    CLAUDE_PID=$!
    echo "Claude 已启动 (PID: $CLAUDE_PID)"

    # 等待固定运行时长
    echo "等待 ${RUN_DURATION} 秒后终止进程..."
    sleep "$RUN_DURATION"

    # 终止进程
    cleanup

    # 随机延迟后重启
    delay=$(( DELAY_BASE + RANDOM % DELAY_VARIANCE ))
    echo "等待 ${delay} 秒后重启..."
    sleep "$delay"
done

echo "Ralph Loop 已完成 $MAX_ITERATIONS 次循环"
