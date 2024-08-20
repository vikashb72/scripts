#!/usr/bin/env bash

sudo service vault stop
sudo rm -rf /opt/vault/{audit.log,tls} /opt/vault/data/{raft,vault.db}
rm -f ~/.vault-token ~/.vault.init.keys
sudo service vault start
