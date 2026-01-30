#!/bin/bash
#
# Verification script for multinode setup
# Run this on each node before starting training
#

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Multinode Training Setup Verification"
echo "=========================================="
echo ""

# Function to check and print result
check() {
    local description=$1
    local command=$2
    
    echo -n "Checking $description... "
    if eval "$command" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        return 0
    else
        echo -e "${RED}✗ FAIL${NC}"
        return 1
    fi
}

# Function to check and print info
check_info() {
    local description=$1
    local command=$2
    
    echo -e "\n${YELLOW}$description:${NC}"
    eval "$command" || echo "  (not available)"
}

ERRORS=0

# Check 1: Docker
if ! check "Docker installation" "docker --version"; then
    echo "  Error: Docker is not installed or not running"
    ERRORS=$((ERRORS + 1))
fi

# Check 2: Docker permissions
if ! check "Docker permissions" "docker ps"; then
    echo "  Error: Current user cannot run Docker commands"
    echo "  Fix: sudo usermod -aG docker $USER (then log out and back in)"
    ERRORS=$((ERRORS + 1))
fi

# Check 3: RDMA drivers
if ! check "RDMA drivers (ibverbs)" "ibv_devices"; then
    echo "  Error: RDMA drivers not found or not working"
    echo "  Fix: Install libibverbs and check RDMA drivers"
    ERRORS=$((ERRORS + 1))
fi

# Check 4: Frontend NIC
if ! check "Frontend NIC (enp159s0np0)" "ip link show enp159s0np0"; then
    echo "  Error: Frontend NIC enp159s0np0 not found"
    echo "  Available NICs:"
    ip link show | grep -E '^[0-9]+:' | awk '{print "    " $2}'
    ERRORS=$((ERRORS + 1))
fi

# Check 5-12: Compute RDMA NICs
RDMA_NICS=(enp28s0np0 enp62s0np0 enp79s0np0 enp96s0np0 enp158s0np0 enp190s0np0 enp206s0np0 enp222s0np0)
RDMA_NIC_COUNT=0
for nic in "${RDMA_NICS[@]}"; do
    if check "Compute NIC ($nic)" "ip link show $nic"; then
        RDMA_NIC_COUNT=$((RDMA_NIC_COUNT + 1))
    fi
done

if [ $RDMA_NIC_COUNT -eq 0 ]; then
    echo -e "${RED}  Error: No compute RDMA NICs found${NC}"
    ERRORS=$((ERRORS + 1))
elif [ $RDMA_NIC_COUNT -lt 8 ]; then
    echo -e "${YELLOW}  Warning: Only $RDMA_NIC_COUNT/8 compute RDMA NICs found${NC}"
fi

# Check 13: Broadcom drivers (host)
echo ""
echo "Checking Broadcom RDMA drivers on host..."
if check "Broadcom driver library" "test -f /usr/local/lib/libbnxt_re-rdmav34.so"; then
    DRIVER_SIZE=$(ls -lh /usr/local/lib/libbnxt_re-rdmav34.so | awk '{print $5}')
    DRIVER_DATE=$(ls -l /usr/local/lib/libbnxt_re-rdmav34.so | awk '{print $6, $7, $8}')
    echo "  Driver: /usr/local/lib/libbnxt_re-rdmav34.so ($DRIVER_SIZE, $DRIVER_DATE)"
else
    echo -e "${RED}  Error: Main driver library not found${NC}"
    ERRORS=$((ERRORS + 1))
fi

if check "Broadcom driver config" "test -f /etc/libibverbs.d/bnxt_re.driver"; then
    echo "  Config: /etc/libibverbs.d/bnxt_re.driver"
else
    echo -e "${RED}  Error: Driver configuration not found${NC}"
    ERRORS=$((ERRORS + 1))
fi

if check "Broadcom driver settings" "test -f /etc/bnxt_re/bnxt_re.conf"; then
    echo "  Settings: /etc/bnxt_re/bnxt_re.conf"
else
    echo -e "${YELLOW}  Warning: Driver settings file not found${NC}"
fi

# Check 14: InfiniBand devices
if ! check "/dev/infiniband exists" "test -d /dev/infiniband"; then
    echo "  Error: /dev/infiniband not found"
    echo "  RDMA will not work in Docker containers"
    ERRORS=$((ERRORS + 1))
fi

# Check 15: Code directory
if ! check "Code directory" "test -d /home/amd/olehtika/code/maxdiffusion_jianhan"; then
    echo "  Error: Code directory not found at expected location"
    echo "  Current directory: $(pwd)"
    ERRORS=$((ERRORS + 1))
fi

# Check 16: Scripts exist
SCRIPT_DIR="/home/amd/olehtika/code/maxdiffusion_jianhan"
if [ -d "$SCRIPT_DIR" ]; then
    check "launch_multinode.sh exists" "test -f $SCRIPT_DIR/launch_multinode.sh"
    check "run_node.sh exists" "test -f $SCRIPT_DIR/run_node.sh"
    check "run_node.sh is executable" "test -x $SCRIPT_DIR/run_node.sh"
fi

echo ""
echo "=========================================="
echo "Additional Information"
echo "=========================================="

# Show RDMA device details
check_info "RDMA devices" "ibv_devices"

# Show RDMA device info
check_info "RDMA device info (first device)" "ibv_devinfo | head -20"

# Show network interfaces with IPs
check_info "Network interfaces" "ip -br addr show | grep -E 'enp[0-9]+'"

# Show Docker version
check_info "Docker version" "docker version --format '{{.Server.Version}}'"

# Show available GPU devices
check_info "GPU devices" "ls /dev/kfd /dev/dri/render* 2>/dev/null"

# Check if Docker can access RDMA
echo ""
echo "=========================================="
echo "Docker RDMA Access Test"
echo "=========================================="
echo "Testing if Docker can access RDMA devices..."
echo "(This requires the Docker image to be built)"
echo ""

IMAGE_TAG="jianhan-wan-multinode-train:v1"
if docker image inspect $IMAGE_TAG > /dev/null 2>&1; then
    echo "Docker image found: $IMAGE_TAG"
    echo "Testing RDMA access in container with mounted drivers..."
    
    if docker run --rm --privileged \
        --volume /dev/infiniband:/dev/infiniband \
        --volume /usr/local/lib/libbnxt_re-rdmav34.so:/usr/local/lib/libbnxt_re-rdmav34.so:ro \
        --volume /usr/local/lib/libbnxt_re.so:/usr/local/lib/libbnxt_re.so:ro \
        --volume /etc/libibverbs.d/bnxt_re.driver:/etc/libibverbs.d/bnxt_re.driver:ro \
        --volume /etc/bnxt_re:/etc/bnxt_re:ro \
        $IMAGE_TAG /bin/bash -c "ldconfig && ibv_devices" 2>&1; then
        echo -e "${GREEN}✓ Docker can access RDMA devices with mounted drivers${NC}"
    else
        echo -e "${RED}✗ Docker cannot access RDMA devices${NC}"
        echo "Check that host drivers are present:"
        echo "  ls -l /usr/local/lib/libbnxt_re*.so"
        echo "  ls -l /etc/libibverbs.d/bnxt_re.driver"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}Docker image not found: $IMAGE_TAG${NC}"
    echo "Build the image first with:"
    echo "  cd $SCRIPT_DIR"
    echo "  docker build -t $IMAGE_TAG -f multi_node/docker/jax_maxdiffusion_wan2.1_train_inference.ubuntu.amd_no_slurm.Dockerfile ."
fi

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "You can proceed with multinode training setup."
    echo "See MULTINODE_SETUP.md for next steps."
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS error(s)${NC}"
    echo ""
    echo "Please fix the errors above before proceeding."
    echo "See MULTINODE_SETUP.md for troubleshooting guidance."
    exit 1
fi
