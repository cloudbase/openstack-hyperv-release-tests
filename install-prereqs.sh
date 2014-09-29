#!/bin/bash
set -e

# Ubuntu only ATM
# TODO Add CentOS / Fedora support

sudo apt-get update
sudo apt-get install software-properties-common python-software-properties -y
sudo add-apt-repository cloud-archive:icehouse -y
sudo apt-get update
sudo apt-get dist-upgrade -y
sudo apt-get install -y realpath python-yaml python-pip

sudo pip install pywinrm
sudo pip install -U setuptools
# Make sure to install MongoDB from cloud-archive on 12.04
# As a version > 2.4 is needed
sudo pip install -U pymongo

# TODO The following needs to be added after stack.sh and before Tempest runs
# sudo ovs-vsctl add-br br-eth1
# ovs-vsctl add-port br-eth1 eth1
# sudo ovs-vsctl add-port br-ex eth2
