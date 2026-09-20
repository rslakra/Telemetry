#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="observability"
RELEASE_NAME="observability"
HELM_CHART="./helm/observability"

echo -e "${GREEN}Starting observability stack installation...${NC}"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}kubectl not found. Please install kubectl.${NC}"
    exit 1
fi

if ! command -v helm &> /dev/null; then
    echo -e "${RED}helm not found. Please install Helm 3.${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Cannot connect to Kubernetes cluster. Please check your kubeconfig.${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites check passed!${NC}"

# Create namespace
echo -e "${YELLOW}Creating namespace ${NAMESPACE}...${NC}"
kubectl create namespace ${NAMESPACE} 2>/dev/null || echo "Namespace already exists"

# Install the stack using kubectl with kustomize
echo -e "${YELLOW}Installing observability stack...${NC}"
kubectl apply -k ./k8s/base/

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

echo -e "\n${YELLOW}Access Instructions:${NC}"
echo -e "
To access Grafana:
${GREEN}kubectl port-forward -n ${NAMESPACE} svc/grafana 3000:3000${NC}
Then visit: http://localhost:3000
Default credentials: admin/admin (change immediately!)

To access Prometheus:
${GREEN}kubectl port-forward -n ${NAMESPACE} svc/prometheus 9090:9090${NC}
Then visit: http://localhost:9090

To access AlertManager:
${GREEN}kubectl port-forward -n ${NAMESPACE} svc/alertmanager 9093:9093${NC}
Then visit: http://localhost:9093
"

echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Change Grafana admin password"
echo "2. Configure AlertManager with your Slack/PagerDuty credentials"
echo "3. Import additional dashboards from grafana.com"
echo "4. Configure alerts for your applications"
echo ""
echo "Documentation: ./docs/"
echo ""
echo -e "${GREEN}Happy monitoring!${NC}"

