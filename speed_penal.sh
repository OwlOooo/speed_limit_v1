#!/bin/bash

# 捕获 SIGINT 信号（Ctrl+C）
trap 'echo -e "\n退出脚本"; exit 0' SIGINT

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 函数：检查命令是否存在
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 函数：检查Linux发行版类型
check_distro() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    echo -e "${GREEN}检测到操作系统: $OS $VERSION${NC}"
    return 0
  else
    echo -e "${RED}无法确定操作系统类型${NC}"
    return 1
  fi
}

# 检查是否已安装
check_existing_installation() {
    if [ -d "/xs/speed_limit_v1" ]]; then
        echo -e "${YELLOW}检测到已存在speed_limit_v1安装${NC}"
        read -p "是否要先卸载已有安装？(y/n): " choice
        case "$choice" in 
            y|Y )
                uninstall_speed_limit
                return 0
                ;;
            n|N )
                echo "安装已取消"
                return 1
                ;;
            * )
                echo "无效的选择，安装已取消"
                return 1
                ;;
        esac
    fi
    return 0
}

# 设置自动启动
setup_autostart() {
    echo "设置开机自动启动..."
    
    # 创建系统服务文件
    cat > /etc/systemd/system/speed-panel.service << EOF
[Unit]
Description=Speed Panel Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/xs/speed_limit_v1
ExecStart=/usr/bin/node /xs/speed_limit_v1/src/server.js
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启用并启动服务
    systemctl enable speed-panel.service
    systemctl start speed-panel.service
    
    echo -e "${GREEN}自动启动服务已设置完成${NC}"
}

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
    rm -f /usr/local/xs/speed_limit.sh
    rm -f /usr/local/xs/xs-limit-service
    rm -rf /usr/local/xs
    
    echo -e "${GREEN}清理完成${NC}"
}

# 函数：安装 Node.js 和 npm
install_nodejs() {
  echo -e "${YELLOW}正在安装 Node.js 和 npm...${NC}"
  
  case $OS in
    "centos"|"rhel")
       yum install -y nodejs npm
      ;;
    "ubuntu"|"debian")
       apt-get update
       apt-get install -y nodejs npm
      ;;
    *)
      echo -e "${RED}不支持的操作系统类型: $OS${NC}"
      return 1
      ;;
  esac
  
  # 验证安装
  if command_exists node && command_exists npm; then
    echo -e "${GREEN}Node.js $(node -v) 和 npm $(npm -v) 安装成功${NC}"
  else
    echo -e "${RED}Node.js 或 npm 安装失败，请检查系统环境后重试${NC}"
    exit 1
  fi
}

# 函数：检查并安装必要的依赖
check_dependencies() {
  echo -e "${YELLOW}检查系统依赖...${NC}"
  
  # 检查系统类型
  if ! check_distro; then
    echo -e "${RED}无法确定系统类型，退出脚本${NC}"
    exit 1
  fi
 
  # 检查 Node.js 和 npm
  if ! command_exists node || ! command_exists npm; then
    echo -e "${YELLOW}未检测到 Node.js 或 npm 环境，开始安装...${NC}"
    install_nodejs
  else
    echo -e "${GREEN}检测到 Node.js $(node -v)${NC}"
    echo -e "${GREEN}检测到 npm $(npm -v)${NC}"
  fi
}

# 卸载功能
uninstall_speed_limit() {
    echo -e "${YELLOW}准备卸载speed_limit_v1...${NC}"
    read -p "确认要卸载吗？这将删除所有相关文件和配置 (y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "卸载已取消"
        return
    fi
    
    # 停止服务
    echo "停止运行中的服务..."
    if [ -f /xs/speed_limit_v1/speed_limit_v1.pid ]; then
        pid=$(cat /xs/speed_limit_v1/speed_limit_v1.pid)
        if kill -0 $pid 2>/dev/null; then
            kill $pid
            echo "已终止speed_limit_v1进程 (PID: $pid)"
        fi
    fi
    
    # 禁用并删除自启动服务
    if systemctl is-active speed-panel >/dev/null 2>&1; then
        echo "停止并禁用自启动服务..."
        systemctl stop speed-panel
        systemctl disable speed-panel
        rm -f /etc/systemd/system/speed-panel.service
        systemctl daemon-reload
    fi
    
    # 删除安装文件
    echo "删除安装文件..."
    rm -f /usr/local/bin/spl
    cleanup_old_install
    
    # 删除主程序文件
    echo "删除程序文件..."
    rm -rf /xs
    
    echo -e "${GREEN}卸载完成${NC}"
}

# 函数：安装限速脚本
install_speed_script() {
  if [ -f "/xs/speed_limit_v1/install.sh" ]; then
    echo -e "${YELLOW}正在执行限速安装脚本...${NC}"
    cd /xs/speed_limit_v1
    chmod +x install.sh
    ./install.sh
  else
    echo -e "${RED}错误: 限速安装脚本不存在 (/xs/speed_limit_v1/install.sh)${NC}"
    echo "请确保项目文件已正确上传"
  fi
}

# 函数：安装speed_limit_v1
install_speed_limit() {
    # 检查已存在安装
    if ! check_existing_installation; then
        return
    fi

    # 先检查依赖
    check_dependencies
    
    # 检查是否安装 wget 或 curl
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}正在安装 wget...${NC}"
        if [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y wget
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y wget
        else
            echo -e "${RED}无法安装 wget，请手动安装${NC}"
            exit 1
        fi
    fi

    # 步骤 1: 创建 /xs 目录（如果不存在）
    if [ ! -d "/xs" ]; then
        echo -e "${YELLOW}正在创建 /xs 目录...${NC}"
        mkdir -p /xs
        chown -R $USER:$USER /xs
    fi
    
    cd /xs
    
    # 步骤 2: 下载项目
   echo -e "${YELLOW}正在从 GitHub 下载项目...${NC}"
  if command -v wget >/dev/null 2>&1; then
      wget https://github.com/OwlOooo/speed_limit_v1/archive/refs/heads/main.zip -O speed_limit_v1.zip
  else
      curl -L https://github.com/OwlOooo/speed_limit_v1/archive/refs/heads/main.zip -o speed_limit_v1.zip
  fi

    # 步骤 3: 安装 unzip（如果需要）
    echo -e "${YELLOW}正在更新 unzip...${NC}"
    if [[ -f /etc/debian_version ]]; then
        apt-get install -y unzip
    elif [[ -f /etc/redhat-release ]]; then
        yum update -y unzip
    else
        echo -e "${RED}无法更新 unzip，请手动更新${NC}"
        exit 1
    fi

    # 步骤 4: 解压并重命名
    echo -e "${YELLOW}正在解压项目文件...${NC}"
    unzip -o speed_limit_v1.zip
    rm -f speed_limit_v1.zip
    
    # 如果已存在 speed_limit_v1 目录，先备份
    if [ -d "speed_limit_v1" ]; then
        echo "备份现有项目..."
        mv speed_limit_v1 speed_limit_v1_backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    mv speed_limit_v1-main speed_limit_v1
    
    # 步骤 5: 安装项目依赖
    echo -e "${YELLOW}正在安装项目依赖...${NC}"
    cd speed_limit_v1
    
    # 安装项目依赖
    npm install
    
    # 安装限速脚本
    install_speed_script
    
    # 设置自动启动
    setup_autostart
    
    echo -e "${GREEN}speed_limit_v1 项目安装完成${NC}"
}

# 函数：启动 speed_limit_v1 项目
start_speed_limit() {
  if systemctl is-active speed-panel >/dev/null 2>&1; then
    echo -e "${YELLOW}speed_limit_v1 项目已经在运行中${NC}"
    return
  fi
  
  echo -e "${YELLOW}正在启动 speed_limit_v1 项目...${NC}"
  systemctl start speed-panel
  echo -e "${GREEN}speed_limit_v1 项目已启动${NC}"
}

# 函数：查看实时日志
view_logs() {
  echo -e "${YELLOW}显示最后100行的实时日志，按 Ctrl+C 退出...${NC}"
  journalctl -u speed-panel -n 100 -f
}
# 函数：修改访问密码
change_password() {
    echo -e "${YELLOW}修改访问密码${NC}"
    
    # 检查配置文件是否存在
    if [ ! -f "/xs/speed_limit_v1/data/config.json" ]; then
        echo -e "${RED}配置文件不存在,请先安装并启动项目${NC}"
        return 1
    fi
    
    # 读取新密码
    read -p "请输入新的访问密码: " new_password
    
    # 验证密码不为空
    if [ -z "$new_password" ]; then
        echo -e "${RED}密码不能为空${NC}"
        return 1
    fi
    
    # 更新配置文件中的密码
    echo "{\"password\":\"$new_password\"}" > /xs/speed_limit_v1/data/config.json
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}密码修改成功${NC}"
        # 重启服务使新密码生效
        systemctl restart speed-panel
        echo -e "${GREEN}服务已重启,新密码生效${NC}"
    else
        echo -e "${RED}密码修改失败${NC}"
        return 1
    fi
}
# 函数：安装TCP加速脚本
install_tcp_script() {
  echo -e "${YELLOW}正在下载并安装TCP加速脚本...${NC}"
  wget --no-check-certificate -O tcp.sh http://www.78idc.cn/tcp.sh && chmod +x tcp.sh && ./tcp.sh
}
# 函数：显示菜单
show_menu() {
  echo -e "${YELLOW}spl 项目管理菜单:${NC}"
  echo "1. 安装 speed_limit_panel"
  echo "2. 启动"
  echo "3. 重启"
  echo "4. 关闭"
  echo "5. 查看实时日志"
  echo "6. 检查环境依赖"
  echo "7. 安装限速脚本"
  echo "8. 修改访问密码"
  echo "9. TCP加速脚本&&更新软件源"
  echo "10. 卸载 speed_limit_panel"
  echo -e "${YELLOW}按 Ctrl+C 退出脚本${NC}"
}

# 主程序
main() {
  # 检查并存储系统类型
  if ! check_distro; then
    echo -e "${RED}无法确定系统类型，退出脚本${NC}"
    exit 1
  fi

  while true; do
    show_menu
    read -p "请选择操作（输入对应数字）: " choice
    case $choice in
      1)
        install_speed_limit
        ;;
      2)
        start_speed_limit
        ;;
      3)
        echo -e "${YELLOW}正在重启 speed_limit_v1 项目...${NC}"
        systemctl restart speed-panel
        echo -e "${GREEN}speed_limit_v1 项目已重启${NC}"
        ;;
      4)
        echo -e "${YELLOW}正在关闭 speed_limit_v1 项目...${NC}"
        systemctl stop speed-panel
        echo -e "${GREEN}speed_limit_v1 项目已关闭${NC}"
        ;;
      5)
        view_logs
        ;;
      6)
        check_dependencies
        ;;
      7)
        install_speed_script
        ;;
      8)
        change_password
        ;;
      9)
        install_tcp_script
        ;;
      10)
        uninstall_speed_limit
        ;;
      *)
        echo -e "${RED}无效的选择，请输入菜单中的数字${NC}"
        ;;
    esac
    echo "按回车键返回主菜单..."
    read
  done
}

# 运行主程序
main