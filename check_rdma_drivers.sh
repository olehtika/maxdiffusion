#!/bin/bash
#
# Check RDMA drivers and configuration on host and inside container
#

echo "========================================"
echo "RDMA Driver Diagnostic Script"
echo "========================================"
echo "Hostname: $(hostname)"
echo "Date: $(date)"
echo ""

echo "========================================" 
echo "1. HOST: Checking Broadcom driver files"
echo "========================================"
echo ""

# Check if Broadcom driver files exist
echo "Broadcom RDMA driver libraries:"
ls -lh /usr/local/lib/libbnxt_re*.so 2>/dev/null || echo "  ❌ No Broadcom driver libraries found in /usr/local/lib/"
echo ""

echo "Broadcom driver configuration:"
ls -lh /etc/libibverbs.d/bnxt_re.driver 2>/dev/null || echo "  ❌ No bnxt_re.driver found in /etc/libibverbs.d/"
echo ""

ls -lh /etc/bnxt_re/ 2>/dev/null || echo "  ❌ No /etc/bnxt_re/ directory found"
echo ""

echo "========================================"
echo "2. HOST: InfiniBand devices"
echo "========================================"
echo ""
ls -l /dev/infiniband/ 2>/dev/null || echo "  ❌ No /dev/infiniband/ directory found"
echo ""

echo "========================================"
echo "3. HOST: ibv_devices output"
echo "========================================"
echo ""
ibv_devices 2>&1
echo ""

echo "========================================"
echo "4. HOST: Checking kernel modules"
echo "========================================"
echo ""
echo "Loaded RDMA modules:"
lsmod | grep -E "(bnxt_re|rdma|ib_)" || echo "  ❌ No RDMA modules loaded"
echo ""

echo "========================================"
echo "5. HOST: Network interfaces (RoCE)"
echo "========================================"
echo ""
ip link show | grep -E "^[0-9]+: " | grep -v "lo:" || echo "  ❌ No network interfaces found"
echo ""

echo "========================================"
echo "6. CONTAINER: Testing driver mount"
echo "========================================"
echo ""

IMAGE_TAG="jianhan-wan-multinode-train:v1"

# Check if image exists
if ! docker image inspect ${IMAGE_TAG} >/dev/null 2>&1; then
    echo "  ❌ Docker image ${IMAGE_TAG} not found"
    echo "  Please build the image first"
    exit 1
fi

echo "Testing RDMA inside container with mounted drivers..."
docker run --rm --privileged \
    --volume /dev/infiniband:/dev/infiniband \
    --volume /usr/local/lib/libbnxt_re-rdmav34.so:/usr/local/lib/libbnxt_re-rdmav34.so:ro 2>/dev/null \
    --volume /usr/local/lib/libbnxt_re.so:/usr/local/lib/libbnxt_re.so:ro 2>/dev/null \
    --volume /usr/local/lib/libbnxt_re.a:/usr/local/lib/libbnxt_re.a:ro 2>/dev/null \
    --volume /usr/local/lib/libbnxt_re.la:/usr/local/lib/libbnxt_re.la:ro 2>/dev/null \
    --volume /etc/libibverbs.d/bnxt_re.driver:/etc/libibverbs.d/bnxt_re.driver:ro 2>/dev/null \
    --volume /etc/bnxt_re:/etc/bnxt_re:ro 2>/dev/null \
    ${IMAGE_TAG} /bin/bash -c "
        echo 'Container environment:'
        echo '  Hostname: \$(hostname)'
        echo ''
        echo 'Mounted Broadcom drivers:'
        ls -lh /usr/local/lib/libbnxt_re* 2>/dev/null || echo '  ❌ No drivers mounted'
        echo ''
        echo 'Mounted driver config:'
        ls -lh /etc/libibverbs.d/bnxt_re.driver 2>/dev/null || echo '  ❌ No driver config mounted'
        echo ''
        echo 'Running ldconfig...'
        ldconfig
        echo ''
        echo 'RDMA devices inside container:'
        ibv_devices 2>&1
        echo ''
        echo 'libibverbs version:'
        dpkg -l | grep libibverbs || echo '  ❌ libibverbs not found'
    "

echo ""
echo "========================================"
echo "7. Summary"
echo "========================================"
echo ""

# Count devices on host
DEVICE_COUNT=$(ibv_devices 2>/dev/null | grep -c "roce" || echo "0")
echo "RDMA devices detected on host: ${DEVICE_COUNT}"

# Check for ABI warnings
if ibv_devices 2>&1 | grep -q "does not support the kernel ABI"; then
    echo "⚠️  Kernel ABI mismatch detected"
    echo ""
    echo "Action needed:"
    echo "  1. Update Broadcom drivers on host to support kernel ABI v8"
    echo "  2. Or downgrade libibverbs in container (not recommended)"
else
    echo "✓ No kernel ABI warnings"
fi

echo ""
echo "========================================"
echo "Diagnostic complete"
echo "========================================"
