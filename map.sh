#!/bin/bash

set -u

# 获取脚本所在目录，确保能找到配置文件
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 错误：未找到配置文件 $CONFIG_FILE"
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

# 可选开关默认值
AUTO_OPEN_BROWSER="${AUTO_OPEN_BROWSER:-true}"
ENABLE_MINI_GAME="${ENABLE_MINI_GAME:-true}"
DEFAULT_REMOTE_PORTS="${DEFAULT_REMOTE_PORTS:-5173}"

is_valid_port() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] || return 1
    (( p >= 1 && p <= 65535 ))
}

is_port_in_use() {
    local p="$1"
    if command -v lsof >/dev/null 2>&1; then
        lsof -ti :"$p" >/dev/null 2>&1
        return $?
    fi
    if command -v fuser >/dev/null 2>&1; then
        fuser "$p"/tcp >/dev/null 2>&1
        return $?
    fi
    return 1
}

is_forbidden_port() {
    local p="$1"
    local blocked
    for blocked in "${FORBIDDEN_PORTS[@]}"; do
        if [ "$p" -eq "$blocked" ]; then
            return 0
        fi
    done
    return 1
}

strip_cr() {
    local v="$1"
    printf "%s" "${v//$'\r'/}"
}

port_exists_in_array() {
    local target="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" = "$target" ]; then
            return 0
        fi
    done
    return 1
}

pick_local_port() {
    local remote_port="$1"
    local candidate="$remote_port"
    while true; do
        if [ "$candidate" -gt 65535 ]; then
            echo "❌ 错误：无法为远程端口 $remote_port 分配可用本地端口。"
            return 1
        fi
        if port_exists_in_array "$candidate" "${MAPPED_LOCAL_PORTS[@]:-}"; then
            candidate=$((candidate + 1))
            continue
        fi
        if is_port_in_use "$candidate"; then
            candidate=$((candidate + 1))
            continue
        fi
        echo "$candidate"
        return 0
    done
}

show_spinner() {
    local msg="$1"
    local rounds="${2:-10}"
    local frames=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
    local i
    for ((i=0; i<rounds; i++)); do
        printf "\r%s %s" "${frames[i % ${#frames[@]}]}" "$msg"
        sleep 0.07
    done
    printf "\r✅ %s\n" "$msg"
}

run_mini_game() {
    [ "$ENABLE_MINI_GAME" = "true" ] || return 0
    echo ""
    echo "🎮 启动迷你字符小游戏：Tunnel Runner"
    local i width pos obstacle line
    width=30
    pos=1
    for ((i=1; i<=20; i++)); do
        obstacle=$(( (RANDOM % (width - 3)) + 2 ))
        line=""
        local j
        for ((j=1; j<=width; j++)); do
            if [ "$j" -eq "$pos" ]; then
                line="${line}🚀"
            elif [ "$j" -eq "$obstacle" ]; then
                line="${line}#"
            else
                line="${line}-"
            fi
        done
        printf "\r[%s]" "$line"
        sleep 0.06
        pos=$((pos + 1))
        if [ "$pos" -gt "$width" ]; then
            pos=1
        fi
    done
    printf "\n🏁 游戏结束：隧道稳定，准备连接。\n\n"
}

ensure_sshpass() {
    if command -v sshpass >/dev/null 2>&1; then
        return 0
    fi

    echo "ℹ️ 未检测到 sshpass，尝试自动安装..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "⚠️ 未检测到 Homebrew，无法自动安装 sshpass。"
        return 1
    fi

    if brew install hudochenkov/sshpass/sshpass; then
        return 0
    fi

    brew install sshpass >/dev/null 2>&1 || true
    command -v sshpass >/dev/null 2>&1
}

# 1. 获取用户输入的端口（支持多组，空格或逗号分隔）
read -r -p "请输入要映射的远程端口（可多组，空格/逗号分隔）[默认 $DEFAULT_REMOTE_PORTS]: " INPUT_PORTS
RAW_PORTS="${INPUT_PORTS:-$DEFAULT_REMOTE_PORTS}"
REMOTE_SSH_PORT="$(strip_cr "${REMOTE_SSH_PORT:-}")"
RAW_PORTS="$(strip_cr "$RAW_PORTS")"

if ! is_valid_port "$REMOTE_SSH_PORT"; then
    echo "❌ 错误：配置中的 REMOTE_SSH_PORT='$REMOTE_SSH_PORT' 非法。"
    exit 1
fi

# 解析端口列表
NORMALIZED_PORTS="${RAW_PORTS//,/ }"
read -r -a REMOTE_PORT_LIST <<< "$NORMALIZED_PORTS"
if [ "${#REMOTE_PORT_LIST[@]}" -eq 0 ]; then
    echo "❌ 错误：未提供有效端口。"
    exit 1
fi

declare -a VALID_REMOTE_PORTS
declare -a MAPPED_LOCAL_PORTS
declare -a LINKS
declare -a SSH_PIDS

# 2. 端口校验 + 动态分配本地端口
for remote_port in "${REMOTE_PORT_LIST[@]}"; do
    remote_port="$(strip_cr "$remote_port")"
    if ! is_valid_port "$remote_port"; then
        echo "❌ 错误：端口 '$remote_port' 非法，请输入 1~65535 的整数。"
        exit 1
    fi
    if is_forbidden_port "$remote_port"; then
        echo "❌ 错误：端口 $remote_port 是受限的危险端口，禁止映射。"
        exit 1
    fi
    if port_exists_in_array "$remote_port" "${VALID_REMOTE_PORTS[@]:-}"; then
        continue
    fi

    local_port="$(pick_local_port "$remote_port")" || exit 1
    VALID_REMOTE_PORTS+=("$remote_port")
    MAPPED_LOCAL_PORTS+=("$local_port")
    LINKS+=("http://localhost:$local_port")
done

# 链接固定显示在最上方（多组）
echo "🌐 本地访问链接（固定）:"
for link in "${LINKS[@]}"; do
    echo "  - $link"
done
echo "============================================================"

show_spinner "校验配置与端口策略"
run_mini_game
show_spinner "建立 SSH 隧道"

cleanup() {
    local pid
    for pid in "${SSH_PIDS[@]:-}"; do
        if kill -0 "$pid" >/dev/null 2>&1; then
            kill "$pid" >/dev/null 2>&1 || true
        fi
    done
    echo ""
    echo "🛑 映射已停止。"
}
trap cleanup INT TERM

USE_SSHPASS=false
if [ -n "${SSH_PASSWORD:-}" ] && ensure_sshpass; then
    USE_SSHPASS=true
    echo "🔑 使用 sshpass 自动输入密码连接。"
else
    echo "🔑 将使用手动输入密码连接。"
fi

for idx in "${!VALID_REMOTE_PORTS[@]}"; do
    remote_port="${VALID_REMOTE_PORTS[$idx]}"
    local_port="${MAPPED_LOCAL_PORTS[$idx]}"
    SSH_CMD=(ssh -N -L "$local_port:localhost:$remote_port" "$REMOTE_USER@$REMOTE_HOST" -p "$REMOTE_SSH_PORT")
    if [ "$USE_SSHPASS" = "true" ]; then
        SSH_CMD=(sshpass -p "$SSH_PASSWORD" "${SSH_CMD[@]}")
    fi
    "${SSH_CMD[@]}" &
    SSH_PIDS+=("$!")
done

sleep 1
for pid in "${SSH_PIDS[@]}"; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
        echo "❌ 有隧道启动失败，请检查账号密码与网络。"
        wait "$pid" || true
        cleanup
        exit 1
    fi
done

if [ "$AUTO_OPEN_BROWSER" = "true" ]; then
    if command -v open >/dev/null 2>&1; then
        for link in "${LINKS[@]}"; do
            open "$link" >/dev/null 2>&1 || true
        done
        echo "🧭 已自动打开浏览器。"
    else
        echo "ℹ️ 当前环境不支持 open 命令，已跳过自动打开。"
    fi
fi

echo "🚀 ${#SSH_PIDS[@]} 组隧道运行中，按 Ctrl + C 结束。"
wait
