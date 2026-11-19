#!/bin/sh
set -eu

install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
install -m 0600 -o deploy -g deploy /keys/id_ed25519.pub /home/deploy/.ssh/authorized_keys

install -d -m 0700 /run/sshd
install -d -m 0755 -o www-data -g www-data /run/php

ssh-keygen -A

service php8.2-fpm start
service nginx start
service cron start

exec /usr/sbin/sshd -D -e -p 2222 -o UsePAM=no -o PasswordAuthentication=no
