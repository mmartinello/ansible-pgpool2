#!/bin/bash

###############################################################################################
# Generic backup functions
# Mattia Martinello
# mattia@mattiamartinello.com
#
# Version 1.0 - 25/02/2020
#
###############################################################################################

# Mail function
send_mail() {
    local subject recipients
    subject="$1"
    shift
    recipients=("$@")
    mail -a "Content-Type: text/plain; charset=UTF-8" -s "$subject" "${recipients[@]}" 
}

# Display seconds in human readable format
function displaytime {
  local T=$1
  local D=$((T/60/60/24))
  local H=$((T/60/60%24))
  local M=$((T/60%60))
  local S=$((T%60))
  (( $D > 0 )) && printf '%d days ' $D
  (( $H > 0 )) && printf '%d hours ' $H
  (( $M > 0 )) && printf '%d minutes ' $M
  (( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
  printf '%d seconds\n' $S
}

# Print message both to stdout and FD5
msg() {
    msg="$1"
    echo "$msg" | tee /dev/fd/5
}

# Command execution
# Function arguments:
#   - $1: the command to be executed
#   - $2: when command output has to be printed out:
#     * 1 = always (default)
#     * 0 = never
#     * 2 | on_error = only on error (status code != 0)
cmd_exec() {
    cmd="$1"
    
    # If $2 not given set the default (1=always print)
    if [ -z "$2" ]; then
      print_output="1"
    else
      print_output=$2
    fi
        
    exec 5>&2
    #echo "La variabile print_output e' $print_output"
    #echo "Executing command '$cmd' ..."
    output=$($cmd 2>&1 |tee /dev/fd/5; exit ${PIPESTATUS[0]})
    status=$?
    #echo "Command exited with status code: $status"
    echo
    
    if [ "$print_output" -eq "1" ]; then
    	#echo "Stampo output"
    	echo "$output"
    elif [ "$print_output" -eq "2" ] || [ "$print_output" -eq "on_error" ]; then
        if [ "$status" -ne "0" ]; then
          echo "Stampo output"
          echo "$output"
        fi
    fi
    
    return $status
}

# Command execution
# Function arguments:
#   - $1: the command to be executed
#   - $2: when command output has to be printed out:
#     * 1 = always (default)
#     * 0 = never
#     * 2 | on_error = only on error (status code != 0)
cmd_exec_bis() {
    cmd="$1"
    
    exec 5>&2
    echo "Executing command '"$@"' ..."
    output=`"$@" 2>&1 |tee /dev/fd/5; exit ${PIPESTATUS[0]}`
    status=$?
    echo "Command exited with status code: $status"
    echo
    
    echo "$output"
    
    return $status
}

# Trap CTRL+C
trap ctrl_c INT
function ctrl_c() {
    echo "Removing backup output dir ..."
    rm -rf "$output_dir"
    $(sleep 2)
    umount_storage
    exit 99
}

# Unmount storage
function umount_storage() {
    cmd="/bin/umount /mnt/backup"
    $cmd
}
