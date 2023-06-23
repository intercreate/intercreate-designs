#!/bin/sh
#

CMD="STATUS"

THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

function log() {
  local lvl=$1
  local str=$2

  local RED="\033[0;91m"
  local YELLOW="\033[0;33m"
  local GREEN="\033[1;92m"
  local BOLD="\033[1m"
  local CYAN="\033[96m"
  local OFF="\033[0m"

  case ${lvl} in
    ERROR)
      color=${RED}
      lvl="** $lvl"
      ;;
    WARNING)
      color=${YELLOW}
      ;;
    OK)
      color=${GREEN}
      ;;
    INFO)
      color=${BOLD}
      ;;
    *)
      color=${CYAN}
      ;;
  esac

  echo -e "${color}${lvl}: ${str}${OFF}"
}


function usage() {
  log INFO "Usage: $0 [--status|-s] [--connect|-c] [--shutdown|-k]"
  log INFO "default: $0 --status"
}

function ec2_get_status() {
  aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicDnsName]' --output text
}

function ec2_start_instance() {
  local inst=$1
  aws ec2 start-instances --instance-ids ${inst}
}

function ec2_stop_instance() {
  local inst=$1
  aws ec2 stop-instances --instance-ids ${inst}
}

function do_connect() {
  local out
  local inst
  local state
  local url

  if [ "$(echo \"${out}\" | wc -l)" -ne "1" ]; then
    log ERROR "Script doesn't support more than 1 instance"
    exit 2
  fi
  while true; do
    out=$(ec2_get_status)
    inst=$(echo ${out} | awk '{ print $1 }')
    state=$(echo ${out} | awk '{ print $2 }')
    url=$(echo ${out} | awk '{ print $3 }')

    case ${state} in
      running )
        echo -en "\n"
        log INFO "Connecting to '${url}'."
        ssh ubuntu@${url}
        if [ "$(echo $?)" -ne "0" ]; then
          log WARNING "Failed to connect. Trying again after 2 seconds.."
          sleep 2
          ssh ubuntu@${url}
        fi
        break
        ;;
      pending )
        echo -ne ". "
        ;;
      stopped )
        log INFO "Starting instance '${inst}'"
        ec2_start_instance ${inst}
        ;;
      stopping )
        ;;
      * )
        log ERROR "Unhanlded instance state '${state}'"
    esac
    sleep 1
  done
}

function do_shutdown() {
  out=$(ec2_get_status)
  if [ "$(echo \"${out}\" | wc -l)" -ne "1" ]; then
    log ERROR "Script doesn't support more than 1 instance"
    exit 1
  fi
  inst=$(echo ${out} | awk '{ print $1 }')
  state=$(echo ${out} | awk '{ print $2 }')
  url=$(echo ${out} | awk '{ print $3 }')
  if [ "${state}" = "running" ]; then
    ec2_stop_instance ${inst}
  else
    log ERROR "No instances running ('state = ${state}')"
  fi
}

while [ $# -gt 0 ]; do
  case $1 in
    --status | -s)
      shift
      CMD="STATUS"
      ;;
    --connect | -c)
      shift
      CMD="CONNECT"
      ;;
    --shutdown | -k)
      shift
      CMD="SHUTDOWN"
      ;;
    --help | -h)
      shift
      usage
      exit 0
      ;;
    *)
      log ERROR "Invalid option '$1'"
      usage
      exit 1
      ;;
  esac
done

which aws &> /dev/null
if [ "$(echo $?)" -ne "0" ]; then
    log ERROR "'aws' is not found in your PATH"
    exit 1
fi

if [ "${CMD}" = "STATUS" ]; then
  log INFO "$(ec2_get_status)"
elif [ "${CMD}" = "CONNECT" ]; then
  do_connect
elif [ "${CMD}" = "SHUTDOWN" ]; then
  do_shutdown
fi

