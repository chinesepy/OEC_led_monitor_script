#!/bin/bash

# LED控制脚本 - 优化版
# 功能：根据系统状态控制三色LED指示灯

# 配置参数
LED_PATH="/sys/class/leds"
THRESHOLDS=(90 90 4.0 80)  # 磁盘% 内存% CPU负载 CPU温度°C
CHECK_INTERVAL=30          # 检查间隔（秒）
NIGHT_HOURS="21:30-06:30"  # 夜间关灯时间
LOG_FILE="/var/log/led_monitor.log"
LOG_MAX_SIZE=524288        # 日志文件最大512KB

# 全局变量
LAST_STATUS=""
LAST_LOG_TIME=0
LOG_INTERVAL=300           # 5分钟记录一次日志

# 工具函数
log_msg() {
    local now=$(date +%s)
    local msg="$1"
    
    # 只在状态变化或超过日志间隔时记录
    if [[ "$msg" != "$LAST_STATUS" ]] || (( now - LAST_LOG_TIME > LOG_INTERVAL )); then
        # 检查日志文件大小
        [[ -f "$LOG_FILE" && $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $LOG_MAX_SIZE ]] && > "$LOG_FILE"
        
        echo "$(date '+%m-%d %H:%M:%S') - $msg" >> "$LOG_FILE"
        LAST_LOG_TIME=$now
        LAST_STATUS="$msg"
    fi
}

# LED控制
set_led() { 
    echo $1 > "$LED_PATH/red-led/brightness" 2>/dev/null
    echo $2 > "$LED_PATH/green-led/brightness" 2>/dev/null  
    echo $3 > "$LED_PATH/blue-led/brightness" 2>/dev/null
}

# 系统检查函数 - 返回状态码和详细信息
check_system() {
    # 网络检查（最轻量）
    if ! ping -c1 -W2 8.8.8.8 >/dev/null 2>&1; then
        echo "1:"
        return
    fi
    
    # 磁盘使用率
    disk=$(df / | awk 'NR==2{print int($5)}')
    if (( disk >= ${THRESHOLDS[0]} )); then
        echo "2:$disk"
        return
    fi
    
    # 内存使用率
    mem=$(free | awk '/Mem:/{printf "%.0f", $3/$2*100}')
    if (( mem >= ${THRESHOLDS[1]} )); then
        # 同时检查CPU负载以确定是否为组合状态
        load=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
        if awk "BEGIN{exit !($load >= ${THRESHOLDS[2]})}"; then
            echo "4:$mem,$load"  # 内存+CPU高
        else
            echo "3:$mem"       # 仅内存高
        fi
        return
    fi
    
    # CPU负载检查
    load=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    if awk "BEGIN{exit !($load >= ${THRESHOLDS[2]})}"; then
        echo "5:$load"
        return
    fi
    
    # CPU温度 - 增加合理性检查
    local temp_file="/sys/class/thermal/thermal_zone0/temp"
    if [[ -f "$temp_file" ]]; then
        local temp_raw=$(cat "$temp_file" 2>/dev/null || echo "0")
        temp=$(( temp_raw / 1000 ))
        # 温度合理性检查：0-120°C范围内才有效
        if (( temp > 0 && temp <= 120 && temp >= ${THRESHOLDS[3]} )); then
            echo "6:$temp"
            return
        fi
    fi
    
    # 正常状态
    echo "0:"
}

# 夜间模式检查 - 兼容BusyBox，正确处理跨日逻辑
is_night() {
    local current=$(date +%H%M)
    local start_time="${NIGHT_HOURS%-*}"
    local end_time="${NIGHT_HOURS#*-}"
    
    # 手动解析时间，兼容BusyBox
    local start=$(echo "$start_time" | sed 's/://')
    local end=$(echo "$end_time" | sed 's/://')
    
    # 判断是否跨日
    if (( start > end )); then
        # 跨日情况：如21:30-06:30
        (( current >= start || current <= end ))
    else
        # 同日情况：如22:00-23:00
        (( current >= start && current <= end ))
    fi
}

# 主状态更新
update_status() {
    is_night && { set_led 0 0 0; return; }
    
    # 获取系统状态和详细信息
    local result=$(check_system)
    local status_code="${result%%:*}"
    local details="${result#*:}"
    
    case $status_code in
        0) set_led 0 1 0; log_msg "Normal";;
        1) set_led 0 0 1; log_msg "Network down";;
        2) set_led 1 1 0; log_msg "Disk high(${details}%)";;
        3) set_led 1 1 1; log_msg "Memory high(${details}%)";;
        4) IFS=',' read -r mem_val load_val <<< "$details"
           set_led 1 0 1; log_msg "Memory+CPU high(${mem_val}%,${load_val})";;
        5) set_led 0 1 1; log_msg "CPU load high(${details})";;
        6) set_led 1 0 0; log_msg "CPU temp high(${details}°C)";;
    esac
}

# 主程序
main() {
    # 初始化
    set_led 1 1 1
    log_msg "Boot"
    
    # 等待网络（最多60秒）
    for i in {1..12}; do
        ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && break
        sleep 5
    done
    
    echo "LED monitor started (PID: $$)"
    
    # 主循环
    while true; do
        update_status
        sleep $CHECK_INTERVAL
    done
}

# 信号处理
trap 'set_led 1 1 1; log_msg "Stopped"; exit 0' INT TERM

main "$@"
