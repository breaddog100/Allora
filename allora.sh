#!/bin/bash

function install_node(){
	# 更新系统
	sudo apt update & sudo apt upgrade -y
	sudo apt install ca-certificates zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev curl git wget make jq build-essential pkg-config lsb-release libssl-dev libreadline-dev libffi-dev gcc screen unzip lz4 -y

	# 安装 Go
    if ! go version >/dev/null 2>&1; then
        sudo rm -rf /usr/local/go
        curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
        source $HOME/.bash_profile
        go version
    fi
	
	# 检查是否安装了Docker
	if ! command -v docker &> /dev/null; then
	    echo "Docker未安装，正在安装..."
	    # 更新包列表
	    sudo apt-get update
	    # 安装必要的包
	    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
	    # 添加Docker的官方GPG密钥
	    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
	    # 添加Docker的APT仓库
	    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
	    # 再次更新包列表
	    sudo apt-get update
	    # 安装Docker
	    sudo apt-get install -y docker-ce
	    echo "Docker安装完成。"
	else
	    echo "Docker已安装。"
	fi
	
	sudo groupadd docker
	sudo usermod -aG docker $USER
	
	# 检查是否安装了Docker Compose
	if ! command -v docker-compose &> /dev/null; then
	    echo "Docker Compose未安装，正在安装..."
	    # 下载Docker Compose的二进制文件
	    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
	    # 赋予执行权限
	    sudo chmod +x /usr/local/bin/docker-compose
	    echo "Docker Compose安装完成。"
	else
	    echo "Docker Compose已安装。"
	fi
	
	git clone https://github.com/allora-network/allora-chain.git
	cd allora-chain
	make all
	allorad version
	
	sudo docker compose pull
	sudo docker compose up -d
}

# 安装worker
function install_worker(){
	# Install
	cd $HOME
	git clone https://github.com/allora-network/basic-coin-prediction-node
	cd basic-coin-prediction-node
	mkdir worker-data
	mkdir head-data
	
	# Give certain permissions
	sudo chmod -R 777 worker-data
	sudo chmod -R 777 head-data
	
	# Create head keys
	sudo docker run -it --entrypoint=bash -v ./head-data:/data alloranetwork/allora-inference-base:latest -c "mkdir -p /data/keys && (cd /data/keys && allora-keys)"
	# Create worker keys
	sudo docker run -it --entrypoint=bash -v ./worker-data:/data alloranetwork/allora-inference-base:latest -c "mkdir -p /data/keys && (cd /data/keys && allora-keys)"
	
	# Copy the head-id
	identity=$(cat head-data/keys/identity)
	mv docker-compose.yml docker-compose.yml.bak
	wget https://raw.githubusercontent.com/breaddog100/Allora/main/docker-compose.yml
	sed -i "s/head-id/$identity/g" docker-compose.yml
	
	sudo docker compose pull
	sudo docker compose up -d
}

# 创建钱包
function add_wallet() {
	read -p "请输入钱包名称: " wallet_name
	$HOME/go/bin/allorad keys add $wallet_name
}

# 查看日志
function view_logs(){
	sudo docker compose logs -f
}

# 查看状态
function check_status(){
	curl -s http://localhost:26657/status | jq .result.sync_info
}

sudo docker compose -f $HOME/allora-chain/docker-compose.yaml exec validator0 bash

# 卸载节点
function uninstall_node(){
    echo "你确定要卸载节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            l1_stop_node
            l2_stop_node
            sudo docker rm -f priceless_brattain
            
            sudo rm -rf $HOME/allora-chain

            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 主菜单
function main_menu() {
	while true; do
	    clear
	    echo "===================allora-network Pre-Alpha 一键部署脚本==================="
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "最低配置：4C8G512G；推荐配置：8C16G512G"
		echo "此版本是一个内部测试版，功能包含节点安装，块同步，创建钱包。大家可以先部署节点"
		echo "创建钱包后领水，后续会增加worker部署，创建验证者以及相关功能。感谢大家的测试和包容。"
		echo "请选择要执行的操作:"
	    echo "1. 部署节点 install_node"
	    echo "2. 查看状态 check_status"
	    echo "3. 查看日志 view_logs"
	    echo "4. 创建钱包 add_wallet"
	    echo "5. 申请验证者 "
	    echo "6. 安装worker install_worker"
	    echo "1618. 卸载节点 uninstall_node"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) check_status ;;
	    3) view_logs ;;
	    4) add_wallet ;;
	    6) install_worker ;;
	    1618) uninstall_node ;;
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

main_menu