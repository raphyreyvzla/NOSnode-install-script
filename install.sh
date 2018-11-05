#!/bin/bash

# Run as ROOT for example in /tmp directory and follow the instructions on the screen
# Tested on ubuntu 18.04 LTS

# Usage ./install.sh [NOSnode-BRANCH]

# CONSTANTS
NOS_NODE_REPO="https://github.com/NOS-cash/NOSnode.git"
NOS_NODE_BRANCH=$1

# Number of threads used to compile the source, plz adjust it according the CPU cores of your machine
THREADS=3
USER="nos"
NOS_DATA_DIR="$NOS_NODE_BRANCH-Data"

PREV_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
echo "PREV_PATH is $PREV_PATH"

# Make sure only root can continue
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Check number of params
if (( $# != 1)); then
    echo "Illegal number of parameters"
    echo "./install.sh [NOSnode-BRANCH]"
    exit 1
fi

# install dependencies
apt-get update
apt-get install -y build-essential git cmake g++ curl make jq

# add User and enter his home
useradd -m $USER
cd /home/$USER

# install NOSnode
wget -O boost_1_66_0.tar.gz https://netix.dl.sourceforge.net/project/boost/boost/1.66.0/boost_1_66_0.tar.gz   
tar xzvf boost_1_66_0.tar.gz   
cd boost_1_66_0   
./bootstrap.sh --with-libraries=filesystem,iostreams,log,program_options,thread   
./b2 --prefix=../[boost] link=static install -j$THREADS

cd /home/$USER

git clone --recursive -b $NOS_NODE_BRANCH $NOS_NODE_REPO NOSnode_build
cd NOSnode_build
cmake -DBOOST_ROOT=../[boost]/ -G "Unix Makefiles"   
make -j$THREADS rai_node
./rai_node --diagnostics

cp ./rai_node /home/$USER/
su - $USER -c "./rai_node --daemon --data_path /home/$USER/$NOS_DATA_DIR &"
sleep 5
pkill -f "rai_node"

# uncomment if you want to enable RPC
# sed -i 's/"rpc_enable": "false",/"rpc_enable": "true",/' /home/$USER/$NOS_DATA_DIR/config.json
# sed -i 's/"enable_control": "false",/"enable_control": "true",/' /home/$USER/$NOS_DATA_DIR/config.json

RPC_PORT="$( cat /home/$USER/$NOS_DATA_DIR/config.json | jq -r .rpc.port )"

cp "$PREV_PATH/rai_node.service" /etc/systemd/system/rai_node.service
sed -i "s^\$USER^$USER^g" /etc/systemd/system/rai_node.service
sed -i "s^\$NOS_DATA_DIR^$NOS_DATA_DIR^" /etc/systemd/system/rai_node.service
systemctl daemon-reload
systemctl enable rai_node

# Fix permissions
chown -R $USER:$USER /home/$USER
service rai_node start
service rai_node status

# configure NodeWatchdog
cd /home/$USER/
git clone https://github.com/NOS-Cash/NodeWatchdog.git /home/$USER/NodeWatchdog
sed -i "s^NODE_RPC_PORT=\"7131\"^NODE_RPC_PORT=\"$RPC_PORT\"^" /home/$USER/NodeWatchdog/nodewatchdog.sh

# add Nodewatchdog a cronjob
crontab -l > /tmp/current_cron
echo "* * * * * /home/$USER/NodeWatchdog/nodewatchdog.sh" >> /tmp/current_cron
crontab /tmp/current_cron
rm /tmp/current_cron


echo "INSTALLATION COMPLETE"
exit 0
