#!/bin/sh
set -e

SCRIPT=`basename "$0"`

sudo apt-get update
sudo apt-get -y install apt-transport-https ca-certificates curl software-properties-common

# Using Docker CE directly provided by Docker
echo "[INFO] [${SCRIPT}] Setup docker"
cd /tmp/
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

sudo add-apt-repository "deb [arch=arm64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
sudo apt-get update
apt-cache policy docker-ce
sudo apt-get update 

sudo apt-get install -y docker-ce
sudo usermod -a -G docker ubuntu
