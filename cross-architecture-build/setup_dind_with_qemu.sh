#!/bin/bash
# uncomment to debug the script
# set -x

export BUILD_CLUSTER=${BUILD_CLUSTER:-"mycluster"}
export BUILD_CLUSTER_NAMESPACE=${BUILD_CLUSTER_NAMESPACE:-"build-arm"}
export IBMCLOUD_TARGET_REGION=${IBMCLOUD_TARGET_REGION:-"us-south"}

# if target region is in the 'ibm:yp:<region>' just keep the region part
REGION_SUBSET=$(echo "$IBMCLOUD_TARGET_REGION" | awk -F ':' '{print $3;}')
if [ -z "$REGION_SUBSET" ]; then
  echo "IBM Cloud Target Region is $IBMCLOUD_TARGET_REGION"
else
  export IBMCLOUD_TARGET_REGION=$REGION_SUBSET
  echo "IBM Cloud Target Region is $IBMCLOUD_TARGET_REGION. export IBMCLOUD_TARGET_REGION=$REGION_SUBSET done"
fi

echo "Logging in to build cluster account..."
ibmcloud login --apikey "$IBM_CLOUD_API_KEY" -r "$IBMCLOUD_TARGET_REGION"

if [ -z "$IBMCLOUD_TARGET_RESOURCE_GROUP" ]; then
  echo "Using default resource group" 
else
  ibmcloud target -g "$IBMCLOUD_TARGET_RESOURCE_GROUP"
fi

echo "Cluster list:"
ibmcloud ks clusters

echo "Running ibmcloud ks cluster-config -cluster "$BUILD_CLUSTER" --export"
CLUSTER_CONFIG_COMMAND=$(ibmcloud ks cluster-config -cluster "$BUILD_CLUSTER" --export)
echo "$CLUSTER_CONFIG_COMMAND"
eval $CLUSTER_CONFIG_COMMAND

echo "Checking cluster namespace $BUILD_CLUSTER_NAMESPACE"
if ! kubectl get namespace "$BUILD_CLUSTER_NAMESPACE"; then
  kubectl create namespace "$BUILD_CLUSTER_NAMESPACE"
fi

# Ensure there is a Docker server on the ${BUILD_CLUSTER}
if ! kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" rollout status -w deployment/docker-qemu; then
  echo "Preparing Docker server with QEMU inside"
  cat > docker-dind-qemu-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    run: docker
  name: docker-qemu
spec:
  replicas: 1
  selector:
    matchLabels:
      run: docker
  template:
    metadata:
      labels:
        run: docker
    spec:
      initContainers:
      - name: populate-qemu
        image: multiarch/qemu-user-static
        env:
        - name: QEMU_BIN_DIR
          value: '/qemu/bin'
        command: ['sh']
        args: ['-c', 'cp /*.sh /qemu/bin && cp /usr/bin/qemu-* /qemu/bin && chmod +x /qemu/bin/*']
        volumeMounts:
        - name: qemu
          mountPath: /qemu/bin
      - name: register-qemu
        image: multiarch/qemu-user-static:register
        env:
        - name: QEMU_BIN_DIR
          value: '/qemu/bin'
        command: ['sh']
        args: ['-c', '/register --reset']
        securityContext:
          privileged: true
        volumeMounts:
        - name: qemu
          mountPath: /qemu/bin
      containers:
      - name: docker
        image: docker:dind
        env:
        - name: DOCKER_TLS_CERTDIR
          value: ''
        - name: QEMU_BIN_DIR
          value: '/qemu/bin'
        resources: {}
        command: ['sh']
        args: ['-c', 'if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc; fi; ls -l /proc/sys/fs/binfmt_misc; dockerd-entrypoint.sh']
        securityContext:
          privileged: true
        volumeMounts:
        - name: qemu
          mountPath: /qemu/bin
      volumes:
      - name: qemu
        emptyDir: {}  
EOF
  echo "Installing Docker Server into build cluster..."
  kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" apply -f docker-dind-qemu-deployment.yaml
  kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" rollout status -w deployment/docker-qemu
fi

# Use port-forward to make the pod/port locally accessible
# Be sure to use a running POD (not an evicted one)
kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" get pods 
kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" port-forward $(kubectl --namespace "$BUILD_CLUSTER_NAMESPACE" get pods | grep docker | grep -i running | awk '{print $1;}') 2375:2375 > /dev/null 2>&1 &

while ! nc -z localhost 2375; do   
  sleep 0.1
done

export DOCKER_HOST='tcp://localhost:2375'

echo "Logging in to docker registry..."
ibmcloud cr login