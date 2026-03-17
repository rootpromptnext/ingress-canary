# Ingress Canary Demo with MicroK8s

This repository demonstrates how to set up **MicroK8s** and run a simple **canary deployment** using ingress.  
You’ll deploy two versions of a demo app (`v1` and `v2`) and configure ingress to send ~20% of traffic to the canary.

## Install MicroK8s Manually

```bash
# Install MicroK8s
sudo snap install microk8s --classic

# Wait until MicroK8s is ready
microk8s status --wait-ready

# Refresh group membership
newgrp microk8s

# Verify status
microk8s status

# Create kubectl alias
sudo snap alias microk8s.kubectl kubectl

# Check cluster nodes
kubectl get nodes

# Enable DNS, storage, and ingress
microk8s enable dns storage
microk8s enable ingress
```

### You can run script  to install microk8s from below repo as well 

## Clone Repo and Run Script

```bash
git clone https://github.com/rootpromptnext/ingress-canary.git
cd ingress-canary/
```

Run the provided install script:

```bash
bash microk8s-install/microk8s-install.sh
```

Script contents:

```bash
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
```

## Expose Ingress via NodePort

By default, MicroK8s ingress doesn’t create a Service. Add one manually:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-ingress-microk8s-controller
  namespace: ingress
spec:
  type: NodePort
  selector:
    name: nginx-ingress-microk8s
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
    protocol: TCP
```

Apply it:

```bash
kubectl apply -f ingress-service.yaml
kubectl -n ingress get all
```

Find your node IP:

```bash
hostname -I
ip a
```

For local testing, add an entry in `/etc/hosts`:

```bash
echo "10.10.0.2 demo.local" | sudo tee -a /etc/hosts
```

## Deploy Applications

### Production (v1)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production
  labels:
    app: demo
    version: v1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
      version: v1
  template:
    metadata:
      labels:
        app: demo
        version: v1
    spec:
      containers:
      - name: demo
        image: hashicorp/http-echo:0.2.3
        args:
        - "-text=Hello from v1"
        - "-listen=:80"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: demo-service
spec:
  selector:
    app: demo
    version: v1
  ports:
  - port: 80
    targetPort: 80
```

### Canary (v2)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: canary
  labels:
    app: demo
    version: v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo
      version: v2
  template:
    metadata:
      labels:
        app: demo
        version: v2
    spec:
      containers:
      - name: demo
        image: hashicorp/http-echo:0.2.3
        args:
        - "-text=Hello from v2"
        - "-listen=:80"
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: canary-service
spec:
  selector:
    app: demo
    version: v2
  ports:
  - port: 80
    targetPort: 80
```
## Ingress Rules

### Production Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: demo.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: demo-service
            port:
              number: 80
```

### Canary Ingress
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: canary-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/canary: "true"
    nginx.ingress.kubernetes.io/canary-weight: "20"
spec:
  rules:
  - host: demo.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: canary-service
            port:
              number: 80
```
## Test Canary Deployment

```bash
curl http://demo.local:30080
```

You should see:
- **Hello from v1** most of the time (production).  
- **Hello from v2** about 20% of the time (canary).

## Running on Amazon EKS

If you prefer to use **Amazon EKS** instead of MicroK8s, the workflow is very similar — but the cluster setup and ingress exposure differ.

### Create an EKS Cluster
Use `eksctl` to provision a managed Kubernetes cluster:

```bash
eksctl create cluster \
  --name ingress-canary-demo \
  --region us-east-1 \
  --nodes 2
```

Update your kubeconfig so `kubectl` points to the new cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name ingress-canary-demo
kubectl get nodes
```

### Install NGINX Ingress Controller
Unlike MicroK8s, EKS does not ship with ingress by default. Install it via Helm:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

Verify the controller:

```bash
kubectl get pods -n ingress-nginx
```

### Expose Ingress
On EKS, the ingress controller automatically creates a **LoadBalancer Service**:

```bash
kubectl get svc -n ingress-nginx
```

You’ll see an `EXTERNAL-IP` (AWS ELB DNS name). Use that instead of `demo.local:30080`.

### Host Mapping
For local testing, map the ELB DNS name to `demo.local` in `/etc/hosts`:

```bash
echo "<ELB-DNS-NAME> demo.local" | sudo tee -a /etc/hosts
```

### Deploy Applications
Apply the same manifests (`deploy-v1.yaml`, `deploy-v2.yaml`, `demo-ingress.yaml`, `canary-ingress.yaml`).  
No changes are needed — the YAMLs are portable between MicroK8s and EKS.

```bash
kubectl apply -f manifests/
```

### Test Canary Deployment
```bash
curl http://demo.local
```

You should see:
- **Hello from v1** most of the time (production).  
- **Hello from v2** about 20% of the time (canary).
