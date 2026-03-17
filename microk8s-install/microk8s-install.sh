#!/bin/bash
set -e

echo "=== Installing MicroK8s ==="
sudo snap install microk8s --classic

echo "=== Waiting for MicroK8s to be ready ==="
microk8s status --wait-ready

echo "=== Adding current user to microk8s group ==="
sudo usermod -a -G microk8s $USER
sudo chown -f -R $USER ~/.kube

echo "=== Creating kubectl alias ==="
sudo snap alias microk8s.kubectl kubectl

echo "=== Enabling DNS and storage add-ons ==="
microk8s enable dns storage

echo "=== Enabling ingress controller ==="
microk8s enable ingress

echo "=== Setup complete! ==="
echo "IMPORTANT: Please log out and log back in (or run 'newgrp microk8s') to refresh your group membership before using kubectl."
