#!/bin/bash
echo "Exec arping with params $@ at `date`"
sudo /usr/sbin/arping $@
exit $?
