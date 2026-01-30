# Quick Start Guide - Multinode Training (No Slurm)

## Prerequisites Checklist
- [ ] Docker installed on all nodes
- [ ] RDMA drivers installed (`ibv_devices` works)
- [ ] SSH keys set up between nodes
- [ ] Code copied to same path on all nodes
- [ ] Frontend NIC (enp159s0np0) is UP
- [ ] All 8 compute NICs are UP

## Quick Setup (2 Nodes)

### 1. Verify Setup on Each Node
```bash
cd /home/amd/olehtika/code/maxdiffusion_jianhan
./verify_multinode_setup.sh
```

### 2. Build Docker Image on Each Node
```bash
docker build -t jianhan-wan-multinode-train:v1 \
    -f multi_node/docker/jax_maxdiffusion_wan2.1_train_inference.ubuntu.amd_no_slurm.Dockerfile .
```

**⚡ Fast Build**: This takes only 2-5 minutes because RDMA drivers are mounted from the host (not downloaded). See `DRIVER_MOUNTING.md` for details.

### 3. Get Coordinator IP
**On Node 0 (Coordinator):**
```bash
COORDINATOR_IP=$(ip addr show enp159s0np0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
echo "Coordinator IP: $COORDINATOR_IP"
# Note this IP!
```

### 4. Start Training

**On Node 0 (Coordinator) - Start this FIRST:**
```bash
./run_node.sh 0 $COORDINATOR_IP 2
```

**On Node 1 (Worker) - Start within 30 seconds:**
```bash
COORDINATOR_IP="<ip_from_step_3>"
./run_node.sh 1 $COORDINATOR_IP 2
```

For more nodes, continue with `./run_node.sh 2 $COORDINATOR_IP 3`, etc.

## Common Commands

### Monitor Training
```bash
# View logs
docker logs -f maxdiffusion_train_0  # Use appropriate rank

# Check container status
docker ps | grep maxdiffusion_train

# Check GPU utilization (from inside container)
docker exec maxdiffusion_train_0 rocm-smi
```

### Stop Training
```bash
# Stop container on current node
docker stop maxdiffusion_train_0  # Use appropriate rank

# Stop all on all nodes (if using orchestrator)
./multinode_docker_orchestrator.sh --stop
```

### Troubleshooting
```bash
# Check RDMA devices
ibv_devices
ibstat

# Check network interfaces
ip addr show enp159s0np0
ip link show enp28s0np0  # Check compute NICs

# Test RDMA in Docker
docker run --rm --privileged \
    --volume /dev/infiniband:/dev/infiniband \
    jianhan-wan-multinode-train:v1 ibv_devices

# Check container logs for errors
docker logs maxdiffusion_train_0 2>&1 | grep -i error

# Enable verbose NCCL debugging (edit launch_multinode.sh)
export NCCL_DEBUG=INFO
export NCCL_DEBUG_SUBSYS=ALL
```

## Network Topology

```
┌─────────────────────────────────────────────────────────────┐
│                         Node 0 (Coordinator)                 │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Frontend NIC: enp159s0np0 (Control/Coordination)    │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Compute RDMA NICs (Data Transfer):                  │   │
│  │  - enp28s0np0  → bnxt_re0                           │   │
│  │  - enp62s0np0  → bnxt_re1                           │   │
│  │  - enp79s0np0  → bnxt_re2                           │   │
│  │  - enp96s0np0  → bnxt_re3                           │   │
│  │  - enp158s0np0 → bnxt_re4                           │   │
│  │  - enp190s0np0 → bnxt_re5                           │   │
│  │  - enp206s0np0 → bnxt_re6                           │   │
│  │  - enp222s0np0 → bnxt_re7                           │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 8x GPUs (MI300X)                                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Frontend Network
                            │ (enp159s0np0)
                            │
┌─────────────────────────────────────────────────────────────┐
│                         Node 1 (Worker)                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Frontend NIC: enp159s0np0                            │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Compute RDMA NICs (8x bnxt_re)                       │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ 8x GPUs (MI300X)                                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Environment Variables (Key Ones)

Already configured in `launch_multinode.sh`:

| Variable | Value | Purpose |
|----------|-------|---------|
| `NCCL_SOCKET_IFNAME` | `enp159s0np0` | Frontend NIC for control |
| `NCCL_IB_HCA` | `bnxt_re0,bnxt_re1,...,bnxt_re7` | RDMA devices for data |
| `JAX_COORDINATOR_IP` | Set by `run_node.sh` | Coordinator address |
| `NODE_RANK` | Set by `run_node.sh` | Node rank (0, 1, 2, ...) |
| `NNODES` | Set by `run_node.sh` | Total number of nodes |

## File Structure

```
/home/amd/olehtika/code/maxdiffusion_jianhan/
├── launch_multinode.sh          # Training script (updated for your NICs)
├── run_node.sh                  # Per-node runner script
├── verify_multinode_setup.sh    # Setup verification
├── multinode_docker_orchestrator.sh  # Automated orchestrator (optional)
├── MULTINODE_SETUP.md          # Detailed setup guide
├── QUICK_START.md              # This file
├── multi_node/
│   └── docker/
│       └── jax_maxdiffusion_wan2.1_train_inference.ubuntu.amd_no_slurm.Dockerfile
└── output/                     # Training outputs
    ├── logs/                   # Log files
    └── checkpoints/            # Model checkpoints
```

## Expected Timeline

1. **Verification**: 5 minutes per node
2. **Docker Build**: 2-5 minutes per node (fast! drivers mounted from host)
3. **First Training Start**: 2-5 minutes (JAX initialization)
4. **Training**: Depends on configuration

**Note**: Docker build is much faster now because we mount RDMA drivers from the host instead of downloading them. See `DRIVER_MOUNTING.md`.

## Scaling to More Nodes

To run with N nodes:

1. Update `NNODES` parameter in commands: `./run_node.sh <rank> $COORDINATOR_IP <N>`
2. Start coordinator first (rank 0)
3. Start workers (ranks 1 to N-1) within 30 seconds
4. All nodes should see each other within 1-2 minutes

Example for 4 nodes:
```bash
# Node 0
./run_node.sh 0 $COORDINATOR_IP 4

# Node 1
./run_node.sh 1 $COORDINATOR_IP 4

# Node 2
./run_node.sh 2 $COORDINATOR_IP 4

# Node 3
./run_node.sh 3 $COORDINATOR_IP 4
```

## Success Indicators

Look for these in the logs:

```
✓ Starting node X of N
✓ Coordinator IP: <ip>:12345
✓ RDMA devices found: bnxt_re0, bnxt_re1, ...
✓ JAX distributed initialization successful
✓ Training started
```

## Common Issues

| Issue | Solution |
|-------|----------|
| "No RDMA devices found" | Run `ibv_devices` on host, check `/dev/infiniband` |
| "Coordinator timeout" | Check frontend NIC connectivity with `ping` |
| "NCCL initialization failed" | Check RDMA NIC status with `ibstat` |
| "Permission denied (Docker)" | Add user to docker group: `sudo usermod -aG docker $USER` |
| "Different code versions" | Use `rsync` to sync code across nodes |

## Next Steps

For detailed information, see:
- **Full setup guide**: `MULTINODE_SETUP.md`
- **Troubleshooting**: `MULTINODE_SETUP.md` (Troubleshooting section)
- **Performance tuning**: `MULTINODE_SETUP.md` (Performance Tuning section)
