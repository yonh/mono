
count=0

export ANTHROPIC_AUTH_TOKEN=sk-sp-c3c3273aac4348338203194792610e2f
export ANTHROPIC_BASE_URL=https://coding.dashscope.aliyuncs.com/apps/anthropic
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_MAX_OUTPUT_TOKENS=65536

while [ $count -lt 10 ]; do
    #echo "Loop iteration $count"
    count=$((count + 1))
    cat PROMPT.md | claude --dangerously-skip-permissions --model qwen3.5-plus --continue
done
