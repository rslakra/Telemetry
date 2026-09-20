#!/usr/bin/env python3
"""
Sample instrumented application demonstrating:
- Prometheus metrics
- Structured logging for Loki
- OpenTelemetry tracing for Tempo
"""

from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.flask import FlaskInstrumentor
import logging
import json
import time
import os
import random

# Setup structured logging for Loki
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_obj = {
            'timestamp': self.formatTime(record),
            'level': record.levelname,
            'message': record.getMessage(),
            'service': 'sample-app',
            'environment': os.getenv('ENVIRONMENT', 'development')
        }
        if hasattr(record, 'user_id'):
            log_obj['user_id'] = record.user_id
        if hasattr(record, 'endpoint'):
            log_obj['endpoint'] = record.endpoint
        return json.dumps(log_obj)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logger.handlers = [handler]

# Setup OpenTelemetry tracing
trace.set_tracer_provider(TracerProvider())
tracer = trace.get_tracer(__name__)

otlp_endpoint = os.getenv('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://tempo.observability.svc.cluster.local:4317')
otlp_exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))

# Setup Prometheus metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

ACTIVE_REQUESTS = Gauge(
    'http_requests_active',
    'Active HTTP requests'
)

ERROR_RATE = Counter(
    'http_errors_total',
    'Total HTTP errors',
    ['method', 'endpoint', 'error_type']
)

# Create Flask app
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)

@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'}), 200

@app.route('/ready')
def ready():
    """Readiness check endpoint"""
    return jsonify({'status': 'ready'}), 200

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/api/users', methods=['GET'])
def get_users():
    """Sample API endpoint with full observability"""
    ACTIVE_REQUESTS.inc()
    start_time = time.time()
    
    with tracer.start_as_current_span("get_users") as span:
        try:
            # Simulate database query
            with tracer.start_as_current_span("database_query"):
                time.sleep(random.uniform(0.01, 0.1))
                users = [
                    {'id': 1, 'name': 'Alice'},
                    {'id': 2, 'name': 'Bob'},
                    {'id': 3, 'name': 'Charlie'}
                ]
                span.set_attribute("user_count", len(users))
            
            # Log the request
            logger.info("Users retrieved successfully", extra={
                'endpoint': '/api/users',
                'user_count': len(users)
            })
            
            # Record metrics
            duration = time.time() - start_time
            REQUEST_LATENCY.labels(method='GET', endpoint='/api/users').observe(duration)
            REQUEST_COUNT.labels(method='GET', endpoint='/api/users', status='200').inc()
            
            return jsonify({'users': users}), 200
            
        except Exception as e:
            # Log error
            logger.error(f"Error retrieving users: {str(e)}", extra={
                'endpoint': '/api/users',
                'error': str(e)
            })
            
            # Record error metrics
            ERROR_RATE.labels(method='GET', endpoint='/api/users', error_type=type(e).__name__).inc()
            REQUEST_COUNT.labels(method='GET', endpoint='/api/users', status='500').inc()
            
            # Add error to span
            span.set_attribute("error", True)
            span.set_attribute("error.message", str(e))
            
            return jsonify({'error': 'Internal server error'}), 500
            
        finally:
            ACTIVE_REQUESTS.dec()

@app.route('/api/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    """Get specific user"""
    ACTIVE_REQUESTS.inc()
    start_time = time.time()
    
    with tracer.start_as_current_span("get_user") as span:
        span.set_attribute("user_id", user_id)
        
        try:
            # Simulate database query
            with tracer.start_as_current_span("database_query"):
                time.sleep(random.uniform(0.01, 0.05))
                user = {'id': user_id, 'name': f'User{user_id}'}
            
            # Log
            logger.info("User retrieved", extra={
                'endpoint': f'/api/users/{user_id}',
                'user_id': user_id
            })
            
            # Metrics
            duration = time.time() - start_time
            REQUEST_LATENCY.labels(method='GET', endpoint='/api/users/:id').observe(duration)
            REQUEST_COUNT.labels(method='GET', endpoint='/api/users/:id', status='200').inc()
            
            return jsonify({'user': user}), 200
            
        finally:
            ACTIVE_REQUESTS.dec()

@app.route('/api/slow', methods=['GET'])
def slow_endpoint():
    """Intentionally slow endpoint for testing"""
    ACTIVE_REQUESTS.inc()
    start_time = time.time()
    
    with tracer.start_as_current_span("slow_endpoint"):
        try:
            # Simulate slow operation
            time.sleep(2)
            
            logger.warning("Slow endpoint accessed", extra={
                'endpoint': '/api/slow',
                'duration': 2
            })
            
            duration = time.time() - start_time
            REQUEST_LATENCY.labels(method='GET', endpoint='/api/slow').observe(duration)
            REQUEST_COUNT.labels(method='GET', endpoint='/api/slow', status='200').inc()
            
            return jsonify({'message': 'This was slow'}), 200
            
        finally:
            ACTIVE_REQUESTS.dec()

@app.route('/api/error', methods=['GET'])
def error_endpoint():
    """Endpoint that generates errors for testing"""
    ACTIVE_REQUESTS.inc()
    
    with tracer.start_as_current_span("error_endpoint") as span:
        try:
            # Simulate random errors
            if random.random() < 0.7:  # 70% error rate
                raise Exception("Random error for testing")
            
            REQUEST_COUNT.labels(method='GET', endpoint='/api/error', status='200').inc()
            return jsonify({'message': 'Success'}), 200
            
        except Exception as e:
            logger.error("Intentional error", extra={
                'endpoint': '/api/error',
                'error': str(e)
            })
            
            ERROR_RATE.labels(method='GET', endpoint='/api/error', error_type='Exception').inc()
            REQUEST_COUNT.labels(method='GET', endpoint='/api/error', status='500').inc()
            
            span.set_attribute("error", True)
            span.set_attribute("error.message", str(e))
            
            return jsonify({'error': str(e)}), 500
            
        finally:
            ACTIVE_REQUESTS.dec()

if __name__ == '__main__':
    port = int(os.getenv('PORT', '8080'))
    app.run(host='0.0.0.0', port=port)

