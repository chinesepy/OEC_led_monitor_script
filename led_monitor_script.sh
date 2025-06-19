#!/bin/bash

# LED控制脚本
# 功能：根据系统状态控制三色LED指示灯

# LED设备路径
RED_LED="/sys/class/leds/red-led/brightness"
GREEN_LED="/sys/class/leds/green-led/brightness"
BLUE_LED="/sys/class/leds/blue-led/brightness"

# 配置参数
DISK_THRESHOLD=90          # 磁盘使用率阈值（%）
MEMORY_THRESHOLD=90        # 内存使用率阈值（%）
CPU_LOAD_THRESHOLD=4.0     # CPU负载阈值
CPU_TEMP_THRESHOLD=80      # CPU温度阈值（°C）
CHECK_INTERVAL=10          # 检查间隔（秒）
NIGHT_START="21:30"        # 夜间关灯开始时间
NIGHT_END="06:30"          # 夜间关灯结束时间

# 日志文件
LOG_FILE="/var/log/led_monitor.log"
LOG_MAX_SIZE=1048576    # 日志文件最大大小（字节，默认1MB）

# 检查并限制日志文件大小
check_log_size() {
    if [ -f "$LOG_FILE" ]; then
        local file_size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        
        if [ "$file_size" -gt "$LOG_MAX_SIZE" ]; then
            # 清空日志文件并写入重置信息
            : > "$LOG_FILE"
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Log file reset (previous size: $((file_size / 1024))KB)" >> "$LOG_FILE"
        fi
    fi
}

# 写入日志函数
log_message() {
    check_log_size
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# LED控制函数
set_led() {
    local red=$1
    local green=$2
    local blue=$3
    
    echo $red > "$RED_LED" 2>/dev/null
    echo $green > "$GREEN_LED" 2>/dev/null
    echo $blue > "$BLUE_LED" 2>/dev/null
}

# 关闭所有LED
led_off() {
    set_led 0 0 0
}

# 蓝色（开机状态）
led_blue() {
    set_led 0 0 1
}

# 绿色（正常联网）
led_green() {
    set_led 0 1 0
}

# 黄色（断网）
led_yellow() {
    set_led 1 1 0
}

# 红色（磁盘空间不足）
led_red() {
    set_led 1 0 0
}

# 品红色（多种问题组合）
led_magenta() {
    set_led 1 0 1
}

# 白色（系统启动）
led_white() {
    set_led 1 1 1
}

# 青色（CPU相关问题）
led_cyan() {
    set_led 0 1 1
}

# 检查网络连接
check_network() {
    # 尝试ping多个服务器确保网络连接
    ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || \
    ping -c 1 -W 3 192.168.1.1 >/dev/null 2>&1 || \
    ping -c 1 -W 3 www.baidu.com >/dev/null 2>&1
}

# 检查CPU温度
check_cpu_temp() {
    local temp_file="/sys/class/thermal/thermal_zone0/temp"
    if [ -f "$temp_file" ]; then
        local temp=$(cat "$temp_file")
        # 转换为摄氏度（通常是毫度）
        temp=$((temp / 1000))
        [ $temp -ge $CPU_TEMP_THRESHOLD ]
    else
        # 如果无法读取温度，返回false
        return 1
    fi
}

# 检查CPU负载
check_cpu_load() {
    local load=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
    # 使用bc进行浮点数比较，如果没有bc则用整数比较
    if command -v bc >/dev/null 2>&1; then
        echo "$load >= $CPU_LOAD_THRESHOLD" | bc -l | grep -q 1
    else
        # 简单的整数比较（取整）
        local load_int=${load%.*}
        local threshold_int=${CPU_LOAD_THRESHOLD%.*}
        [ $load_int -ge $threshold_int ]
    fi
}

# 检查磁盘使用率
check_disk_usage() {
    local usage=$(df / | awk 'NR==2 {print int($5)}')
    [ $usage -ge $DISK_THRESHOLD ]
}

# 检查内存使用率
check_memory_usage() {
    local total=$(free | awk '/^Mem:/ {print $2}')
    local used=$(free | awk '/^Mem:/ {print $3}')
    local usage=$(( used * 100 / total ))
    [ $usage -ge $MEMORY_THRESHOLD ]
}

# 检查是否在夜间时段
is_night_time() {
    local current_time=$(date +%H:%M)
    local night_start=$(date -d "$NIGHT_START" +%H%M)
    local night_end=$(date -d "$NIGHT_END" +%H%M)
    local current_time_num=$(date -d "$current_time" +%H%M)
    
    # 处理跨日情况
    if [ $night_start -gt $night_end ]; then
        # 跨日：21:30 到次日 06:30
        [ $current_time_num -ge $night_start ] || [ $current_time_num -le $night_end ]
    else
        # 同日：不太可能，但防止配置错误
        [ $current_time_num -ge $night_start ] && [ $current_time_num -le $night_end ]
    fi
}

# 获取系统状态并设置相应LED
update_led_status() {
    # 夜间关灯
    if is_night_time; then
        led_off
        return
    fi
    
    # 检查各种状态
    local cpu_temp_high=$(check_cpu_temp && echo "1" || echo "0")
    local cpu_load_high=$(check_cpu_load && echo "1" || echo "0")
    local memory_high=$(check_memory_usage && echo "1" || echo "0")
    local disk_high=$(check_disk_usage && echo "1" || echo "0")
    local network_ok=$(check_network && echo "1" || echo "0")
    
    # 状态优先级判断
    if [ "$cpu_temp_high" = "1" ]; then
        led_red
        log_message "CPU temperature critical (>$CPU_TEMP_THRESHOLD°C) - LED: Red"
    elif [ "$memory_high" = "1" ] && [ "$cpu_load_high" = "1" ]; then
        led_magenta
        log_message "Memory high (>$MEMORY_THRESHOLD%) + CPU load high (>$CPU_LOAD_THRESHOLD) - LED: Magenta"
    elif [ "$cpu_load_high" = "1" ]; then
        led_cyan
        log_message "CPU load high (>$CPU_LOAD_THRESHOLD) - LED: Cyan"
    elif [ "$memory_high" = "1" ]; then
        led_white
        log_message "Memory usage high (>$MEMORY_THRESHOLD%) - LED: White"
    elif [ "$disk_high" = "1" ]; then
        led_yellow
        log_message "Disk usage high (>$DISK_THRESHOLD%) - LED: Yellow"
    elif [ "$network_ok" = "0" ]; then
        led_blue
        log_message "Network disconnected - LED: Blue"
    else
        led_green
        log_message "System normal - LED: Green"
    fi
}

# 初始化：显示蓝色（开机状态）
led_blue
log_message "System boot - LED: Blue"

# 等待网络就绪（最多等待60秒）
echo "Waiting for network connection..."
for i in {1..12}; do
    if check_network; then
        echo "Network connected!"
        break
    fi
    sleep 5
done

# 主循环
echo "LED monitor started. Log file: $LOG_FILE"
while true; do
    update_led_status
    sleep $CHECK_INTERVAL
done