#!/bin/bash

# Run as ROOT for example in /tmp directory and follow the instructions on the screen
# Tested on ubuntu 18.04 LTS


usage ()
{
    echo "Usage: $0 -n|--network NETWORK [-b|--branch BRANCH] [-t|--threads THREADS] [-u|--user USERNAME] [-w]"

    echo "NETWORK=NOS|BANANO|NANO"
    echo "BRANCH (optional): default is master, specify a different one if needed"
    echo "THREADS (optional): default is 1, adjust this to your machones cores"
    echo "USER (optional): default is "nos", put the user here under which the node will run. User will be create if it does not exist."
    echo "-w (optional) : if specified the nodewatchdog will be installed. For this RPC will be enabled on the node"
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
WATCHDOG="FALSE"

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
      shift
      shift
      ;;
    -b|--branch)
      BRANCH="$2"
      shift
      shift
      ;;
    -t|--threads)
      THREADS="$2"
      shift
      shift
      ;;
    -u|--user)
      USER="$2"
      shift
      shift
      ;;
    -w)
      WATCHDOG="TRUE"
      shift
      shift
      ;;
    *)    # unknown option
      echo "Unknown option $1"
      usage
      shift
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
      BUILD_TARGET="rai_node"
      ;;
    BANANO)
      NODE_REPO="https://github.com/BananoCoin/banano"
      BUILD_TARGET="bananode"
      ;;
    NANO)
      NODE_REPO="https://github.com/nanocurrency/raiblocks.git"
      BUILD_TARGET="rai_node"
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
apt update
apt install -y build-essential git cmake g++ curl make jq

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
make -j$THREADS $BUILD_TARGET

cp ./$BUILD_TARGET /home/$USER/
su - $USER -c "./$BUILD_TARGET --daemon --data_path /home/$USER/$DATA_DIR &"
sleep 5
pkill -f "$BUILD_TARGET"

# enable RPC when the watchdog has to be installed
if [ $WATCHDOG = "TRUE" ]; then
  sed -i 's/"rpc_enable": "false",/"rpc_enable": "true",/' /home/$USER/$DATA_DIR/config.json
fi

RPC_PORT="$( cat /home/$USER/$DATA_DIR/config.json | jq -r .rpc.port )"

cp "$PREV_PATH/rai_node.service" "/etc/systemd/system/$BUILD_TARGET.service"
sed -i "s^\$USER^$USER^g" "/etc/systemd/system/$BUILD_TARGET.service"
sed -i "s^\$DATA_DIR^$DATA_DIR^" "/etc/systemd/system/$BUILD_TARGET.service"
sed -i "s^\$BUILD_TARGET^$BUILD_TARGET^" "/etc/systemd/system/$BUILD_TARGET.service"
systemctl daemon-reload
systemctl enable $BUILD_TARGET

# Fix permissions
chown -R $USER:$USER /home/$USER

# start the node
service $BUILD_TARGET start
service $BUILD_TARGET status

if [ $WATCHDOG = "TRUE" ]; then
  
  # configure NodeWatchdog
  cd /home/$USER/
  git clone https://github.com/NOS-Cash/NodeWatchdog.git /home/$USER/NodeWatchdog

  # add Nodewatchdog a cronjob
  crontab -l > /tmp/current_cron
  echo "* * * * * /home/$USER/NodeWatchdog/nodewatchdog.sh $BUILD_TARGET $RPC_HOST $RPC_PORT" >> /tmp/current_cron
  crontab /tmp/current_cron
  rm /tmp/current_cron
fi

echo "INSTALLATION COMPLETE"
exit 0
