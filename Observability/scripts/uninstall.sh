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

echo -e "${YELLOW}This will uninstall the observability stack.${NC}"
read -p "Are you sure? (yes/no): " -r
echo

if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

read -p "Do you want to preserve PersistentVolumeClaims (data)? (yes/no): " -r
PRESERVE_DATA=$REPLY
echo

# Uninstall Helm release
echo -e "${YELLOW}Uninstalling Helm release...${NC}"
helm uninstall ${RELEASE_NAME} -n ${NAMESPACE} || true

if [[ ! $PRESERVE_DATA =~ ^[Yy]es$ ]]; then
    echo -e "${YELLOW}Deleting namespace and all resources including PVCs...${NC}"
    kubectl delete namespace ${NAMESPACE}
    echo -e "${GREEN}All resources deleted.${NC}"
else
    echo -e "${YELLOW}Deleting resources but preserving PVCs...${NC}"
    kubectl delete all --all -n ${NAMESPACE}
    echo -e "${GREEN}Resources deleted. PVCs preserved in namespace ${NAMESPACE}${NC}"
    echo -e "${YELLOW}Existing PVCs:${NC}"
    kubectl get pvc -n ${NAMESPACE}
    echo ""
    echo "To completely remove including data, run:"
    echo -e "${RED}kubectl delete namespace ${NAMESPACE}${NC}"
fi

echo -e "${GREEN}Uninstall complete.${NC}"

