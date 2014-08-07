#!/bin/bash
set -e

export OS_USERNAME=admin
export OS_PASSWORD=Passw0rd
export OS_TENANT_NAME=admin
export OS_AUTH_URL=http://127.0.0.1:5000/v2.0

nova flavor-delete 42
nova flavor-create m1.nano 42 256 3 1

nova flavor-delete 84
nova flavor-create m1.micro 84 300 4 1

nova flavor-delete 451
nova flavor-create m1.heat 451 512 5 1

