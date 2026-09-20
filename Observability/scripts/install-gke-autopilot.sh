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

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Observability Stack Installation for GKE Autopilot       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

# Check if running on GKE
if ! kubectl get nodes -o jsonpath='{.items[0].spec.providerID}' 2>/dev/null | grep -q "gce"; then
    echo -e "${YELLOW}Warning: This doesn't appear to be a GKE cluster.${NC}"
    read -p "Continue anyway? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        exit 0
    fi
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed!${NC}"
echo ""

# Display GKE Autopilot limitations
echo -e "${YELLOW}GKE Autopilot Limitations:${NC}"
echo "  • Node Exporter: ❌ Disabled (requires hostNetwork/hostPID)"
echo "  • Promtail: ❌ Disabled (requires privileged access)"
echo "  • Prometheus: ✅ Enabled (with cAdvisor for container metrics)"
echo "  • Grafana: ✅ Enabled"
echo "  • Loki: ✅ Enabled (configure Cloud Logging export)"
echo "  • Tempo: ✅ Enabled"
echo "  • AlertManager: ✅ Enabled"
echo "  • kube-state-metrics: ✅ Enabled"
echo ""
echo -e "${BLUE}Recommendation: Use Google Cloud Managed Service for Prometheus${NC}"
echo -e "${BLUE}for full node metrics: https://cloud.google.com/stackdriver/docs/managed-prometheus${NC}"
echo ""

read -p "Continue with installation? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    exit 0
fi

# Create namespace
echo -e "${YELLOW}Creating namespace ${NAMESPACE}...${NC}"
kubectl create namespace ${NAMESPACE} 2>/dev/null || echo "Namespace already exists"

# Install the stack using GKE Autopilot overlay
echo -e "${YELLOW}Installing observability stack (GKE Autopilot compatible)...${NC}"
kubectl apply -k ./k8s/overlays/gke-autopilot/

# Wait a moment for resources to be created
echo -e "${YELLOW}Waiting for pods to start...${NC}"
sleep 10

# Verify installation
echo -e "${YELLOW}Verifying installation (this may take a few minutes)...${NC}"
kubectl wait --for=condition=ready pod -l app=prometheus -n ${NAMESPACE} --timeout=300s 2>/dev/null || echo "Prometheus starting..."
kubectl wait --for=condition=ready pod -l app=grafana -n ${NAMESPACE} --timeout=300s 2>/dev/null || echo "Grafana starting..."
kubectl wait --for=condition=ready pod -l app=loki -n ${NAMESPACE} --timeout=300s 2>/dev/null || echo "Loki starting..."

echo -e "\n${YELLOW}Checking final status...${NC}"
sleep 5

# Display status
echo -e "\n${GREEN}Installation complete!${NC}\n"

echo -e "${YELLOW}Component Status:${NC}"
kubectl get pods -n ${NAMESPACE}

echo -e "\n${YELLOW}Services:${NC}"
kubectl get svc -n ${NAMESPACE}

echo -e "\n${YELLOW}PVCs:${NC}"
kubectl get pvc -n ${NAMESPACE}

echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Access Instructions:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Grafana:${NC}"
echo -e "  ${GREEN}kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000${NC}"
echo -e "  Then visit: ${BLUE}http://localhost:3000${NC}"
echo -e "  Default credentials: ${YELLOW}admin/admin${NC} ${RED}(change immediately!)${NC}"
echo ""
echo -e "${YELLOW}Prometheus:${NC}"
echo -e "  ${GREEN}kubectl port-forward -n ${NAMESPACE} svc/prometheus 9090:9090${NC}"
echo -e "  Then visit: ${BLUE}http://localhost:9090${NC}"
echo ""
echo -e "${YELLOW}AlertManager:${NC}"
echo -e "  ${GREEN}kubectl port-forward -n ${NAMESPACE} svc/alertmanager 9093:9093${NC}"
echo -e "  Then visit: ${BLUE}http://localhost:9093${NC}"
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo -e "${YELLOW}Important Notes for GKE Autopilot:${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
echo ""
echo "1. ${YELLOW}Node Metrics:${NC}"
echo "   Use cAdvisor metrics from kubelet (included in Prometheus config)"
echo "   Or enable Google Cloud Managed Service for Prometheus"
echo ""
echo "2. ${YELLOW}Log Collection:${NC}"
echo "   Configure Cloud Logging export to Loki:"
echo "   https://cloud.google.com/logging/docs/export"
echo ""
echo "3. ${YELLOW}Container Metrics:${NC}"
echo "   cAdvisor provides: CPU, memory, network for containers"
echo "   Available via: /api/v1/nodes/\${node}/proxy/metrics/cadvisor"
echo ""
echo "4. ${YELLOW}Kubernetes Metrics:${NC}"
echo "   kube-state-metrics provides: pod, deployment, node status"
echo ""
echo -e "${GREEN}Documentation: ./docs/${NC}"
echo -e "${GREEN}GKE Docs: ./docs/GKE-AUTOPILOT.md${NC}"
echo ""
echo -e "${GREEN}Happy Monitoring! 🎉${NC}"

