#!/bin/bash

# Multinode training launch script for MaxDiffusion Flux Dev
# This script is called by run_node.sh inside the Docker container
# Optimized for 2-node setup with 8 GPUs per node

set -e

# Create log directories
LOG_PATH="$PWD/output/logs"
mkdir -p "$LOG_PATH"

# Generate unique experiment name
timestamp=$(date +%Y%m%d_%H%M%S)
EXP_NAME="flux_dev_multinode_${timestamp}"
LOG_FILE="$LOG_PATH/output_$EXP_NAME.log"

echo "========================================" | tee "$LOG_FILE"
echo "MaxDiffusion Flux Dev Multinode Training" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "Experiment: $EXP_NAME" | tee -a "$LOG_FILE"
echo "Node Rank: ${JAX_COORDINATOR_RANK:-0}" | tee -a "$LOG_FILE"
echo "Coordinator: ${JAX_COORDINATOR_ADDRESS:-localhost:1234}" | tee -a "$LOG_FILE"
echo "Num Nodes: ${NNODES:-1}" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Print environment info
echo "Environment Information:" | tee -a "$LOG_FILE"
echo "JAX_COORDINATOR_ADDRESS: ${JAX_COORDINATOR_ADDRESS}" | tee -a "$LOG_FILE"
echo "JAX_COORDINATOR_RANK: ${JAX_COORDINATOR_RANK}" | tee -a "$LOG_FILE"
echo "JAX_PROCESS_INDEX: ${JAX_PROCESS_INDEX}" | tee -a "$LOG_FILE"
echo "NNODES: ${NNODES}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Print GPU info
echo "GPU Information:" | tee -a "$LOG_FILE"
rocm-smi --showproductname 2>/dev/null | tee -a "$LOG_FILE" || echo "rocm-smi not available" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Print RDMA info
echo "RDMA Information:" | tee -a "$LOG_FILE"
ibv_devices 2>/dev/null | tee -a "$LOG_FILE" || echo "ibv_devices not available" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Print NCCL configuration
echo "NCCL Configuration:" | tee -a "$LOG_FILE"
echo "NCCL_DEBUG: ${NCCL_DEBUG}" | tee -a "$LOG_FILE"
echo "NCCL_IB_HCA: ${NCCL_IB_HCA}" | tee -a "$LOG_FILE"
echo "NCCL_SOCKET_IFNAME: ${NCCL_SOCKET_IFNAME}" | tee -a "$LOG_FILE"
echo "NCCL_PROTO: ${NCCL_PROTO}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Filter out the special arguments (node rank, coordinator, etc) from command line args
# so they don't interfere with the training script
FILTERED_ARGS=()
skip_next=false
for arg in "$@"; do
    if [[ "$skip_next" == true ]]; then
        skip_next=false
        continue
    fi
    
    case "$arg" in
        --node_rank|--coordinator_address|--num_nodes)
            skip_next=true
            ;;
        --node_rank=*|--coordinator_address=*|--num_nodes=*)
            # Skip args with = form
            ;;
        *)
            FILTERED_ARGS+=("$arg")
            ;;
    esac
done

# Start training
echo "Starting Flux Dev training..." | tee -a "$LOG_FILE"
echo "Command line arguments: ${FILTERED_ARGS[@]}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Use NNODES environment variable for DCN parallelism, default to 1 if not set
NUM_NODES=${NNODES:-1}
echo "Configuring for $NUM_NODES nodes" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run training with explicit DCN data parallelism
python -m src.maxdiffusion.train_flux src/maxdiffusion/configs/base_flux_dev.yml \
        run_name="run_$EXP_NAME" output_dir="$PWD/output" \
        hardware=gpu \
        attention=cudnn_flash_te \
        max_train_steps=20 \
        resolution=512 \
        dcn_data_parallelism=$NUM_NODES \
        dcn_fsdp_parallelism=1 \
        ici_data_parallelism=1 \
        ici_fsdp_parallelism=8 \
        per_device_batch_size=1 \
        metrics_file="$LOG_PATH/metrics_$EXP_NAME.txt" \
        "${FILTERED_ARGS[@]}" |& tee -a "$LOG_FILE"

exit_code=$?

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
if [ $exit_code -eq 0 ]; then
    echo "Training completed successfully!" | tee -a "$LOG_FILE"
else
    echo "Training failed with exit code: $exit_code" | tee -a "$LOG_FILE"
fi
echo "========================================" | tee -a "$LOG_FILE"

exit $exit_code
