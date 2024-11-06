#!/bin/bash

# 捕获 SIGINT 信号（Ctrl+C）
trap 'echo -e "\n退出脚本"; exit 0' SIGINT

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
    echo "检测到操作系统: $OS $VERSION"
    return 0
  else
    echo "无法确定操作系统类型"
    return 1
  fi
}

# 函数：安装 Node.js 和 npm
install_nodejs() {
  echo "正在安装 Node.js 和 npm..."
  
  case $OS in
    "centos"|"rhel")
      sudo yum install -y nodejs npm
      ;;
    "ubuntu"|"debian")
      sudo apt-get update
      sudo apt-get install -y nodejs npm
      ;;
    *)
      echo "不支持的操作系统类型: $OS"
      return 1
      ;;
  esac
  
  # 验证安装
  if command_exists node && command_exists npm; then
    echo "Node.js $(node -v) 和 npm $(npm -v) 安装成功"
  else
    echo "Node.js 或 npm 安装失败，请检查系统环境后重试"
    exit 1
  fi
}

# 函数：检查并安装必要的依赖
check_dependencies() {
  echo "检查系统依赖..."
  
  # 检查系统类型
  if ! check_distro; then
    echo "无法确定系统类型，退出脚本"
    exit 1
  fi
  
  # 检查 Node.js 和 npm
  if ! command_exists node || ! command_exists npm; then
    echo "未检测到 Node.js 或 npm 环境"
    read -p "是否安装 Node.js 和 npm？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      install_nodejs
    else
      echo "取消安装，退出脚本"
      exit 1
    fi
  else
    echo "检测到 Node.js $(node -v)"
    echo "检测到 npm $(npm -v)"
  fi
}

# 函数：安装限速脚本
install_speed_script() {
  if [ -f "/xs/speed_limit_v1/install.sh" ]; then
    echo "正在执行限速安装脚本..."
    cd /xs/speed_limit_v1
    chmod +x install.sh
    ./install.sh
  else
    echo "错误: 限速安装脚本不存在 (/xs/speed_limit_v1/install.sh)"
    echo "请确保项目文件已正确上传"
  fi
}

install_speed_limit() {
    # 先检查依赖
    check_dependencies
    
    # 检查是否安装 wget 或 curl
    if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        echo "正在安装 wget..."
        if [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y wget
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y wget
        else
            echo "无法安装 wget，请手动安装"
            exit 1
        fi
    fi

    # 步骤 1: 创建 /xs 目录（如果不存在）
    if [ ! -d "/xs" ]; then
        echo "正在创建 /xs 目录..."
        mkdir -p /xs
        chown -R $USER:$USER /xs
    fi
    
    cd /xs
    
    # 步骤 2: 下载项目
    echo "正在从 GitHub 下载项目..."
    if command -v wget >/dev/null 2>&1; then
        wget https://codeload.github.com/OwlOooo/speed_limit_v1/zip/refs/heads/main -O speed_limit_v1.zip
    else
        curl -L https://codeload.github.com/OwlOooo/speed_limit_v1/zip/refs/heads/main -o speed_limit_v1.zip
    fi

    # 步骤 3: 安装 unzip（如果需要）
    if ! command -v unzip >/dev/null 2>&1; then
        echo "正在安装 unzip..."
        if [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y unzip
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y unzip
        else
            echo "无法安装 unzip，请手动安装"
            exit 1
        fi
    fi

    # 步骤 4: 解压并重命名
    echo "正在解压项目文件..."
    unzip -o speed_limit_v1.zip
    rm -f speed_limit_v1.zip
    
    # 如果已存在 speed_limit_v1 目录，先备份
    if [ -d "speed_limit_v1" ]; then
        echo "备份现有项目..."
        mv speed_limit_v1 speed_limit_v1_backup_$(date +%Y%m%d_%H%M%S)
    fi
    
    mv speed_limit_v1-main speed_limit_v1
    
    # 步骤 5: 安装项目依赖
    echo "正在安装项目依赖..."
    cd speed_limit_v1
    
    # 检查是否安装了 nodejs 和 npm
    if ! command -v node >/dev/null 2>&1; then
        echo "正在安装 Node.js..."
        if [[ -f /etc/debian_version ]]; then
            curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
            apt-get install -y nodejs
        elif [[ -f /etc/redhat-release ]]; then
            curl -fsSL https://rpm.nodesource.com/setup_16.x | bash -
            yum install -y nodejs
        else
            echo "无法安装 Node.js，请手动安装"
            exit 1
        fi
    fi
    
    # 安装项目依赖
    npm install
    
    # 安装限速脚本
   install_speed_script
    
    echo "speed_limit_v1 项目安装完成"
}

# 函数：启动 speed_limit_v1 项目
start_speed_limit() {
  if [ -f /xs/speed_limit_v1/speed_limit_v1.pid ]; then
    pid=$(cat /xs/speed_limit_v1/speed_limit_v1.pid)
    if kill -0 $pid 2>/dev/null; then
      echo "speed_limit_v1 项目已经在运行中 (PID: $pid)."
      return
    fi
  fi
  
  echo "正在启动 speed_limit_v1 项目..."
  setsid nohup node /xs/speed_limit_v1/src/server.js > /xs/speed_limit_v1/output.log 2>&1 < /dev/null &
  echo $! > /xs/speed_limit_v1/speed_limit_v1.pid
  echo "speed_limit_v1 项目已在后台启动，PID: $!"
}

# 函数：显示菜单
show_menu() {
  echo "spl 项目管理菜单:"
  echo "1. 安装 speed_limit_panel"
  echo "2. 启动"
  echo "3. 重启"
  echo "4. 关闭"
  echo "5. 查看实时日志"
  echo "6. 检查环境依赖"
  echo "7. 安装限速脚本"
  echo "按 Ctrl+C 退出脚本"
}

# 函数：查看实时日志
view_logs() {
  echo "显示最后100行的实时日志，按 Ctrl+C 退出..."
  tail -n 100 -f /xs/speed_limit_v1/output.log
}

# 主程序
main() {
  # 检查并存储系统类型
  if ! check_distro; then
    echo "无法确定系统类型，退出脚本"
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
        disown -h $(cat /xs/speed_limit_v1/speed_limit_v1.pid)
        ;;
      3)
        echo "正在重启 speed_limit_v1 项目..."
        if [ -f /xs/speed_limit_v1/speed_limit_v1.pid ]; then
          pid=$(cat /xs/speed_limit_v1/speed_limit_v1.pid)
          if kill -0 $pid 2>/dev/null; then
            kill $pid
            echo "已终止旧的 speed_limit_v1 进程 (PID: $pid)."
          else
            echo "speed_limit_v1 项目未在运行中."
          fi
          rm /xs/speed_limit_v1/speed_limit_v1.pid
        fi
        start_speed_limit
        disown -h $(cat /xs/speed_limit_v1/speed_limit_v1.pid)
        ;;
      4)
        echo "正在关闭 speed_limit_v1 项目..."
        if [ -f /xs/speed_limit_v1/speed_limit_v1.pid ]; then
          pid=$(cat /xs/speed_limit_v1/speed_limit_v1.pid)
          if kill -0 $pid 2>/dev/null; then
            kill $pid
            echo "已终止 speed_limit_v1 进程 (PID: $pid)."
          else
            echo "speed_limit_v1 项目未在运行中."
          fi
          rm /xs/speed_limit_v1/speed_limit_v1.pid
        else
          echo "speed_limit_v1 项目未在运行中."
        fi
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
      *)
        echo "无效的选择，请输入菜单中的数字."
        ;;
    esac
    echo "按回车键返回主菜单..."
    read
  done
}

# 运行主程序
main