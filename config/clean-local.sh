#!/bin/bash

set -e

K3S_TOKEN=$(cat ./tmp/k3s.token) podman compose -f docker-compose.yaml down

podman volume rm workshop-vault-agent-devs_k3s-agent
podman volume rm workshop-vault-agent-devs_k3s-server
rm -rf tmp
rm -rf secrets