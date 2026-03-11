#!/bin/bash
# test-all.sh - 运行所有测试

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

run_test() {
    local test_name=$1
    local test_script=$2
    
    echo -e "\n${YELLOW}Running: $test_name${NC}"
    
    if bash "$test_script"; then
        echo -e "${GREEN}✓ PASSED: $test_name${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}✗ FAILED: $test_name${NC}"
        FAIL=$((FAIL + 1))
    fi
}

echo "=========================================="
echo "  OpenClaw Guard - Test Suite"
echo "=========================================="

# 测试1：验证所有脚本语法
echo -e "\n${YELLOW}Test 1: Script syntax validation${NC}"
for script in "$PROJECT_DIR"/scripts/*.sh; do
    if bash -n "$script" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $(basename $script)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $(basename $script)"
        FAIL=$((FAIL + 1))
    fi
done

# 测试2：验证 Python 脚本语法
echo -e "\n${YELLOW}Test 2: Python syntax validation${NC}"
for script in "$PROJECT_DIR"/scripts/*.py "$PROJECT_DIR"/config/*.py; do
    if python3 -m py_compile "$script" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $(basename $script)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $(basename $script)"
        FAIL=$((FAIL + 1))
    fi
done

# 测试3：验证 Dockerfile 存在
echo -e "\n${YELLOW}Test 3: Docker files validation${NC}"
if [ -f "$PROJECT_DIR/docker/Dockerfile" ]; then
    echo -e "  ${GREEN}✓${NC} Dockerfile exists"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${NC} Dockerfile missing"
    FAIL=$((FAIL + 1))
fi

if [ -f "$PROJECT_DIR/docker/docker-compose.yml" ]; then
    echo -e "  ${GREEN}✓${NC} docker-compose.yml exists"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${NC} docker-compose.yml missing"
    FAIL=$((FAIL + 1))
fi

# 测试4：验证文档完整性
echo -e "\n${YELLOW}Test 4: Documentation validation${NC}"
for doc in ARCHITECTURE.md DEPLOYMENT.md CONFIGURATION.md RECOVERY.md DEVELOPMENT.md; do
    if [ -f "$PROJECT_DIR/docs/$doc" ]; then
        echo -e "  ${GREEN}✓${NC} $doc exists"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $doc missing"
        FAIL=$((FAIL + 1))
    fi
done

# 测试5：验证环境变量示例
echo -e "\n${YELLOW}Test 5: Configuration files${NC}"
if [ -f "$PROJECT_DIR/.env.example" ]; then
    echo -e "  ${GREEN}✓${NC} .env.example exists"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}✗${NC} .env.example missing"
    FAIL=$((FAIL + 1))
fi

# 汇总
echo -e "\n=========================================="
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "=========================================="

if [ $FAIL -gt 0 ]; then
    exit 1
fi
