#!/bin/bash
################################单网卡脚本########################################
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用root权限运行此脚本${NC}"
    exit 1
fi

# 检测系统类型
check_sys(){
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    else
        echo -e "${RED}未检测到系统版本，请联系脚本作者！${NC}"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    check_sys
    echo -e "${YELLOW}检测到系统为 $release${NC}"
    echo -e "${GREEN}正在安装依赖...${NC}"
    
    case $release in
        'centos')
            yum clean all
            yum makecache
            yum -y install epel-release
            yum -y install iproute iproute-tc net-tools which bc jq
            ;;
        'ubuntu'|'debian')
            apt update
            apt -y install iproute2 net-tools bc jq
            ;;
        *)
            echo -e "${RED}不支持的系统类型${NC}"
            exit 1
            ;;
    esac
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v $cmd >/dev/null 2>&1; then
        echo -e "${YELLOW}命令 $cmd 未安装，正在安装...${NC}"
        install_dependencies
        if ! command -v $cmd >/dev/null 2>&1; then
            echo -e "${RED}命令 $cmd 安装失败${NC}"
            exit 1
        fi
        echo -e "${GREEN}命令 $cmd 安装成功${NC}"
    fi
}

# 检查必需的命令
check_required_commands() {
    local commands=("tc" "ip" "grep" "awk" "sed" "bc" "jq")
    for cmd in "${commands[@]}"; do
        check_command "$cmd"
    done
}

# 检查并安装依赖
check_required_commands

# 检查内核模块
check_kernel_modules() {
    local modules=("ifb" "cls_u32" "sch_htb" "sch_ingress")
    local missing_modules=()
    
    for module in "${modules[@]}"; do
        if ! lsmod | grep -q "^$module"; then
            missing_modules+=($module)
            modprobe $module 2>/dev/null
        fi
    done
    
    if [ ${#missing_modules[@]} -ne 0 ]; then
        echo -e "${YELLOW}正在加载内核模块: ${missing_modules[*]}${NC}"
        case $release in
            'centos')
                yum -y install kernel-modules-extra
                ;;
            'ubuntu'|'debian')
                apt -y install linux-modules-extra-$(uname -r)
                ;;
        esac
        
        for module in "${missing_modules[@]}"; do
            modprobe $module
            if ! lsmod | grep -q "^$module"; then
                echo -e "${RED}无法加载内核模块: $module${NC}"
                exit 1
            fi
        done
    fi
}

# 检查内核模块
check_kernel_modules

# 配置目录和文件
CONFIG_DIR="/xs/speed_limit_v1/data"
CONFIG_FILE="$CONFIG_DIR/port.json"

# 确保配置目录存在
mkdir -p $CONFIG_DIR

# 初始化配置文件
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[]" > "$CONFIG_FILE"
    fi
}

# 初始化配置
init_config

# 获取网卡名称
INTERFACE=$(ip route | grep default | awk '{print $5}')
if [ -z "$INTERFACE" ]; then
    echo -e "${RED}无法检测到网卡，请手动指定${NC}"
    exit 1
fi

# 检查端口是否存在
check_port_exists() {
    local PORT=$1
    if [ -f "$CONFIG_FILE" ]; then
        jq -e ".[] | select(.port == \"$PORT\")" "$CONFIG_FILE" > /dev/null
        return $?
    fi
    return 1
}

# 更新端口配置
update_port_config() {
    local PORT=$1
    local DOWNLOAD=$2
    local UPLOAD=$3
    local NAME=$4
    
    local TMP_FILE=$(mktemp)
    
    if check_port_exists "$PORT"; then
        # 更新现有端口配置
        jq --arg port "$PORT" \
           --arg down "$DOWNLOAD" \
           --arg up "$UPLOAD" \
           --arg name "$NAME" \
           'map(if .port == $port then {name: $name, port: $port, download: $down, upload: $up} else . end)' \
           "$CONFIG_FILE" > "$TMP_FILE"
    else
        # 添加新端口配置
        jq --arg port "$PORT" \
           --arg down "$DOWNLOAD" \
           --arg up "$UPLOAD" \
           --arg name "$NAME" \
           '. + [{name: $name, port: $port, download: $down, upload: $up}]' \
           "$CONFIG_FILE" > "$TMP_FILE"
    fi
    
    mv "$TMP_FILE" "$CONFIG_FILE"
}
# 初始化TC
init_tc() {
    # 清理现有规则
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    
    # 加载 ifb 模块
    modprobe ifb
    ip link set dev ifb0 up 2>/dev/null || {
        ip link add ifb0 type ifb
        ip link set dev ifb0 up
    }
    tc qdisc del dev ifb0 root 2>/dev/null
    
    # 创建根队列
    tc qdisc add dev $INTERFACE root handle 1: htb default 999
    tc class add dev $INTERFACE parent 1: classid 1:999 htb rate 1000mbit
    
    tc qdisc add dev ifb0 root handle 1: htb default 999
    tc class add dev ifb0 parent 1: classid 1:999 htb rate 1000mbit
    
    # 设置入站重定向
    tc qdisc add dev $INTERFACE handle ffff: ingress
    tc filter add dev $INTERFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
}
# 添加在init_tc函数后面
# 清理并重新应用所有规则
reload_all_rules() {
    echo -e "${GREEN}开始重新加载所有规则...${NC}"
    
    # 清理所有规则
    echo -e "${YELLOW}清理现有规则...${NC}"
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    tc qdisc del dev ifb0 root 2>/dev/null
    
    # 初始化TC
    init_tc
    
    # 读取并应用所有配置
    if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ] && [ "$(cat "$CONFIG_FILE")" != "[]" ]; then
        echo -e "${YELLOW}应用端口限速规则...${NC}"
        while IFS= read -r line; do
            local port=$(echo $line | jq -r '.port')
            local download=$(echo $line | jq -r '.download')
            local upload=$(echo $line | jq -r '.upload')
            local name=$(echo $line | jq -r '.name')
            
            # 下载限速
            local DOWNLOAD_KBPS=$((download * 1024))
            local CLASS_ID=${port: -4}
            tc class add dev $INTERFACE parent 1: classid 1:$CLASS_ID htb rate ${DOWNLOAD_KBPS}kbit ceil ${DOWNLOAD_KBPS}kbit burst 15k
            tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport $port 0xffff flowid 1:$CLASS_ID
            
            # 上传限速
            local UPLOAD_KBPS=$((upload * 1024))
            tc class add dev ifb0 parent 1: classid 1:$CLASS_ID htb rate ${UPLOAD_KBPS}kbit ceil ${UPLOAD_KBPS}kbit burst 15k
            tc filter add dev ifb0 parent 1: protocol ip prio 1 u32 match ip dport $port 0xffff flowid 1:$CLASS_ID
            
            echo -e "${GREEN}已设置端口 $port($name) - 下载: ${download}Mbps, 上传: ${upload}Mbps${NC}"
        done < <(jq -c '.[]' "$CONFIG_FILE")
        echo -e "${GREEN}所有规则加载完成${NC}"
    else
        echo -e "${YELLOW}配置文件为空，未应用任何规则${NC}"
    fi
}

# 添加限速规则
add_limit() {
    local PORT=$1
    local DOWNLOAD=$2
    local UPLOAD=$3
    local NAME=$4
    local CLASS_ID=${PORT: -4}
    
    # 检查参数
    if [ -z "$PORT" ] || [ -z "$DOWNLOAD" ] || [ -z "$UPLOAD" ] || [ -z "$NAME" ]; then
        echo -e "${RED}参数不完整！用法: xs add <端口> <下载速度> <上传速度> <名称>${NC}"
        return 1
    fi
    
    # 下载限速
    local DOWNLOAD_KBPS=$((DOWNLOAD * 1024))
    tc class add dev $INTERFACE parent 1: classid 1:$CLASS_ID htb rate ${DOWNLOAD_KBPS}kbit ceil ${DOWNLOAD_KBPS}kbit burst 15k
    tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport $PORT 0xffff flowid 1:$CLASS_ID
    
    # 上传限速
    local UPLOAD_KBPS=$((UPLOAD * 1024))
    tc class add dev ifb0 parent 1: classid 1:$CLASS_ID htb rate ${UPLOAD_KBPS}kbit ceil ${UPLOAD_KBPS}kbit burst 15k
    tc filter add dev ifb0 parent 1: protocol ip prio 1 u32 match ip dport $PORT 0xffff flowid 1:$CLASS_ID
    
    # 更新配置文件
    update_port_config "$PORT" "$DOWNLOAD" "$UPLOAD" "$NAME"
    
    if check_port_exists "$PORT"; then
        echo -e "${GREEN}端口 $PORT($NAME) 限速规则已更新：下载 ${DOWNLOAD}Mbps，上传 ${UPLOAD}Mbps${NC}"
    else
        echo -e "${GREEN}端口 $PORT($NAME) 限速规则已添加：下载 ${DOWNLOAD}Mbps，上传 ${UPLOAD}Mbps${NC}"
    fi
    
    # 重启服务以确保规则生效
    systemctl restart xs-limit
}

# 删除限速规则
remove_limit() {
    local PORT=$1
    local CLASS_ID=${PORT: -4}
    
    if ! check_port_exists "$PORT"; then
        echo -e "${YELLOW}端口 $PORT 不存在${NC}"
        return 1
    fi
    
    tc filter del dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip sport $PORT 0xffff 2>/dev/null
    tc filter del dev ifb0 parent 1: protocol ip prio 1 u32 match ip dport $PORT 0xffff 2>/dev/null
    tc class del dev $INTERFACE parent 1: classid 1:$CLASS_ID 2>/dev/null
    tc class del dev ifb0 parent 1: classid 1:$CLASS_ID 2>/dev/null
    
    # 从JSON中删除
    local TMP_FILE=$(mktemp)
    jq --arg port "$PORT" 'map(select(.port != $port))' "$CONFIG_FILE" > "$TMP_FILE"
    mv "$TMP_FILE" "$CONFIG_FILE"
    
    echo -e "${GREEN}端口 $PORT 的限速规则已删除${NC}"
    
    systemctl restart xs-limit
}

# 显示单个端口限速信息
show_port() {
    local PORT=$1
    if [ -f "$CONFIG_FILE" ]; then
        local PORT_INFO=$(jq -r ".[] | select(.port == \"$PORT\")" "$CONFIG_FILE")
        if [ ! -z "$PORT_INFO" ]; then
            local NAME=$(echo "$PORT_INFO" | jq -r '.name')
            local DOWNLOAD=$(echo "$PORT_INFO" | jq -r '.download')
            local UPLOAD=$(echo "$PORT_INFO" | jq -r '.upload')
            
            echo -e "\n端口信息:"
            echo "===================="
            echo -e "名称: ${BLUE}${NAME}${NC}"
            echo -e "端口: ${BLUE}${PORT}${NC}"
            echo -e "下载限速: ${BLUE}${DOWNLOAD}${NC} Mbps"
            echo -e "上传限速: ${BLUE}${UPLOAD}${NC} Mbps"
           
        else
            echo -e "${YELLOW}端口 $PORT 没有限速规则${NC}"
        fi
    fi
}

# 显示所有端口限速信息
# 添加紫色定义
PURPLE='\033[0;35m'

show_all() {
    if [ -f "$CONFIG_FILE" ] && [ -s "$CONFIG_FILE" ] && [ "$(cat "$CONFIG_FILE")" != "[]" ]; then
        echo -e "\n${PURPLE}当前限速规则：${NC}"
        echo -e "${PURPLE}=================================================================${NC}"
        echo -e "${PURPLE}名称\t\t端口\t\t下载(Mbps)\t上传(Mbps)${NC}"
        echo -e "${PURPLE}=================================================================${NC}"
        while IFS= read -r line; do
            echo -e "${PURPLE}$line${NC}"
        done < <(jq -r '.[] | "\(.name)\t\t\(.port)\t\t\(.download)\t\t\(.upload)"' "$CONFIG_FILE")
        echo -e "${PURPLE}=================================================================${NC}"
    else
        echo -e "${YELLOW}没有限速规则${NC}"
    fi
}
# 监控服务资源使用
monitor_resources() {
    clear
    echo -e "${BLUE}正在监控限速服务资源使用情况...${NC}"
    echo -e "${YELLOW}按 Ctrl+C 退出监控${NC}\n"

    # 获取服务PID
    local SERVICE_PID=$(pgrep -f "xs-limit-service")
    if [ -z "$SERVICE_PID" ]; then
        echo -e "${RED}限速服务未运行！${NC}"
        return 1
    fi

    HEADER_PRINTED=0

    while true; do
        # 获取当前时间
        local DATETIME=$(date "+%Y-%m-%d %H:%M:%S")
        
        # 获取CPU使用率
        local CPU_USAGE=$(ps -p $SERVICE_PID -o %cpu --no-headers)
        
        # 获取内存使用
        local MEM_USAGE=$(ps -p $SERVICE_PID -o rss --no-headers)
        # 转换为MB
        MEM_USAGE=$(echo "scale=2; $MEM_USAGE/1024" | bc)
        
        # 获取系统负载
        local LOAD=$(cat /proc/loadavg | awk '{print $1,$2,$3}')
        
        # 获取网络统计
        local NETWORK_STATS=$(ifconfig $INTERFACE | grep "RX packets\|TX packets")
        
        # 获取tc规则数量
        local TC_RULES=$(tc -s qdisc show | wc -l)
        
        # 每20行打印一次表头
        if [ $HEADER_PRINTED -eq 0 ]; then
            echo "================================================================================"
            printf "%-20s %-10s %-15s %-20s %-10s\n" "时间" "CPU%" "内存(MB)" "系统负载" "TC规则数"
            echo "================================================================================"
            HEADER_PRINTED=0
        fi

        # 打印状态行
        printf "%-20s %-10.1f %-15.2f %-20s %-10s\n" \
            "$DATETIME" \
            "$CPU_USAGE" \
            "$MEM_USAGE" \
            "$LOAD" \
            "$TC_RULES"

        # 每10行显示网络统计
        if [ $((HEADER_PRINTED % 10)) -eq 0 ]; then
            echo -e "\n网络统计:"
            echo "$NETWORK_STATS"
            echo -e "\nTC类统计:"
            tc -s class show dev $INTERFACE | grep -E "class|Sent"
            tc -s class show dev ifb0 | grep -E "class|Sent"
            echo "--------------------------------------------------------------------------------"
        fi

        HEADER_PRINTED=$((HEADER_PRINTED + 1))
        if [ $HEADER_PRINTED -ge 20 ]; then
            HEADER_PRINTED=0
        fi

        sleep 1
    done
}

# 添加详细的TC统计信息
show_tc_stats() {
    echo -e "\n${BLUE}TC详细统计信息:${NC}"
    echo "================================================================================"
    echo -e "${YELLOW}下载限速统计(物理网卡):${NC}"
    tc -s qdisc show dev $INTERFACE
    tc -s class show dev $INTERFACE
    tc -s filter show dev $INTERFACE

    echo -e "\n${YELLOW}上传限速统计(IFB设备):${NC}"
    tc -s qdisc show dev ifb0
    tc -s class show dev ifb0
    tc -s filter show dev ifb0
}
# 查询实际限速规则
show_active_rules() {
    echo -e "\n${PURPLE}解析当前活动的限速规则：${NC}"
    echo -e "${PURPLE}=================================================================${NC}"
    echo -e "${PURPLE}端口\t\t下载限速\t上传限速\t当前使用量${NC}"
    echo -e "${PURPLE}----------------------------------------------------------------${NC}"

    # 获取所有 class 信息（排除默认类1:999）
    local class_info=$(tc class show dev $INTERFACE | grep "htb" | grep -v "1:999")
    if [ -z "$class_info" ]; then
        echo -e "${YELLOW}当前没有活动的限速规则${NC}"
        return
    fi

    # 逐行处理每个 class
    echo "$class_info" | while read -r line; do
        local class_id=$(echo "$line" | awk '{print $3}')
        
        # 从class_id中提取ID部分（去掉1:）
        local id=${class_id#1:}
        
        # 获取下载限速值（当前 class）
        local down_rate=$(echo "$line" | grep -o "rate [0-9]*Kbit" | awk '{print $2}' | sed 's/Kbit//')
        local down_mbps=$(echo "scale=2; $down_rate/1024" | bc)
        
        # 获取上传限速值（从ifb0设备）
        local up_class=$(tc class show dev ifb0 | grep "1:$id")
        local up_rate=$(echo "$up_class" | grep -o "rate [0-9]*Kbit" | awk '{print $2}' | sed 's/Kbit//')
        local up_mbps=$(echo "scale=2; $up_rate/1024" | bc)
        
        # 获取端口号（从filter规则）
        local filter_info=$(tc filter show dev $INTERFACE | grep -A1 "flowid $class_id" | grep "match")
        local port=""
        if [[ $filter_info =~ match[[:space:]]([0-9a-fA-F]{4})0000/ffff0000[[:space:]]at[[:space:]]20 ]]; then
            port=$(printf "%d" "0x${BASH_REMATCH[1]}")
        fi

        # 获取流量统计
        local down_stats=$(tc -s class show dev $INTERFACE | grep -A1 "htb 1:$id" | grep "Sent")
        local down_bytes=$(echo "$down_stats" | awk '{print $2}')
        local down_mb=$(echo "scale=2; $down_bytes/1024/1024" | bc)
        
        local up_stats=$(tc -s class show dev ifb0 | grep -A1 "htb 1:$id" | grep "Sent")
        local up_bytes=$(echo "$up_stats" | awk '{print $2}')
        local up_mb=$(echo "scale=2; $up_bytes/1024/1024" | bc)

        if [ ! -z "$port" ]; then
            printf "${PURPLE}%-8s\t%-8s\t%-8s\t↓%.2fMB ↑%.2fMB${NC}\n" \
                "$port" "${down_mbps}Mbps" "${up_mbps}Mbps" "$down_mb" "$up_mb"
        fi
    done
    echo -e "${PURPLE}----------------------------------------------------------------${NC}"
    
    # 显示系统总流量
    echo -e "\n${PURPLE}系统总流量统计：${NC}"
    local total_down=$(tc -s qdisc show dev $INTERFACE | grep "Sent" | head -1 | awk '{printf "%.2f", $2/1024/1024}')
    local total_up=$(tc -s qdisc show dev ifb0 | grep "Sent" | head -1 | awk '{printf "%.2f", $2/1024/1024}')
    echo -e "${PURPLE}总下行流量：${total_down} MB${NC}"
    echo -e "${PURPLE}总上行流量：${total_up} MB${NC}"
}
# 清除所有限速规则但保留配置
clear_rules() {
    echo -e "${YELLOW}正在清除所有限速规则...${NC}"
    
    # 清除TC规则
    tc qdisc del dev $INTERFACE root 2>/dev/null
    tc qdisc del dev $INTERFACE ingress 2>/dev/null
    tc qdisc del dev ifb0 root 2>/dev/null
    
    # 重新初始化TC
    init_tc
    
    echo -e "${GREEN}所有限速规则已清除，配置文件保留${NC}"
}

# 显示菜单
show_menu() {
    echo -e "\n${BLUE}限速管理工具${NC}"
    echo "1. 添加限速规则"
    echo "2. 查看单个端口限速"
    echo "3. 查看所有限速规则"
    echo "4. 删除单个端口限速"
    echo "5. 删除所有限速规则(删除配置文件以及限速规则)"
    echo "6. 查看服务状态"
    echo "7. 重启限速服务"
    echo "8. 监控服务资源"
    echo "9. 查看TC详细统计"
    echo "10. 查看实际限速规则"
    echo "11. 清除所有规则(保留配置)"
    echo "12. 退出"
}

# 命令行参数处理
case "$1" in
    "add")
        if [ $# -eq 5 ]; then
            add_limit "$2" "$3" "$4" "$5"
        else
            echo "用法: xs add <端口> <下载速度> <上传速度> <名称>"
        fi
        exit 0
        ;;
    "show")
        if [ $# -eq 2 ]; then
            show_port "$2"
        else
            show_all
        fi
        exit 0
        ;;
     "active")
        show_active_rules
        exit 0
        ;;
    "remove")
        if [ $# -eq 2 ]; then
            remove_limit "$2"
        else
            echo "用法: xs remove <端口>"
        fi
        exit 0
        ;;
    "remove-all")
        echo "[]" > "$CONFIG_FILE"
        init_tc
        systemctl restart xs-limit
        exit 0
        ;;        
    "restart")
        reload_all_rules
        echo "限速服务已重启,已加载最新配置并应用"
        exit 0
        ;;
    "monitor")
        monitor_resources
        exit 0
        ;;
    "stats")
        show_tc_stats
        exit 0
        ;;
    "clear")
        clear_rules
        exit 0
        ;;
esac

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [1-11]: " choice
    
    case $choice in
        1)
            read -p "请输入限速信息(格式: 端口 下载速度 上传速度 名称): " port down up name
            if [[ ! -z "$port" && ! -z "$down" && ! -z "$up" && ! -z "$name" ]]; then
                add_limit "$port" "$down" "$up" "$name"
            else
                echo -e "${RED}输入格式错误${NC}"
            fi
            ;;
        2)
            read -p "请输入要查看的端口: " port
            show_port "$port"
            ;;
        3)
            show_all
            ;;
        4)
            read -p "请输入要删除限速的端口: " port
            remove_limit "$port"
            ;;
        5)
            read -p "确认要删除所有限速规则吗？(y/n): " confirm
            if [ "$confirm" = "y" ]; then
                echo "[]" > "$CONFIG_FILE"
                init_tc
                systemctl restart xs-limit
                echo -e "${GREEN}所有限速规则和配置文件已删除${NC}"
            fi
            ;;
        6)
            systemctl status xs-limit
            ;;
        7)
            reload_all_rules
            echo -e "${GREEN}限速服务已重启,已加载最新配置并应用${NC}"
            systemctl status xs-limit
            ;;
        8)
            monitor_resources
            ;;
        9)
            show_tc_stats
            ;;
        10)
            show_active_rules
            ;;
        11)
            clear_rules
            ;;
        12)
            echo "退出程序"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的选择${NC}"
            ;;
    esac
done