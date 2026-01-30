# Multinode Training Setup (Without Slurm and Shared Filesystem)

This guide explains how to run multinode training on your cluster without Slurm and without a shared filesystem.

## Hardware Configuration

Based on your setup:
- **Frontend NIC**: `enp159s0np0` (for control/coordination traffic)
- **Compute RDMA NICs**: 8x NICs
  - `enp28s0np0`, `enp62s0np0`, `enp79s0np0`, `enp96s0np0`
  - `enp158s0np0`, `enp190s0np0`, `enp206s0np0`, `enp222s0np0`
- **RDMA Drivers**: Broadcom bnxt_re drivers installed at `/usr/local/lib/libbnxt*`

## Prerequisites

### On All Nodes:

1. **Docker installed and running**
   ```bash
   docker --version
   ```

2. **RDMA drivers installed**
   ```bash
   find /usr/ -type f -name "libbnxt*"
   ibv_devices  # Should show bnxt_re devices
   ```

3. **SSH access between nodes** (for orchestrator script)
   ```bash
   ssh-keygen -t rsa -b 4096
   ssh-copy-id user@node1
   ssh-copy-id user@node2
   # ... for all nodes
   ```

4. **Network connectivity**
   ```bash
   # Test frontend NIC connectivity
   ping -I enp159s0np0 <other_node_ip>
   
   # Verify RDMA NICs are up
   ip link show enp28s0np0
   ip link show enp62s0np0
   # ... check all 8 NICs
   ```

5. **Docker permissions**
   ```bash
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

## Files Overview

### Modified/New Files:

1. **`launch_multinode.sh`** - Updated launch script with correct RDMA NIC configuration
2. **`run_node.sh`** - Script to manually run training on each node
3. **`multinode_docker_orchestrator.sh`** - Automated orchestrator using SSH
4. **`multi_node/docker/jax_maxdiffusion_wan2.1_train_inference.ubuntu.amd_no_slurm.Dockerfile`** - Updated Dockerfile

## Setup Methods

You have two options for running multinode training:

### Option 1: Manual Execution (Simpler, Recommended for Testing)

Run the training script manually on each node.

#### Step 1: Prepare Code on Each Node

On each node, clone or copy the code:
```bash
# On each node
cd /home/amd/olehtika/code/
git clone <your_repo> maxdiffusion_jianhan
cd maxdiffusion_jianhan
```

#### Step 2: Build Docker Image on Each Node

```bash
# On each node
cd /home/amd/olehtika/code/maxdiffusion_jianhan
docker build -t jianhan-wan-multinode-train:v1 \
    -f multi_node/docker/jax_maxdiffusion_wan2.1_train_inference.ubuntu.amd_no_slurm.Dockerfile .
```

#### Step 3: Verify RDMA Setup

```bash
# On each node, verify RDMA devices are visible in Docker
docker run --rm --privileged \
    --volume /dev/infiniband:/dev/infiniband \
    jianhan-wan-multinode-train:v1 ibv_devices

# Should show output like:
#     device                 node GUID
#     ------              ----------------
#     bnxt_re0            xxxxxxxxxxxx
#     bnxt_re1            xxxxxxxxxxxx
#     ...
```

#### Step 4: Start Training

**On the coordinator node (Node 0):**
```bash
cd /home/amd/olehtika/code/maxdiffusion_jianhan
chmod +x run_node.sh

# Get the IP of this node on the frontend NIC
COORDINATOR_IP=$(ip addr show enp159s0np0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
echo "Coordinator IP: $COORDINATOR_IP"

# Start training (node_rank=0, total_nodes=2 for 2-node training)
./run_node.sh 0 $COORDINATOR_IP 2
```

**On worker node(s) (Node 1, 2, ...):**
```bash
cd /home/amd/olehtika/code/maxdiffusion_jianhan
chmod +x run_node.sh

# Use the coordinator IP from above
COORDINATOR_IP="<ip_from_coordinator_node>"

# Start training (node_rank=1 for second node, 2 for third, etc.)
./run_node.sh 1 $COORDINATOR_IP 2
```

**Important:** Start the coordinator (rank 0) first, then start worker nodes within 30 seconds.

### Option 2: Automated Orchestration (Advanced)

Use the orchestrator script to manage all nodes via SSH automatically.

#### Step 1: Configure the Orchestrator

Edit `multinode_docker_orchestrator.sh`:

```bash
# Update these variables at the top of the file:
NODES=(
    "192.168.1.100"    # Coordinator node IP
    "192.168.1.101"    # Worker node 1 IP
    # Add more nodes as needed
)

SSH_USER="amd"  # Your SSH username
CODE_PATH="/home/amd/olehtika/code/maxdiffusion_jianhan"
OUTPUT_BASE_PATH="/home/amd/olehtika/maxdiffusion_output"
```

#### Step 2: Run the Orchestrator

From your local machine or the coordinator node:

```bash
chmod +x multinode_docker_orchestrator.sh
./multinode_docker_orchestrator.sh
```

The orchestrator will:
1. Verify SSH connectivity to all nodes
2. Create necessary directories
3. Distribute code to all nodes (using rsync)
4. Build Docker images on all nodes
5. Start training containers
6. Monitor training progress

#### Step 3: Monitor Training

```bash
# View logs from coordinator
ssh amd@<coordinator_ip> 'docker logs -f maxdiffusion_train_0'

# View logs from worker
ssh amd@<worker_ip> 'docker logs -f maxdiffusion_train_1'
```

## Configuration Details

### RDMA NIC Configuration

The `launch_multinode.sh` script has been updated with your specific NICs:

```bash
# NCCL will use these 8 RDMA devices
export NCCL_IB_HCA=bnxt_re0,bnxt_re1,bnxt_re2,bnxt_re3,bnxt_re4,bnxt_re5,bnxt_re6,bnxt_re7

# Socket communication uses frontend NIC
export NCCL_SOCKET_IFNAME=enp159s0np0
export GLOO_SOCKET_IFNAME=enp159s0np0
```

### JAX Distributed Initialization

The scripts configure JAX for multinode:
- `JAX_COORDINATOR_IP`: IP of the first node (coordinator)
- `JAX_COORDINATOR_PORT`: Port for coordination (default: 12345)
- `NODE_RANK`: 0 for coordinator, 1, 2, ... for workers
- `NNODES`: Total number of nodes

## Troubleshooting

### Issue: RDMA devices not found

```bash
# Check if devices are visible on host
ibv_devices

# Check if kernel modules are loaded
lsmod | grep bnxt

# Check device permissions
ls -la /dev/infiniband/
```

### Issue: JAX coordination timeout

```bash
# Check network connectivity on frontend NIC
ping -I enp159s0np0 <coordinator_ip>

# Check if port is open
nc -zv <coordinator_ip> 12345

# Check if firewall is blocking
sudo iptables -L -n | grep 12345
```

### Issue: NCCL initialization fails

```bash
# Enable detailed NCCL debugging
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET,GRAPH

# Check RDMA NIC status
ibstat
```

### Issue: Container cannot access RDMA devices

```bash
# Ensure privileged mode and device mounting
docker run --rm --privileged \
    --volume /dev/infiniband:/dev/infiniband \
    <image> ibv_devices

# Check container capabilities
docker run --rm --privileged <image> \
    cat /proc/self/status | grep Cap
```

### Issue: Different nodes have different code versions

Since there's no shared filesystem, you must ensure code is synchronized:

```bash
# Option 1: Use rsync to sync code
rsync -avz --exclude 'output/' --exclude '__pycache__/' \
    /home/amd/olehtika/code/maxdiffusion_jianhan/ \
    user@node2:/home/amd/olehtika/code/maxdiffusion_jianhan/

# Option 2: Embed code in Docker image
# (Update Dockerfile to COPY code instead of mounting)
```

## Performance Tuning

### NCCL Settings

If you experience performance issues, try adjusting these in `launch_multinode.sh`:

```bash
# For large messages
export NCCL_IB_QPS_PER_CONNECTION=4  # Increase from 1

# For all-to-all communication
export NCCL_PXN_DISABLE=0  # Already enabled

# For debugging slow initialization
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=INIT,NET
```

### Network Interface Selection

If automatic NIC detection fails:

```bash
# Explicitly set which interfaces to use
export NCCL_IB_HCA=bnxt_re0,bnxt_re1  # Limit to specific NICs

# Set specific GID index if needed
export NCCL_IB_GID_INDEX=3  # Already set
```

## Stopping Training

### Manual Method:
```bash
# On each node
docker stop maxdiffusion_train_0  # Use appropriate rank
```

### Orchestrator Method:
```bash
# Stop all nodes
for node in node1 node2; do
    ssh amd@$node 'docker stop $(docker ps -q --filter name=maxdiffusion_train)'
done
```

## Log Locations

- **Host logs**: `$OUTPUT_DIR/logs/node_<rank>_<timestamp>.log`
- **Container logs**: `docker logs maxdiffusion_train_<rank>`
- **Training output**: `$OUTPUT_DIR/output_<hostname>.log`
- **XLA dumps**: `$OUTPUT_DIR/<hostname>_xla_dump_<timestamp>/`

## Next Steps

1. Test with 2 nodes first
2. Verify RDMA bandwidth with `ib_write_bw` or `ib_send_bw`
3. Monitor GPU utilization with `docker exec <container> rocm-smi`
4. Scale to more nodes once 2-node setup is stable

## Support

For issues specific to:
- **RDMA/Networking**: Check `ibstat`, `ibv_devinfo`, `ip link`
- **JAX Distributed**: Check coordinator logs, verify `JAX_COORDINATOR_IP`
- **Docker**: Check `docker logs`, `docker inspect`
- **Training**: Check training logs in output directory
