#!/bin/bash

###############################################################################################
# Pgpool failover script
# Promote a new primary node after a failed primary node is detected.
# This script connects to a new primary using passwordless SSH and executes
# "repmgr standby promote" to promote it as a new primary node.
#
# Notifications are send via e-mail
#
# Command arguments (all arguments are positional):
#   - $1: failed node ID number
#   - $2: failed node hostname
#   - $3: old primary node ID number
#   - $4: new primary node ID number (will became new primary after promotion)
#   - $5: new primary node hostname (the script connects to this server to execute promotion)
#   - $6: new primary $PGDATA directory
#
# Mattia Martinello
# mattia@mattiamartinello.com
#
# Version 1.3 - 07/10/2019
#
# Changelog:
# * Version 1.3 (07/10/2019):
#   - specify when to print the output from an executed command using the cmd_exec function
###############################################################################################

# Command arguments
failed_node_id=$1
failed_hostname=$2
old_primary_id=$3
new_primary_id=$4
new_primary_hostname=$5
new_primary_pgdata=$6

# Command settings
postgres_user="postgres"
ssh_command="`which ssh` -q -p 22 -n -T -o StrictHostKeyChecking=no"
repmgr_command="/usr/bin/repmgr -f /etc/repmgr.conf"
cluster_show_command="$ssh_command $postgres_user@${new_primary_hostname} $repmgr_command cluster show --compact"
promote_command="$ssh_command $postgres_user@${new_primary_hostname} $repmgr_command standby promote -v"

# Log file
log_file="/var/log/pgpool/pgpool-failover.log"

# Mail settings
mail_recipients=("sysadmin@chino.io" "mattia@mattiamartinello.com") # Recipient addresses
mail_subject="[pgpool@$HOSTNAME.test.dc.chino.io] FAILOVER EVENT: $failed_hostname --> $new_primary_hostname" # Mail subject
mail_fail_subject_prepend="[!!! ---FAILURE--- !!!] "

# End confiugration
#########################################################################

. generic-functions.sh

# If the failed node was the primary node, change the mail subject
if [ $failed_node_id -ne $old_primary_id ] ; then
    mail_subject="[pgpool@$HOSTNAME.test.dc.chino.io] NODE FAILED: $failed_hostname (ID $failed_node_id)"
fi

# Main function
main() {
    exec 5>&2
    start_seconds=$SECONDS
    start_time=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Execute failover
    msg
    msg "================================================================="
    msg "FAILOVER EVENT"
    msg "Failed node: $failed_hostname (ID $failed_node_id)"
    msg "================================================================="
    msg ""
    msg ""

    # Show cluster status
    msg "CLUSTER STATUS:"
    cmd_exec "$cluster_show_command"
    msg ""
    msg ""

    # If the failed node was the primary node, execute promotion on a standby node
    if [ $failed_node_id = $old_primary_id ] ; then    	
    	# Execute promote command
        msg "Failed node: $failed_hostname (ID $failed_node_id)"
        msg "Old primary ID: $old_primary_id"
        msg "Promoting new primary node: $new_primary_hostname (ID $new_primary_id)"
        msg ""
        msg "EXECUTING PROMOTION OF $new_primary_hostname (ID $new_primary_id) ..."
        msg ""
        cmd_exec "$promote_command"
        msg ""
        msg ""
        
        # Get promotion command status code
        # Note: repmgr returns 25 if a node has an unexpected status, so we don't
        # consider this as error!
        status=$?
        if [ "$status" -eq 25 ]; then
            status="0"
        fi 
        
        # Show cluster status again (after promotion)
        msg "CLUSTER STATUS AFTER PROMOTION:"
        cmd_exec "$cluster_show_command"
        msg ""
        msg ""
        
        # If error during promotion, print and return error

        if [ "$status" -ne "0" ]; then
            msg "*** ERROR DURING PROMOTION! ***"
            msg "Promotion command exit code: $status"
            msg "Please check and fix manually!"
            msg ""
            msg "CLUSTER STATUS:"
            cmd_exec "$cluster_show_command"
            msg ""
            msg ""
            return $status
        fi        

    # Else I don't need to promote any node because the failed node was a standby
    else    
        msg "$failed_hostname (ID $failed_node_id) was not primary."
        msg ""
        msg "*** Please check and fix manually! ***"
        msg ""
        msg ""
    fi
    
    end_seconds=$SECONDS
    end_time=$(date +"%Y-%m-%d %H:%M:%S")
    elapsed_seconds=$((end_seconds - start_seconds))
    elapsed_time=$(displaytime $elapsed_seconds)

    # Debug
    msg
    msg "================================================================="
    msg "Exit code: ${status}"
    msg "Start time: ${start_time}"
    msg "End time: ${end_time}"
    msg "Elapsed time: ${elapsed_time}"
    return $status
}

# Execute main commands and take output
mail_text="$(main)"
status=$?
# Note: repmgr returns 25 if a node has an unexpected status, so we don't
# consider this as error!
if [ "$status" -eq 25 ]; then
    status="0"
fi

# Check exit status code and compose the mail message
if [ "$status" -ne "0" ]; then
    mail_subject="$mail_fail_subject_prepend $mail_subject"
fi

# Execute main function and write output to log file and send it to mail message
printf "%s\n" "$mail_text" | tee -a $log_file | send_mail "$mail_subject" "${mail_recipients[@]}"

# Exit with last status code
exit $status
