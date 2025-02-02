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
	
	read -p "输入钱包助记词: " wallet_seed

	# Install Python3
	sudo apt install python3
	python3 --version
	
	sudo apt install python3-pip
	pip3 --version

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
	sed -i "s/WALLET_SEED_PHRASE/$wallet_seed/g" docker-compose.yml
	
	sudo docker compose build
	sudo docker compose up -d
}

# 创建钱包
function add_wallet() {
	read -p "请输入钱包名称: " wallet_name
	$HOME/go/bin/allorad keys add $wallet_name
}

# 导入钱包
function import_wallet() {
	read -p "请输入钱包名称: " wallet_name
	echo "请输入助记词："
	$HOME/go/bin/allorad keys add $wallet_name --recover
}

# 查看全节点日志
function view_logs(){
	sudo docker ps --filter "ancestor=alloranetwork/allora-chain:v0.2.7" --format "{{.ID}}" | xargs -I {} sudo docker logs --tail 200 {}
}

# 查看worker日志
function view_worker_logs(){
	sudo docker ps --filter "ancestor=basic-coin-prediction-node-worker" --format "{{.ID}}" | xargs -I {} sudo docker logs -f {}
}

# 查看worker状态
function check_worker_status(){
	echo "输出的结果中code如果是200代表成功，如果是其他（如408）代表失败，可能会因为块同步的问题导致失败，建议等一会儿再查，如果始终不是200，建议卸载重装"
	curl --location 'http://localhost:6000/api/v1/functions/execute' \
	--header 'Content-Type: application/json' \
	--data '{
	    "function_id": "bafybeigpiwl3o73zvvl6dxdqu7zqcub5mhg65jiky2xqb4rdhfmikswzqm",
	    "method": "allora-inference-function.wasm",
	    "parameters": null,
	    "topic": "1",
	    "config": {
	        "env_vars": [
	            {
	                "name": "BLS_REQUEST_PATH",
	                "value": "/api"
	            },
	            {
	                "name": "ALLORA_ARG_PARAMS",
	                "value": "ETH"
	            }
	        ],
	        "number_of_nodes": -1,
	        "timeout": 2
	    }
	}'
}

# 查看状态
function check_status(){
	curl -s http://localhost:26657/status | jq .result.sync_info
}

# 修复worker 408
function fix_worker_408(){
	sed -i 's/--topic=1/--topic=allora-topic-1-worker/' $HOME/basic-coin-prediction-node/docker-compose.yml
	sudo docker stop basic-coin-prediction-node-worker
	cd $HOME/basic-coin-prediction-node/
	sudo docker compose build
	sudo docker compose up -d
	echo "已经修复，请运行7查看状态"
}

#sudo docker compose -f $HOME/allora-chain/docker-compose.yaml exec validator0 bash

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
	    echo "===================allora-network 一键部署脚本==================="
		echo "沟通电报群：https://t.me/lumaogogogo"
		echo "最低配置：4C8G50G；推荐配置：8C16G512G"
		echo "步骤：1,部署全节点;2,创建钱包;3,领水;4,领到水后部署worker"
		echo "感谢以下无私的分享者："
    	echo "Jack Putin 修复worker 408问题"
    	echo "===================桃花潭水深千尺，不及汪伦送我情====================="
		echo "请选择要执行的操作:"
	    echo "1. 部署全节点 install_node"
	    echo "2. 查看全节点状态 check_status"
	    echo "3. 查看全节点日志 view_logs"
	    echo "4. 创建钱包 add_wallet"
	    echo "5. 导入钱包 import_wallet"
	    echo "6. 部署worker install_worker"
	    echo "7. 查看worker状态 check_worker_status"
	    echo "8. 查看worker日志 view_worker_logs"
	    echo "9. 修复408状态 fix_worker_408"
	    echo "1618. 卸载节点 uninstall_node"
	    echo "0. 退出脚本 exit"
	    read -p "请输入选项: " OPTION
	
	    case $OPTION in
	    1) install_node ;;
	    2) check_status ;;
	    3) view_logs ;;
	    4) add_wallet ;;
	    5) import_wallet ;;
	    6) install_worker ;;
	    7) check_worker_status ;;
	    8) view_worker_logs ;;
	    9) fix_worker_408 ;;
	    1618) uninstall_node ;;
	    0) echo "退出脚本。"; exit 0 ;;
	    *) echo "无效选项，请重新输入。"; sleep 3 ;;
	    esac
	    echo "按任意键返回主菜单..."
        read -n 1
    done
}

main_menu