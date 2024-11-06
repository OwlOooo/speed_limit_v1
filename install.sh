#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用root权限运行此脚本${NC}"
    exit 1
fi

# 清理旧安装
cleanup_old_install() {
    echo -e "${YELLOW}检查并清理旧安装...${NC}"
    
    # 停止并删除服务
    if systemctl is-active xs-limit >/dev/null 2>&1; then
        echo "停止xs-limit服务..."
        systemctl stop xs-limit
    fi
    
    if systemctl is-enabled xs-limit >/dev/null 2>&1; then
        echo "禁用xs-limit服务..."
        systemctl disable xs-limit
    fi
    
    # 删除服务文件
    if [ -f "/etc/systemd/system/xs-limit.service" ]; then
        echo "删除服务文件..."
        rm -f /etc/systemd/system/xs-limit.service
        systemctl daemon-reload
    fi
    
    # 删除脚本和配置文件
    echo "删除旧脚本和配置文件..."
    rm -f /usr/local/bin/xs
    rm -f /usr/local/xs/speed_limit.sh  # 添加这行
    rm -f /usr/local/xs/xs-limit-service
    rm -rf /usr/local/xs               # 删除整个目录
    
   
    
    echo -e "${GREEN}清理完成${NC}"
}

# 检查并清理旧安装
cleanup_old_install

echo -e "${GREEN}开始新安装...${NC}"

# 创建目录结构
mkdir -p /usr/local/xs
mkdir -p /xs/speed_limit_v1/data

# 检查速度限制脚本是否存在
if [ ! -f "speed_limit.sh" ]; then
    echo -e "${RED}错误: speed_limit.sh 文件不存在${NC}"
    exit 1
fi

# 复制主脚本到安装目录
cp speed_limit.sh /usr/local/xs/speed_limit.sh
chmod +x /usr/local/xs/speed_limit.sh

# 创建命令行工具
cat > /usr/local/bin/xs << 'EOF'
#!/bin/bash

# 函数：显示使用方法
show_usage() {
    echo "用法："
    echo "xs add <端口> <下载速度> <上传速度> <名称>  - 添加或更新端口限速"
    echo "xs delete <端口>                           - 删除指定端口限速"
    echo "xs show [端口]                            - 显示所有或指定端口限速"
    echo "xs clear                                  - 清除所有限速规则"
    echo "xs restart                                - 重启限速服务"
    echo "xs status                                 - 查看服务状态"
    echo "xs monitor                                - 监控资源使用"
    echo "xs stats                                  - 查看详细统计"
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then 
    echo -e "\033[0;31m请使用root权限运行此命令\033[0m"
    exit 1
fi

# 检查参数
if [ $# -eq 0 ]; then
    /usr/local/xs/speed_limit.sh
    exit 0
fi

case "$1" in
    "add")
        if [ $# -eq 5 ]; then
            /usr/local/xs/speed_limit.sh add "$2" "$3" "$4" "$5"
        else
            echo "用法: xs add <端口> <下载速度> <上传速度> <名称>"
        fi
        ;;
    "delete")
        if [ $# -eq 2 ]; then
            /usr/local/xs/speed_limit.sh remove "$2"
        else
            echo "用法: xs delete <端口>"
        fi
        ;;
  "delete-all")
        /usr/local/xs/speed_limit.sh remove-all
        ;;       
    "show")
        if [ $# -eq 2 ]; then
            /usr/local/xs/speed_limit.sh show "$2"
        else
            /usr/local/xs/speed_limit.sh show
        fi
        ;;
    "clear")
        /usr/local/xs/speed_limit.sh clear
        ;;
    "restart")
        /usr/local/xs/speed_limit.sh restart
        ;;
    "status")
        systemctl status xs-limit
        ;;
    "monitor")
        /usr/local/xs/speed_limit.sh monitor
        ;;
    "stats")
        /usr/local/xs/speed_limit.sh stats
        ;;
    "help"|"-h"|"--help")
        show_usage
        ;;
    *)
        echo "未知命令: $1"
        show_usage
        exit 1
        ;;
esac
EOF

# 设置执行权限
chmod +x /usr/local/bin/xs

# 创建系统服务执行脚本
cat > /usr/local/xs/xs-limit-service << 'EOF'
#!/bin/bash

# 配置文件路径
CONFIG_FILE="/xs/speed_limit_v1/data/port.json"
SCRIPT="/usr/local/xs/speed_limit.sh"

# 初始化服务
echo "初始化限速服务..."
$SCRIPT restart

# 保持服务运行
while true; do
    sleep infinity
done
EOF

chmod +x /usr/local/xs/xs-limit-service

# 创建系统服务
cat > /etc/systemd/system/xs-limit.service << EOF
[Unit]
Description=XS Speed Limit Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/xs/xs-limit-service
Restart=always
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 重新加载服务配置
systemctl daemon-reload

# 启动并设置开机自启
systemctl enable xs-limit
systemctl start xs-limit

echo -e "${GREEN}安装完成！${NC}"
echo "使用方法："
echo "xs add <端口> <下载速度> <上传速度> <名称>  - 添加或更新端口限速"
echo "xs delete <端口>                           - 删除指定端口限速"
echo "xs show [端口]                            - 显示所有或指定端口限速"
echo "xs clear                                  - 清除所有限速规则"
echo "xs restart                                - 重启限速服务"
echo "xs status                                 - 查看服务状态"
echo "xs monitor                                - 监控资源使用"
echo "xs stats                                  - 查看详细统计"

# 显示服务状态
systemctl status xs-limit