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
# Version 1.0.1 - 19/11/2020
#
# Changelog:
# * Version 1.0 (30/08/2020):
#   - first version
# * Version 1.0.1 (19/11/2020):
#   - fixed command pathes (static to dynamic using 'which')
###############################################################################################

# Command arguments
#follow_master_command = '/usr/local/bin/pgpool-follow_master.sh %d %h %m %p %H %M %P %H'
                                   # Executes this command after master failover
                                   # Special values:
                                   #   %d = failed node id
                                   #   %h = failed node host name
                                   #   %p = failed node port number
                                   #   %D = failed node database cluster path
                                   #   %m = new master node id
                                   #   %H = new master node hostname
                                   #   %M = old master node id
                                   #   %P = old primary node id
                                   #   %r = new master port number
                                   #   %R = new master database cluster path
                                   #   %N = old primary node hostname
                                   #   %S = old primary node port number
                                   #   %% = '%' character

# Execution example on postgres2 which is the failed master:
# /usr/local/bin/pgpool-follow_master.sh 1 postgres2 0 5432 postgres1 0 1

# Execution example on postgres3 to follow the new primary postgres1
# /usr/local/bin/pgpool-follow_master.sh 2 postgres3 0 5432 postgres1 0 1

failed_node_id=$1
failed_node_hostname=$2
new_master_node_id=$3
failed_node_port=$4
new_master_hostname=$5
old_master_node_id=$6
old_primary_node_id=$7
old_master_node_hostname=$8

# Command settings
postgres_user="postgres"
postgres_pgdata_path="/var/lib/postgresql/12/main"
ssh_command="`which ssh` -q -p 22 -n -T -o StrictHostKeyChecking=no"
repmgr_command="/usr/bin/repmgr -f /etc/repmgr.conf"
repmgr_user="repmgr"
cluster_show_command="$ssh_command $postgres_user@${failed_node_hostname} $repmgr_command cluster show --compact"
follow_command="$ssh_command $postgres_user@${failed_node_hostname} $repmgr_command -D $postgres_pgdata_path -U $repmgr_user standby follow -v"

# Pgpool settings
pgpool_host="localhost"
pgpool_port="5432"
pgpool_user="repmgr"
pgpool_pcp_port="9898"
pgpool_show_pool_command="`which psql` -h $pgpool_host -p $pgpool_port -U $pgpool_user -c 'show pool_nodes;'"
pgpool_attach_node_command="`which pcp_attach_node` -h $pgpool_host -p $pgpool_pcp_port -w $failed_node_id"

# Log file
log_file="/var/log/pgpool/pgpool-follow-master.log"

# Mail settings
#mail_recipients=("sysadmin@chino.io" "mattia@mattiamartinello.com") # Recipient addresses
mail_recipients=("mattia@mattiamartinello.com") # Recipient addresses
mail_subject="[pgpool@$HOSTNAME.test.dc.chino.io] FOLLOW EVENT: $failed_node_hostname -/-> $old_master_node_hostname --> $new_master_hostname" # Mail subject
mail_fail_subject_prepend="[!!! ---FAILURE--- !!!] "

# End confiugration
#########################################################################

. generic-functions.sh

# If the failed node was the primary node, change the mail subject
if [ $failed_node_id -eq $old_primary_node_id ] ; then
    mail_subject="[pgpool@$HOSTNAME.test.dc.chino.io] FAILED PRIMARY: $failed_node_hostname (Pgpool node ID $failed_node_id)"
fi

# Main function
main() {
    exec 5>&2
    start_seconds=$SECONDS
    start_time=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Execute failover
    msg
    msg "================================================================="
    msg "FOLLOW PRIMARY EVENT"
    msg "Target node: $failed_node_hostname (ID $failed_node_id)"
    msg "Old primary node: $old_master_node_hostname (ID $old_master_node_id)"
    msg "NEW PRIMARY NODE: $new_master_hostname (ID $new_master_node_id)"
    msg "================================================================="
    msg ""
    msg ""
    
    # Show Pgpool pool nodes
    # FIXME: this does not work because of Bash (it removes the '' from the command)
    #msg "PGPOOL POOL NODES STATUS:"
    #cmd_exec "$pgpool_show_pool_command"
    #msg ""
    #msg ""

    # If the failed node was the primary node, execute promotion on a standby node
    if [ $failed_node_id -ne $old_primary_node_id ] ; then
        # Show cluster status
        msg "CLUSTER STATUS FROM $failed_node_hostname PERSPECTIVE:"
        cmd_exec "$cluster_show_command"
        msg ""
        msg ""
        
        # Check if the target node is on recovery, else skip and return error
        in_recovery=$( $ssh_command postgres@${failed_node_hostname} 'psql -t -c "select pg_is_in_recovery();"' | head -1 | awk '{print $1}' )
        msg "pg_is_in_recovery on $failed_node_hostname is: $in_recovery"
        if [ "$in_recovery" = "t" ]; then
            msg "node $failed_node_hostname is in recovery, continue to follow command ..."
            msg ""
            msg ""
        else
            msg "node $failed_node_hostname is not in recovery, probably a degenerated master, skip it"
            msg ""
            msg "*** Please check and fix manually! ***"
            msg ""
            msg ""
            return 1
        fi
    
    	# Execute follow command
        msg "Standby node to order follow on: $failed_node_hostname (Pgpool node ID $failed_node_id)"
        msg "Old primary node ID: $old_primary_node_id"
        msg "New primary node ID: $new_master_hostname (Pgpool node ID $new_master_node_id)"
        msg ""
        msg "EXECUTING FOLLOW ON $failed_node_hostname TO $new_master_hostname ..."
        msg ""
        cmd_exec "$follow_command"
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
        msg "CLUSTER STATUS AFTER FOLLOW FROM $failed_node_hostname PERSPECTIVE:"
        cmd_exec "$cluster_show_command"
        msg ""
        msg ""
        
        # TODO: we should check if the standby follow worked or not, if not we should then do a standby clone comman
        
        # Sleep some seconds
        sleep 10
        
        # Attach the node
        msg "ATTACHING THE NODE $failed_node_id IN THE PGPOOL POOL ..."
        cmd_exec "$pgpool_attach_node_command"
        msg ""
        msg ""
        
        # Show Pgpool pool nodes
        #msg "PGPOOL POOL NODES STATUS AFTER THE ATTACH:"
        #cmd_exec "$pgpool_show_pool_command"
        #msg ""
        #msg ""
        
        # If error during promotion, print and return error

        if [ "$status" -ne "0" ]; then
            msg "*** ERROR DURING FOLLOW! ***"
            msg "Promotion command exit code: $status"
            msg "Please check and fix manually!"
            msg ""
            msg "CLUSTER STATUS FROM $failed_node_hostname PERSPECTIVE:"
            cmd_exec "$cluster_show_command"
            msg ""
            msg ""
            return $status
        fi

    # Else I don't need to promote any node because the failed node was a standby
    else    
        msg "$failed_node_hostname (Pgpool node ID $failed_node_id) is the failed primary node."
        msg "We should prevent failed master to restart here, so that we can investigate the issue!"
        msg ""
        msg "*** Please check and fix manually! ***"
        msg ""
        msg ""
        return 0
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
