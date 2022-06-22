#!/usr/bin/env bash

echo 
echo "[0;5;1;35;47m         [0;5;1;37;46mｗｒｋ[0;5;1;37;45m－ｕｔｉｌｓ[0;5;1;36;47m  [0;5;1;35;47m   [0;5;1;37;46m    [0;5;1;37;45m    [0;5;1;36;47m                       [0;5;1;37;46m    [0;5;37;47m   [0m"
echo
echo "Set of commands & lua scripts to run wrk in clusters and collect stats"
echo

WRK_PATH=""
SSH_PORT=""
SSH_OPTS=""
SCP_OPTS=""
SSH_CMD=""
SCP_CMD=""

CONFIG_FILE=${CONFIG_FILE:-config.env}
source $CONFIG_FILE

# it makes sure that required commands exist on control client (not servers)
declare -a COMMANDS=("ssh" "sshpass" "xargs")
for COMMAND in "${COMMANDS[@]}"; do
    if ! command -v $COMMAND &> /dev/null
    then
        echo $COMMAND \<- command could not be found. Please install it.
        return
    fi
done


BASE_SERVER_FILE=${BASE_SERVER_FILE:-servers.txt}
# a file that contains options
declare -a REQUIRED_FILES=($CONFIG_FILE)
for REQUIRED_FILE in "${REQUIRED_FILES[@]}"; do
    if [ ! -f $REQUIRED_FILE ] || [ `stat -c '%s' $REQUIRED_FILE` -lt 2 ]; then
        echo Can\'t find file or it\'s empty: "$REQUIRED_FILE"
        return
    fi
done

SSH_USR=${SSH_USR:?Please add SSH_USR \(username\) to $CONFIG_FILE file}
SSH_PWD=${SSH_PWD:?Please add SSH_PWD \(password\) to $CONFIG_FILE file.\nIf you wish to use ssh keys, set \$SSH_KEY=true but password is still required for sudo}

SERVERS_FILE=$BASE_SERVER_FILE

WRK_PATH=${WRK_PATH:-~/.wrk-utils/}
SSH_PORT=${SSH_PORT:-22}
SSH_OPTS="${SSH_OPTS:--p$SSH_PORT -oConnectTimeout=5 -oConnectionAttempts=10 -oStrictHostKeyChecking=no}"
SCP_OPTS="${SCP_OPTS:--P$SSH_PORT}"
SSH_CMD=${SSH_CMD:-ssh}
SCP_CMD=${SCP_CMD:-scp}

STDIN_TMP_FILE=''

if [ "$SSH_KEY" != "true" ]; then
    SSH_CMD="sshpass -p $SSH_PWD $SSH_CMD"
    SCP_CMD="sshpass -p $SSH_PWD $CSP_CMD"
fi


read-from-stdin () {
    if [ "$STDIN_TMP_FILE" = '' ]; then
        if [ ! -t 0 ]; then
            STDIN_TMP_FILE=$(mktemp)
            SERVERS_FILE=$STDIN_TMP_FILE
            while read -r line; do
                echo $line >> $STDIN_TMP_FILE
            done
        else
            SERVERS_FILE=$BASE_SERVER_FILE
        fi
    else
        return 255
    fi
}


clean-stdin-temp () {
    if [ -f "$STDIN_TMP_FILE" ]; then
        rm $STDIN_TMP_FILE
        STDIN_TMP_FILE=''
    fi
}


echo -e "\033[1m - Commands -\033[0m"
echo 
echo ssh-all: executes a command on all servers
echo -e "\t-> ssh-all 'ps aux | grep something'"
ssh-all () {
    read-from-stdin
    STATUS=$?
    cat $SERVERS_FILE | xargs -P100 -I{} echo $SSH_CMD $SSH_OPTS $SSH_USR@{} $@
    cat $SERVERS_FILE | xargs -P100 -I{} $SSH_CMD $SSH_OPTS $SSH_USR@{} $@

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo ssh-one: executes a command on a random server
echo -e "\t-> ssh-one 'ps aux | grep something'"
ssh-one () {
    read-from-stdin
    STATUS=$?
    SERVER=`shuf -n1 $SERVERS_FILE`
    echo server: $SERVER
    $SSH_CMD $SSH_OPTS $SSH_USR@$SERVER $@

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo ssh-all-sudo: executes a command on all servers as sudo
echo -e "\t-> ssh-all-sudo id | wc"
ssh-all-sudo () {
    read-from-stdin
    STATUS=$?
    ssh-all "echo $SSH_PWD | sudo -p \"\" -k -S" $@

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo ssh-one-sudo: executes a command on a server as sudo
echo -e "\t-> ssh-one-sudo id | wc"
ssh-one-sudo () {
    read-from-stdin
    STATUS=$?
    ssh-one "echo $SSH_PWD | sudo -p \"\" -k -S" $@

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo kill-all: kills all wrk instances on all servers \(friendly\)
echo -e "\t-> kill-all"
kill-all () {
    read-from-stdin
    STATUS=$?
    ssh-all 'pkill -INT -f ./wrk'

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo kill-all-force: kills all wrk instances on all servers \(force, can\'t keep logs\)
echo -e "\t-> kill-all-force"
kill-all-force () {
    read-from-stdin
    STATUS=$?
    ssh-all 'killall wrk'

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo available-node-count: prints number of available servers
echo -e "\t-> available-node-count"
available-node-count () {
    read-from-stdin
    STATUS=$?
    ssh-all "id" | wc -l

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo active-node-count: prints number of active wrk instances in a loop
echo -e "\t-> active-node-count"
active-node-count () {
    read-from-stdin
    STATUS=$?
    while true; do
        ssh-all "pidof wrk" | wc -w
        sleep 1
    done

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo live-stats: live stats for all servers \(per thread\).
echo -e "\t-> live-stats"
live-stats () {

    if [ $WRK_LIVESTATS = 'true' ]; then
        read-from-stdin
        STATUS=$?
        cat $SERVERS_FILE | ssh-all "ls $WRK_PATH | tail -n1 | xargs -ILOGFN tail -f $WRK_PATH/LOGFN"
        if [ ! $STATUS -eq 255 ]; then
            clean-stdin-temp
        fi
    else
        echo live stats is not enabled
        echo add WRK_LIVESTATS=true to $CONFIG_FILE.
    fi
}


echo
echo init-servers: creates wrk directory on servers copies wrk and lua scripts into that
echo -e "\t-> init-servers"
init-servers () {
    read-from-stdin
    STATUS=$?
    echo Uploading wrk and lua scripts to the servers...
    echo To upload other files \(e.g., wordlists\) please use sync-file command
    ssh-all "mkdir $WRK_PATH 2> /dev/null"
    cat $SERVERS_FILE | xargs -P10 -I{} $SCP_CMD $SCP_OPTS wrk *.lua "$SSH_USR@{}:$WRK_PATH"
    echo Done!

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo sync-file: copies provided files to wrk directory on all servers
echo -e "\t-> sync-file wordlist.txt *.jpg"
sync-file () {
    read-from-stdin
    STATUS=$?
    echo Syncing files: "$@"
    cat $SERVERS_FILE | xargs -P10 -I{} $SCP_CMD $SCP_OPTS $@ "$SSH_USR@{}:$WRK_PATH"
    echo Done!

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}


echo
echo exec-wrk: executes wrk step by step or at once \(first argument is the delay to execute next instance\)
echo -e "\t-> exec-wrk 10 -t10 -c300 -d600s -s stats.lua 'https://example.com/path/?id=1'"
echo -e "\t-> exec-wrk 0 -t10 -c300 -d600s -s custom.lua 'https://example.com/'"
exec-wrk () {
    read-from-stdin
    STATUS=$?
    ssh-all-sudo "sysctl net.core.somaxconn=65535"
    cat $SERVERS_FILE | while read SERVER; do
        $SSH_CMD $SSH_OPTS "$SSH_USR@"$SERVER "ulimit -n 1000000 && cd $WRK_PATH && NODE_IP=$SERVER WRK_DEBUG=$WRK_DEBUG WRK_LIVESTATS=$WRK_LIVESTATS WRK_LOGHEADERS=$WRK_LOGHEADERS SLACK_WEBHOOK=$SLACK_WEBHOOK SLACK_WEBHOOK_DBG=$SLACK_WEBHOOK_DBG ./wrk ${@:2}" &
        echo `date` - new node \("$SERVER"\) is started!
        sleep $1
    done

    if [ ! $STATUS -eq 255 ]; then
        clean-stdin-temp
    fi
}

echo
echo
