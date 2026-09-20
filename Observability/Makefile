.PHONY: help install uninstall upgrade status clean lint validate

NAMESPACE := observability
RELEASE_NAME := observability
HELM_CHART := ./helm/observability

help:
	@echo "Available targets:"
	@echo "  install      - Install the observability stack"
	@echo "  uninstall    - Uninstall the observability stack"
	@echo "  upgrade      - Upgrade the observability stack"
	@echo "  status       - Check status of all components"
	@echo "  lint         - Lint Kubernetes manifests and Helm charts"
	@echo "  validate     - Validate configurations"
	@echo "  clean        - Clean up resources"
	@echo "  port-forward - Setup port forwarding for dashboards"

install:
	@echo "Creating namespace..."
	kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@echo "Installing observability stack..."
	helm install $(RELEASE_NAME) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--values $(HELM_CHART)/values.yaml

uninstall:
	@echo "Uninstalling observability stack..."
	helm uninstall $(RELEASE_NAME) --namespace $(NAMESPACE)

upgrade:
	@echo "Upgrading observability stack..."
	helm upgrade $(RELEASE_NAME) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--values $(HELM_CHART)/values.yaml

status:
	@echo "Checking status..."
	kubectl get pods -n $(NAMESPACE)
	@echo "\nServices:"
	kubectl get svc -n $(NAMESPACE)
	@echo "\nPVCs:"
	kubectl get pvc -n $(NAMESPACE)

lint:
	@echo "Linting Helm charts..."
	helm lint $(HELM_CHART)
	@echo "Validating Kubernetes manifests..."
	kubectl apply --dry-run=client -k ./k8s/base/

validate:
	@echo "Validating Prometheus config..."
	kubectl create configmap prometheus-config-test --from-file=./k8s/base/prometheus/config.yaml --dry-run=client -o yaml > /dev/null
	@echo "Validating AlertManager config..."
	kubectl create configmap alertmanager-config-test --from-file=./k8s/base/alertmanager/config.yaml --dry-run=client -o yaml > /dev/null

clean:
	@echo "Cleaning up..."
	kubectl delete namespace $(NAMESPACE) --ignore-not-found=true

port-forward:
	@echo "Setting up port forwarding..."
	@echo "Grafana will be available at http://localhost:3000"
	@echo "Prometheus will be available at http://localhost:9090"
	@echo "AlertManager will be available at http://localhost:9093"
	kubectl port-forward -n $(NAMESPACE) svc/grafana 3000:3000 & \
	kubectl port-forward -n $(NAMESPACE) svc/prometheus 9090:9090 & \
	kubectl port-forward -n $(NAMESPACE) svc/alertmanager 9093:9093

kill-port-forward:
	@echo "Killing port forward processes..."
	pkill -f "kubectl port-forward" || true

