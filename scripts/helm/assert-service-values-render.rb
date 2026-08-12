#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'

render_path, fixture_name = ARGV
abort 'usage: assert-service-values-render.rb <render.yaml> <fixture-name>' unless render_path && fixture_name

def load_docs(path)
  YAML.load_stream(File.read(path)).compact
end

def find_doc(docs, kind, name)
  docs.find { |doc| doc['kind'] == kind && doc.dig('metadata', 'name') == name }
end

def assert(condition, message)
  abort "[error] #{message}" unless condition
end

expectations = {
  'minimal-single' => {
    name: 'minimal-api',
    image: 'registry.test/platform/minimal-api@sha256:1111111111111111111111111111111111111111111111111111111111111111',
    port: 8080,
    health_path: '/healthz',
    cpu_request: '50m',
    memory_request: '64Mi',
    cpu_limit: '250m',
    memory_limit: '128Mi',
    replicas: 1,
    pdb: false,
    config: nil,
    secrets: []
  },
  'standard-config' => {
    name: 'config-api',
    image: 'registry.test/platform/config-api@sha256:2222222222222222222222222222222222222222222222222222222222222222',
    port: 9000,
    health_path: '/internal/ready',
    cpu_request: '100m',
    memory_request: '128Mi',
    cpu_limit: '500m',
    memory_limit: '256Mi',
    replicas: 2,
    pdb: true,
    config: { 'APP_MODE' => 'review', 'CACHE_TTL_SECONDS' => '30', 'LOG_LEVEL' => 'info' },
    secrets: []
  },
  'standard-secrets' => {
    name: 'secret-api',
    image: 'registry.test/platform/secret-api@sha256:3333333333333333333333333333333333333333333333333333333333333333',
    port: 8081,
    health_path: '/healthz',
    cpu_request: '100m',
    memory_request: '128Mi',
    cpu_limit: '500m',
    memory_limit: '256Mi',
    replicas: 2,
    pdb: true,
    config: nil,
    secrets: %w[database-credentials runtime-settings]
  },
  'large-profile' => {
    name: 'large-api',
    image: 'registry.test/platform/large-api@sha256:4444444444444444444444444444444444444444444444444444444444444444',
    port: 8080,
    health_path: '/status',
    cpu_request: '250m',
    memory_request: '256Mi',
    cpu_limit: '1000m',
    memory_limit: '512Mi',
    replicas: 2,
    pdb: true,
    config: nil,
    secrets: []
  }
}

expected = expectations.fetch(fixture_name)
docs = load_docs(render_path)
deployment = find_doc(docs, 'Deployment', expected[:name])
service = find_doc(docs, 'Service', expected[:name])
configmap = find_doc(docs, 'ConfigMap', "#{expected[:name]}-config")
pdb = find_doc(docs, 'PodDisruptionBudget', expected[:name])

assert(deployment, 'Deployment is missing')
assert(service, 'Service is missing')
assert(deployment.dig('spec', 'replicas') == expected[:replicas], 'replica count mismatch')
assert(service.dig('spec', 'type') == 'ClusterIP', 'Service is not ClusterIP')
assert(docs.none? { |doc| doc['kind'] == 'HorizontalPodAutoscaler' }, 'HPA rendered unexpectedly')
assert(docs.none? { |doc| doc['kind'] == 'Ingress' }, 'Ingress rendered unexpectedly')
assert(docs.none? { |doc| doc['kind'] == 'Secret' }, 'Secret rendered unexpectedly')
assert(expected[:pdb] ? pdb : pdb.nil?, 'PDB presence mismatch')

container = deployment.dig('spec', 'template', 'spec', 'containers').first
assert(container['image'] == expected[:image], 'container image mismatch')
assert(container.dig('ports', 0, 'containerPort') == expected[:port], 'container port mismatch')
assert(container.dig('startupProbe', 'httpGet', 'path') == expected[:health_path], 'startup path mismatch')
assert(container.dig('readinessProbe', 'httpGet', 'path') == expected[:health_path], 'readiness path mismatch')
assert(container.dig('livenessProbe', 'httpGet', 'path') == expected[:health_path], 'liveness path mismatch')
assert(container.dig('resources', 'requests', 'cpu') == expected[:cpu_request], 'CPU request mismatch')
assert(container.dig('resources', 'requests', 'memory') == expected[:memory_request], 'memory request mismatch')
assert(container.dig('resources', 'limits', 'cpu') == expected[:cpu_limit], 'CPU limit mismatch')
assert(container.dig('resources', 'limits', 'memory') == expected[:memory_limit], 'memory limit mismatch')

if expected[:config]
  assert(configmap, 'ConfigMap is missing')
  assert(configmap['data'] == expected[:config], 'ConfigMap data mismatch')
else
  assert(configmap.nil?, 'ConfigMap rendered unexpectedly')
end

secret_refs = Array(container['envFrom']).filter_map { |entry| entry.dig('secretRef', 'name') }
assert(secret_refs == expected[:secrets], 'existing Secret references mismatch')

puts "[ok] #{fixture_name} generated values reached the golden-path chart"
