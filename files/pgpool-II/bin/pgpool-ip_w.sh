#!/bin/bash
echo "Exec ip with params $@ at `date`"
sudo /usr/sbin/ip $@
exit $?
