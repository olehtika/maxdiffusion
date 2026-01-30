#!/bin/bash
#
# Script to run on each individual node manually
# Usage: ./run_node.sh <node_rank> <coordinator_ip> <num_nodes>
#

set -e

if [ $# -lt 3 ]; then
    echo "Usage: $0 <node_rank> <coordinator_ip> <num_nodes> [additional_args...]"
    echo "Example: $0 0 192.168.1.100 2"
    exit 1
fi

NODE_RANK=$1
COORDINATOR_IP=$2
NNODES=$3
shift 3

# Configuration
IMAGE_TAG="jianhan-wan-multinode-train:v1"
CODE_PATH="$(pwd)"
OUTPUT_DIR="${CODE_PATH}/output"
LOG_DIR="${OUTPUT_DIR}/logs"

timestamp=$(date +%Y%m%d-%H%M%S)
EXP_NAME="WAN_multinode_${timestamp}"

# Create directories with proper ownership
echo "Creating output directories..."
if ! mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" 2>/dev/null; then
    echo ""
    echo "ERROR: Cannot create output directories. Likely a permission issue."
    echo "The output directory may be owned by root from previous container runs."
    echo ""
    echo "Fix with:"
    echo "  sudo chown -R \$USER:\$(id -gn) ${OUTPUT_DIR}"
    echo ""
    echo "Or run the fix script:"
    echo "  ./fix_permissions.sh"
    echo ""
    exit 1
fi

# Verify we can write to the directories
if [ ! -w "${OUTPUT_DIR}" ] || [ ! -w "${LOG_DIR}" ]; then
    echo ""
    echo "ERROR: Cannot write to output directories."
    echo "The directories exist but are not writable by current user."
    echo ""
    echo "Current ownership:"
    ls -ld "${OUTPUT_DIR}" "${LOG_DIR}" 2>/dev/null
    echo ""
    echo "Fix with:"
    echo "  sudo chown -R \$USER:\$(id -gn) ${OUTPUT_DIR}"
    echo ""
    echo "Or run the fix script:"
    echo "  ./fix_permissions.sh"
    echo ""
    exit 1
fi

echo "  ✓ Output directory: ${OUTPUT_DIR}"
echo "  ✓ Log directory: ${LOG_DIR}"

# Coordinator port
JAX_COORDINATOR_PORT=12345

echo "========================================"
echo "Starting MaxDiffusion Training Container"
echo "========================================"
echo "Node Rank: ${NODE_RANK}"
echo "Coordinator IP: ${COORDINATOR_IP}"
echo "Total Nodes: ${NNODES}"
echo "Experiment: ${EXP_NAME}"
echo "========================================"

# Stop any existing container
docker stop maxdiffusion_train_${NODE_RANK} 2>/dev/null || true
docker rm maxdiffusion_train_${NODE_RANK} 2>/dev/null || true

# Check RDMA devices
echo "Verifying RDMA devices..."
docker run --rm --privileged \
    --volume /dev/infiniband:/dev/infiniband \
    ${IMAGE_TAG} ibv_devices || {
        echo "ERROR: RDMA devices not found!"
        exit 1
    }

echo "RDMA devices OK"

# Wait a bit for coordinator to be ready (only for non-coordinator nodes)
if [ ${NODE_RANK} -ne 0 ]; then
    echo "Waiting 15 seconds for coordinator to initialize..."
    sleep 15
fi

# Start training container
echo "Starting training container..."
docker run --rm --privileged --network host \
    --name maxdiffusion_train_${NODE_RANK} \
    --cap-add=IPC_LOCK \
    --volume /dev/infiniband:/dev/infiniband \
    --tmpfs /dev/shm:size=200G \
    --volume ${OUTPUT_DIR}:/app/output \
    --volume ${CODE_PATH}:/app/maxdiffusion \
    --volume /usr/local/lib/libbnxt_re-rdmav34.so:/usr/local/lib/libbnxt_re-rdmav34.so:ro \
    --volume /usr/local/lib/libbnxt_re.so:/usr/local/lib/libbnxt_re.so:ro \
    --volume /usr/local/lib/libbnxt_re.a:/usr/local/lib/libbnxt_re.a:ro \
    --volume /usr/local/lib/libbnxt_re.la:/usr/local/lib/libbnxt_re.la:ro \
    --volume /etc/libibverbs.d/bnxt_re.driver:/etc/libibverbs.d/bnxt_re.driver:ro \
    --volume /etc/bnxt_re:/etc/bnxt_re:ro \
    -e JAX_COORDINATOR_IP=${COORDINATOR_IP} \
    -e JAX_COORDINATOR_PORT=${JAX_COORDINATOR_PORT} \
    -e NNODES=${NNODES} \
    -e HIP_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
    -e NODE_RANK=${NODE_RANK} \
    -e JAX_DISTRIBUTED_INITIALIZATION_TIMEOUT_SECONDS=1800 \
    -e EXP_NAME=${EXP_NAME} \
    -w /app/maxdiffusion \
    ${IMAGE_TAG} \
    /bin/bash -c "
        set -ex
        echo 'Starting node ${NODE_RANK} of ${NNODES}'
        echo 'Coordinator IP: \${JAX_COORDINATOR_IP}:\${JAX_COORDINATOR_PORT}'
        echo 'Hostname: \$(hostname)'
        
        # Refresh library cache with mounted drivers
        ldconfig
        
        # Show RDMA devices
        echo 'Available RDMA devices:'
        ibv_devices
        
        # Verify mounted drivers
        echo 'Mounted RDMA drivers:'
        ls -lh /usr/local/lib/libbnxt_re* 2>/dev/null || echo 'No drivers found'
        
        # Show network interfaces
        echo 'Network interfaces:'
        ip addr show | grep -E 'enp[0-9]+' || true
        
        # Run training
        bash launch_multinode.sh LOG_PATH=/app/output $@
    " 2>&1 | tee ${LOG_DIR}/node_${NODE_RANK}_${timestamp}.log

echo "Container exited"
