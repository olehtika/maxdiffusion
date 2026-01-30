#!/usr/bin/env bash

# Test single node with multinode configuration
# This helps isolate if the issue is with the model/config or multinode coordination

export HF_TOKEN=""
export HF_HOME="/app/hf_home/"
export MIOPEN_CUSTOM_CACHE_DIR="/app/.cache/miopen/"
export JAX_COMPILATION_CACHE_DIR="/app/.cache/jax/"
export JAX_PERSISTENT_CACHE_ENABLE_XLA_CACHES="all"
export JAX_TRACEBACK_FILTERING=off

timestamp=$(date +%Y%m%d-%H%M%S)

export LIBTPU_INIT_ARGS=""
export KERAS_BACKEND="jax"
export JAX_SPMD_MODE="allow_all"
export TOKENIZERS_PARALLELISM="1"
export SKIP_GCS=1

export XLA_PYTHON_CLIENT_MEM_FRACTION=0.85
export TF_CUDNN_WORKSPACE_LIMIT_IN_MB=8192

export NVTE_FUSED_ATTN=1
export NVTE_CK_USES_BWD_V3=1
export NVTE_CK_USES_FWD_V3=1
export NVTE_CK_IS_V3_ATOMIC_FP32=0
export NVTE_CK_HOW_V3_BF16_CVT=1
export NVTE_ALLOW_NONDETERMINISTIC_ALGO=1

export HSA_FORCE_FINE_GRAIN_PCIE=1
export GPU_MAX_HW_QUEUES=2
export HIP_FORCE_DEV_KERNARG=1
export HSA_NO_SCRATCH_RECLAIM=1

HOST_NAME=$(hostname)

export XLA_FLAGS="--xla_gpu_enable_latency_hiding_scheduler=true --xla_gpu_enable_cublaslt=True
 --xla_gpu_graph_level=0 --xla_gpu_autotune_level=5 --xla_gpu_enable_reduce_scatter_combine_by_dim=false
 --xla_gpu_enable_all_gather_combine_by_dim=false --xla_gpu_all_gather_combine_threshold_bytes=134217728 
 --xla_gpu_reduce_scatter_combine_threshold_bytes=134217728
 --xla_dump_to=$PWD/output/xla_dump_${timestamp}"

rm -rf /app/.cache/*
python3 setup.py develop

EXP_NAME="flux_dev_single_test_${timestamp}"
LOG_FILE="$PWD/output/output_$EXP_NAME.log"

echo "Testing Flux Dev with single node (multinode config)..."
echo "This should work before trying multinode"

python -m src.maxdiffusion.train_flux src/maxdiffusion/configs/base_flux_dev.yml \
        run_name="run_$EXP_NAME" output_dir="$PWD/output" \
        hardware=gpu \
        attention=cudnn_flash_te \
        max_train_steps=5 \
        resolution=256 \
        ici_fsdp_parallelism=8 \
        per_device_batch_size=1 \
        metrics_file="$PWD/output/metrics_$EXP_NAME.txt" \
        "$@" |& tee -a "$LOG_FILE"

echo ""
echo "Single node test completed!"
echo "If this works, multinode should work too with the new config."
