#!/bin/bash

# Run as ROOT for example in /tmp directory and follow the instructions on the screen
# Tested on ubuntu 18.04 LTS


usage ()
{
    echo "Usage: $0 -n|--network NETWORK [-b|--branch BRANCH] [-t|--threads THREADS] [-u|--user USERNAME]"

    echo "NETWORK=NOS|BANANO|NANO"
    echo "BRANCH (optional): default is master, specify a different one if needed"
    echo "THREADS (optional): default is 1, adjust this to your machones cores"
    echo "USER (optional): default is "nos", put the user here under which the node will run. User will be create if it does not exist."
    echo ""
    echo "EXAMPLE: $0 -n NOS -b usd-network -t 3 -u nodeuser"

    exit 1
}

# check if this script is run as root
# TODO: implement a non-root mode
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi


# ARG parsing

NETWORK="NONE"
BRANCH="master"
THREADS="1"
USER="nos"

if (( $# < 2 )); then
  usage
fi

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -n|--network)
      NETWORK="$2"
      shift # past argument
      shift # past value
      ;;
    -b|--branch)
      BRANCH="$2"
      shift # past argument
      shift # past value
      ;;
    -t|--threads)
      THREADS="$2"
      ;;
    *)    # unknown option
      echo "Unknown option $1"
      usage
      shift # past argument
      ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ $NETWORK = "NONE" ]; then
    echo "No network specified (-n|--network)"
    usage
fi

# ARG parsing finished

case $NETWORK in
    NOS)
      NODE_REPO="https://github.com/NOS-cash/NOSnode.git"
      ;;
    BANANO)
      NODE_REPO="https://github.com/BananoCoin/banano"
      ;;
    NANO)
      NODE_REPO="https://github.com/nanocurrency/raiblocks.git"
      ;;
    *) # unknown network
      echo "Unknown network: $NETWORK"
      echo""
      usage
    ;;
esac

if [ $BRANCH = "master" ]; then
  DATA_DIR="$NETWORK-Data"
else
  DATA_DIR="$NETWORK-$BRANCH-Data"
fi

PREV_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
echo "PREV_PATH is $PREV_PATH"

# install dependencies
apt-get update
apt-get install -y build-essential git cmake g++ curl make jq

# add User and enter his home
useradd -m $USER
cd /home/$USER

# install boost locally in users home
wget -O boost_1_66_0.tar.gz https://netix.dl.sourceforge.net/project/boost/boost/1.66.0/boost_1_66_0.tar.gz   
tar xzvf boost_1_66_0.tar.gz   
cd boost_1_66_0   
./bootstrap.sh --with-libraries=filesystem,iostreams,log,program_options,thread   
./b2 --prefix=../[boost] link=static install -j$THREADS

cd /home/$USER

# install the node
git clone --recursive -b $BRANCH $NODE_REPO node_build
cd node_build
cmake -DBOOST_ROOT=../[boost]/ -G "Unix Makefiles"   
make -j$THREADS rai_node
./rai_node --diagnostics

cp ./rai_node /home/$USER/
su - $USER -c "./rai_node --daemon --data_path /home/$USER/$DATA_DIR &"
sleep 5
pkill -f "rai_node"

# uncomment if you want to enable RPC
# TODO: make it an ARG option
# sed -i 's/"rpc_enable": "false",/"rpc_enable": "true",/' /home/$USER/$DATA_DIR/config.json
# sed -i 's/"enable_control": "false",/"enable_control": "true",/' /home/$USER/$DATA_DIR/config.json

RPC_PORT="$( cat /home/$USER/$DATA_DIR/config.json | jq -r .rpc.port )"

cp "$PREV_PATH/rai_node.service" /etc/systemd/system/rai_node.service
sed -i "s^\$USER^$USER^g" /etc/systemd/system/rai_node.service
sed -i "s^\$DATA_DIR^$DATA_DIR^" /etc/systemd/system/rai_node.service
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
