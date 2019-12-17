#!/bin/bash
# 
# Add your copyright here !
#
# Note: requires BASH 4
# set -x


# usefull functions and variables
MYNAME="$(basename $0)"
DEBUG="true"  # Set to false when deploying
NOOP="true"   # Set to false when deploying
LOGFILE="/var/log/${MYNAME}.log" 

function get_help {
cat <<EOF

  Usage:
      ${MYNAME} [OPTIONS]

      Options:
      --debug <true/false>            Run in debug mode and display all commands and outputs.  Defaults to no.
      --noop <true/false>             Run in noop mode and output all commands without running them.  Defaults to no.
      --logfile <path to log file>    Where to log the output.  Defaults to /var/log/SCRIPT_NAME.log.  Set to /dev/null to disable.
      --help                          This message.
EOF

exit 1
}

function output () {
    if [ "$NOOP" == 'true' ]; then
        if [ "$DEBUG" == 'true' ]; then
            echo "$1" |& tee -a $LOGFILE
        else
            echo "$1"
        fi
    else
        if [ "$DEBUG" == 'true' ]; then
            echo "Command: $1" |& tee -a $LOGFILE
            eval "$1" |& tee -a $LOGFILE
        else
            eval "$1" >> $LOGFILE
        fi
    fi    
    
}

# Arguments Check
gethelp=false
while [[ $# > 0 ]]
do
  key="$1" 
  shift
  case $key in
    --noop)
      NOOP="$1" 
      shift
      ;;
    --debug)
      DEBUG="$1" 
      shift
      ;;
    --logfile)
      LOGFILE="$1" 
      shift
      ;;
    --help)
      gethelp=true
      ;;
    *)
      output "echo \"Unknown option: $key\" >&2"
      output "get_help >&2"
      exit 1
      ;;
  esac
done

# did we call --help?
$gethelp &&  output "get_help >&2"

# check for required args.  Uncomment if you have required arguments.
# if [ -z ${tmpfolder+x} ] || [ -z ${dbtorestore+x} ]; then
#  echo -e '\nERROR: Missing one or more required args'
#  get_help
# fi

# Lock to ensure script is run only once at a time
#lock dirs/files
LOCKDIR="/tmp/${MYNAME}" 
PIDFILE="${LOCKDIR}/PID" 
# exit codes and text
ENO_SUCCESS=0; ETXT[0]="ENO_SUCCESS" 
ENO_GENERAL=1; ETXT[1]="ENO_GENERAL" 
ENO_LOCKFAIL=2; ETXT[2]="ENO_LOCKFAIL" 
ENO_RECVSIG=3; ETXT[3]="ENO_RECVSIG" 

###
### start locking attempt
###

trap 'ECODE=$?; echo "[${MYNAME}] Exit: ${ETXT[ECODE]}($ECODE)"' 0
output "echo -n [${MYNAME}] Locking:" 

if mkdir "${LOCKDIR}" &>/dev/null; then

    # lock succeeded, install signal handlers before storing the PID just in case 
    # storing the PID fails
    trap 'ECODE=$?;
          output "echo \"[${MYNAME}] Removing lock: Exit: ${ETXT[ECODE]}($ECODE)\""
          rm -rf "${LOCKDIR}"' 0
    echo "$$" >"${PIDFILE}" 
    # the following handler will exit the script upon receiving these signals
    # the trap on "0" (EXIT) from above will be triggered by this trap's "exit" command!
    trap 'output "echo \"[${MYNAME}] Killed by a signal.\" >&2"
          exit ${ENO_RECVSIG}' 1 2 3 15
    output "echo success, installed signal handlers" 

else

    # lock failed, check if the other PID is alive
    OTHERPID="$(cat "${PIDFILE}")" 

    # if cat isn't able to read the file, another instance is probably
    # about to remove the lock -- exit, we're *still* locked
    #  Thanks to Grzegorz Wierzowiecki for pointing out this race condition on
    #  http://wiki.grzegorz.wierzowiecki.pl/code:mutex-in-bash
    if [ $? != 0 ]; then
      output "echo \"lock failed, PID ${OTHERPID} is active\" >&2"
      exit ${ENO_LOCKFAIL}
    fi

    if ! kill -0 $OTHERPID &>/dev/null; then
        # lock is stale, remove it and restart
        output "echo \"removing stale lock of nonexistant PID ${OTHERPID}\" >&2"
        rm -rf "${LOCKDIR}" 
        output "echo \"[${MYNAME}] restarting myself\" >&2"
        exec "$0" "$@" 
    else
        # lock is valid and OTHERPID is active - exit, we're locked!
        output "echo \"lock failed, PID ${OTHERPID} is active\" >&2"
        exit ${ENO_LOCKFAIL}
    fi

fi

exit 0
