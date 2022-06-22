#!/usr/bin/env fish

echo 
echo "[0;5;1;35;47m         [0;5;1;37;46mｗｒｋ[0;5;1;37;45m－ｕｔｉｌｓ[0;5;1;36;47m  [0;5;1;35;47m   [0;5;1;37;46m    [0;5;1;37;45m    [0;5;1;36;47m                       [0;5;1;37;46m    [0;5;37;47m   [0m"
echo
echo "Set of commands & lua scripts to run wrk in clusters and collect stats"
echo

set -e WRK_PATH
set -e SSH_PORT
set -e SSH_OPTS
set -e SCP_OPTS
set -e SSH_CMD
set -e SCP_CMD

set -q CONFIG_FILE || set CONFIG_FILE config.env
cat $CONFIG_FILE | sed -e 's/\([A-Z_]\+\)=\(.*\)/set \1 "\2"/' | grep -v '^#' | source

# it makes sure that required commands exist on control client (not servers)
set COMMANDS "ssh" "sshpass" "xargs"
for COMMAND in $COMMANDS
    if not command -v $COMMAND &> /dev/null
        echo $COMMAND \<- command could not be found. Please install it.
        exit
    end
end


set -q BASE_SERVER_FILE || set BASE_SERVER_FILE servers.txt
# a file that contains options
set REQUIRED_FILES $CONFIG_FILE
for REQUIRED_FILE in $REQUIRED_FILES
    if not test -f $REQUIRED_FILE || test (stat -c '%s' $REQUIRED_FILE) -lt 2
        echo Can\'t find file or it\'s empty: "$REQUIRED_FILE"
        exit
    end
end

set -q SSH_USR || echo Please add SSH_USR \(username\) to $CONFIG_FILE file
set -q SSH_PWD || echo Please add SSH_PWD \(password\) to $CONFIG_FILE file.\nIf you wish to use ssh keys, set \$SSH_KEY=true but password is still required for sudo

set SERVERS_FILE $BASE_SERVER_FILE

set -q WRK_PATH || set WRK_PATH ~/.wrk-utils/
set -q SSH_PORT || set SSH_PORT 22
set -q SSH_OPTS || set SSH_OPTS -p$SSH_PORT -oConnectTimeout=5 -oConnectionAttempts=10 -oStrictHostKeyChecking=no
set -q SCP_OPTS || set SCP_OPTS -P$SSH_PORT
set -q SSH_CMD || set SSH_CMD ssh
set -q SCP_CMD || set SCP_CMD scp

set STDIN_TMP_FILE ''

if not test "$SSH_KEY" = "true"
    set SSH_CMD sshpass -p "$SSH_PWD[1..-1]" $SSH_CMD
    set SCP_CMD sshpass -p "$SSH_PWD" $CSP_CMD
end


function read-from-stdin
    if test "$STDIN_TMP_FILE" = ''
        if not isatty stdin
            set STDIN_TMP_FILE (mktemp)
            set SERVERS_FILE $STDIN_TMP_FILE
            while read -L line
                echo $line >> $STDIN_TMP_FILE
            end
        else
            set SERVERS_FILE $BASE_SERVER_FILE
        end
    else
        return 255
    end
end



function clean-stdin-temp
    if test -f "$STDIN_TMP_FILE"
        rm $STDIN_TMP_FILE
        set STDIN_TMP_FILE ''
    end
end



echo -e "\033[1m - Commands -\033[0m"
echo 
echo ssh-all: executes a command on all servers
echo -e "\t-> ssh-all 'ps aux | grep something'"
function ssh-all
    read-from-stdin
    set STATUS $status
    cat $SERVERS_FILE | xargs -P100 -I{} $SSH_CMD $SSH_OPTS $SSH_USR@{} $argv
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo ssh-one: executes a command on a random server
echo -e "\t-> ssh-one 'ps aux | grep something'"
function ssh-one
    read-from-stdin
    set STATUS $status
    set SERVER (shuf -n1 $SERVERS_FILE)
    echo server: $SERVER
    $SSH_CMD $SSH_OPTS $SSH_USR@$SERVER $argv
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo ssh-all-sudo: executes a command on all servers as sudo
echo -e "\t-> ssh-all-sudo id | wc"
function ssh-all-sudo
    read-from-stdin
    set STATUS $status
    ssh-all "echo $SSH_PWD | sudo -p \"\" -k -S" $argv
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo ssh-one-sudo: executes a command on a server as sudo
echo -e "\t-> ssh-one-sudo id | wc"
function ssh-one-sudo
    read-from-stdin
    set STATUS $status
    ssh-one "echo $SSH_PWD | sudo -p \"\" -k -S" $argv
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo kill-all: kills all wrk instances on all servers \(friendly\)
echo -e "\t-> kill-all"
function kill-all
    read-from-stdin
    set STATUS $status
    ssh-all 'pkill -INT -f ./wrk'
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo kill-all-force: kills all wrk instances on all servers \(force, can\'t keep logs\)
echo -e "\t-> kill-all-force"
function kill-all-force
    read-from-stdin
    set STATUS $status
    ssh-all 'killall wrk'
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo available-node-count: prints number of available servers
echo -e "\t-> available-node-count"
function available-node-count
    read-from-stdin
    set STATUS $status
    ssh-all "id" | wc -l
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo active-node-count: prints number of active wrk instances in a loop
echo -e "\t-> active-node-count"
function active-node-count
    read-from-stdin
    set STATUS $status
    while true
        ssh-all "pidof wrk" | wc -w
        sleep 1
    end
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end

echo
echo live-stats: live stats for all servers \(per thread\).
echo -e "\t-> live-stats"
function live-stats

    if test $WRK_LIVESTATS = 'true'
        read-from-stdin
        set STATUS $status
        cat $SERVERS_FILE | ssh-all "ls $WRK_PATH | tail -n1 | xargs -ILOGFN tail -f $WRK_PATH/LOGFN"
        if not test $STATUS -eq 255
            clean-stdin-temp
        end
    else
        echo live stats is not enabled
        echo add WRK_LIVESTATS=true to $CONFIG_FILE.
    end
end

echo
echo init-servers: creates wrk directory on servers copies wrk and lua scripts into that
echo -e "\t-> init-servers"
function init-servers
    read-from-stdin
    set STATUS $status
    echo Uploading wrk and lua scripts to the servers...
    echo To upload other files \(e.g., wordlists\) please use sync-file command
    ssh-all "mkdir $WRK_PATH 2> /dev/null"
    cat $SERVERS_FILE | xargs -P10 -I{} $SCP_CMD $SCP_OPTS wrk *.lua "$SSH_USR@{}:$WRK_PATH"
    echo Done!
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo sync-file: copies provided files to wrk directory on all servers
echo -e "\t-> sync-file wordlist.txt *.jpg"
function sync-file
    read-from-stdin
    set STATUS $status
    echo Syncing files: $argv
    cat $SERVERS_FILE | xargs -P10 -I{} $SCP_CMD $SCP_OPTS $argv "$SSH_USR@{}:$WRK_PATH"
    echo Done!
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end


echo
echo exec-wrk: executes wrk step by step or at once \(first argument is the delay to execute next instance\)
echo -e "\t-> exec-wrk 10 -t10 -c300 -d600s -s stats.lua 'https://example.com/path/?id=1'"
echo -e "\t-> exec-wrk 0 -t10 -c300 -d600s -s custom.lua 'https://example.com/'"
function exec-wrk
    read-from-stdin
    set STATUS $status
    ssh-all-sudo "sysctl net.core.somaxconn=65535"
    for SERVER in (cat $SERVERS_FILE)
        $SSH_CMD $SSH_OPTS $SSH_USR@$SERVER "ulimit -n 1000000 && cd $WRK_PATH && NODE_IP=$SERVER WRK_DEBUG=$WRK_DEBUG WRK_LIVESTATS=$WRK_LIVESTATS WRK_LOGHEADERS=$WRK_LOGHEADERS SLACK_WEBHOOK=$SLACK_WEBHOOK SLACK_WEBHOOK_DBG=$SLACK_WEBHOOK_DBG ./wrk $argv[2..-1]" &;
        echo (date)" - new node ("$SERVER") is started!"
        sleep $argv[1]
    end
    if not test $STATUS -eq 255
        clean-stdin-temp
    end
end

echo
echo
