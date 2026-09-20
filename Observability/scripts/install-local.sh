#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="observability"

echo -e "${BLUE}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Observability Stack - Local Development Setup       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}❌ Cannot connect to Kubernetes cluster.${NC}"
    echo -e "${YELLOW}Please start a local cluster first:${NC}"
    echo ""
    echo "  ${GREEN}Docker Desktop:${NC} Enable Kubernetes in Settings"
    echo "  ${GREEN}Minikube:${NC} minikube start --cpus=4 --memory=8192"
    echo "  ${GREEN}kind:${NC} kind create cluster --name observability"
    echo "  ${GREEN}k3d:${NC} k3d cluster create observability"
    echo ""
    exit 1
fi

# Detect cluster type
CLUSTER_TYPE="unknown"
if kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -q "docker-desktop"; then
    CLUSTER_TYPE="Docker Desktop"
elif kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null | grep -q "minikube"; then
    CLUSTER_TYPE="Minikube"
elif kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null | grep -q "kind"; then
    CLUSTER_TYPE="kind"
elif kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null | grep -q "k3s"; then
    CLUSTER_TYPE="k3d/k3s"
fi

echo -e "${GREEN}✓ Kubernetes cluster detected: ${CLUSTER_TYPE}${NC}"

# Check available resources
NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo -e "${GREEN}✓ Nodes available: ${NODE_COUNT}${NC}"

echo -e "${GREEN}✓ Prerequisites check passed!${NC}"
echo ""

# Display what will be installed
echo -e "${YELLOW}Installing components:${NC}"
echo "  ✅ Prometheus (metrics collection)"
echo "  ✅ Grafana (visualization)"
echo "  ✅ Loki (log aggregation)"
echo "  ✅ Tempo (distributed tracing)"
echo "  ✅ AlertManager (alerting)"
echo "  ✅ Node Exporter (node metrics)"
echo "  ✅ kube-state-metrics (k8s metrics)"
echo "  ✅ Promtail (log collection)"
echo ""
echo -e "${YELLOW}Resource requirements:${NC}"
echo "  • Memory: ~2.5GB"
echo "  • Storage: ~42GB"
echo "  • CPU: 2-4 cores recommended"
echo ""

read -p "Continue with installation? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Create namespace
echo -e "${YELLOW}Creating namespace ${NAMESPACE}...${NC}"
kubectl create namespace ${NAMESPACE} 2>/dev/null || echo "Namespace already exists"

# Create local overlay with reduced resources
echo -e "${YELLOW}Configuring for local environment...${NC}"
mkdir -p ./k8s/overlays/local

cat > ./k8s/overlays/local/kustomization.yaml <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: observability

resources:
  - ../../base/

# Reduce replicas for local development
patches:
  # Prometheus: 1 replica, reduced resources
  - target:
      kind: StatefulSet
      name: prometheus
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "1Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "2Gi"
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "10Gi"

  # Grafana: 1 replica
  - target:
      kind: Deployment
      name: grafana
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1

  # Loki: 1 replica, reduced resources
  - target:
      kind: StatefulSet
      name: loki
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "512Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "1Gi"
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "10Gi"

  # Tempo: reduced resources
  - target:
      kind: StatefulSet
      name: tempo
    patch: |
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "512Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "1Gi"
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "5Gi"

  # AlertManager: 1 replica
  - target:
      kind: Deployment
      name: alertmanager
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1

  # Remove ServiceMonitor (requires Prometheus Operator)
  - target:
      kind: ServiceMonitor
    patch: |
      \$patch: delete

  # Disable HPA for local (not needed)
  - target:
      kind: HorizontalPodAutoscaler
    patch: |
      \$patch: delete
EOF

# Install the stack
echo -e "${YELLOW}Installing observability stack...${NC}"
echo -e "${BLUE}This will take 5-10 minutes. Please be patient...${NC}"
echo ""

kubectl apply -k ./k8s/overlays/local/

# Wait for resources to be created
echo -e "${YELLOW}Waiting for resources to be created...${NC}"
sleep 15

# Show initial status
echo -e "\n${YELLOW}Initial status:${NC}"
kubectl get pods -n ${NAMESPACE}

# Wait for key components
echo -e "\n${YELLOW}Waiting for components to become ready...${NC}"
echo -e "${BLUE}(This may take several minutes as images are pulled)${NC}"
echo ""

# Function to wait with spinner
wait_for_component() {
    local component=$1
    local label=$2
    echo -ne "${YELLOW}⏳ Waiting for ${component}...${NC}"
    
    timeout=300
    elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if kubectl wait --for=condition=ready pod -l app=${label} -n ${NAMESPACE} --timeout=10s &>/dev/null; then
            echo -e "\r${GREEN}✓ ${component} is ready!${NC}                    "
            return 0
        fi
        echo -ne "\r${YELLOW}⏳ Waiting for ${component}... (${elapsed}s)${NC}"
        sleep 5
        elapsed=$((elapsed + 5))
    done
    echo -e "\r${YELLOW}⚠ ${component} taking longer than expected${NC}          "
    return 1
}

# Wait for each component
wait_for_component "Prometheus" "prometheus"
wait_for_component "Grafana" "grafana"
wait_for_component "Loki" "loki"
wait_for_component "AlertManager" "alertmanager"
wait_for_component "kube-state-metrics" "kube-state-metrics"

echo ""

# Display final status
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Installation Complete! 🎉${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Component Status:${NC}"
kubectl get pods -n ${NAMESPACE}

echo -e "\n${YELLOW}Services:${NC}"
kubectl get svc -n ${NAMESPACE}

echo -e "\n${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Access Your Dashboards:${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}1. Grafana (Visualization)${NC}"
echo -e "   Run: ${GREEN}kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000${NC}"
echo -e "   Then visit: ${BLUE}http://localhost:3000${NC}"
echo -e "   Login: ${YELLOW}admin / admin${NC} ${RED}(change password on first login!)${NC}"
echo ""

echo -e "${YELLOW}2. Prometheus (Metrics)${NC}"
echo -e "   Run: ${GREEN}kubectl port-forward -n ${NAMESPACE} svc/prometheus 9090:9090${NC}"
echo -e "   Then visit: ${BLUE}http://localhost:9090${NC}"
echo ""

echo -e "${YELLOW}3. AlertManager (Alerts)${NC}"
echo -e "   Run: ${GREEN}kubectl port-forward -n ${NAMESPACE} svc/alertmanager 9093:9093${NC}"
echo -e "   Then visit: ${BLUE}http://localhost:9093${NC}"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Quick Test:${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Deploy sample instrumented application:${NC}"
echo -e "   ${GREEN}kubectl apply -f examples/sample-app/deployment.yaml${NC}"
echo ""

echo -e "${YELLOW}Generate test traffic:${NC}"
echo -e "   ${GREEN}kubectl port-forward svc/sample-app 8080:80${NC}"
echo -e "   ${GREEN}curl http://localhost:8080/api/users${NC}"
echo ""

echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. Access Grafana and change the admin password"
echo "2. Explore pre-configured dashboards"
echo "3. Deploy the sample app to see metrics, logs, and traces"
echo "4. Read the docs: ${GREEN}docs/LOCAL-SETUP.md${NC}"
echo ""

echo -e "${YELLOW}Useful Commands:${NC}"
echo "  ${GREEN}kubectl get pods -n ${NAMESPACE}${NC}           # Check status"
echo "  ${GREEN}kubectl logs -f deployment/grafana -n ${NAMESPACE}${NC}  # View logs"
echo "  ${GREEN}./scripts/uninstall.sh${NC}                     # Uninstall"
echo ""

echo -e "${GREEN}Happy Local Development! 🚀${NC}"

