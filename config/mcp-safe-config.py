#!/usr/bin/env python3
"""
mcp-safe-config.py - MCP 安全配置修改工具
提供安全的配置修改接口，自动快照 + 验证 + 回滚
"""

import json
import shutil
import os
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional

class SafeConfigManager:
    """安全配置管理器"""
    
    def __init__(self):
        self.config_path = Path("/home/node/.openclaw/openclaw.json")
        self.backup_dir = Path("/home/node/.openclaw/auto-backups")
        self.changelog_path = self.backup_dir / "changelog.md"
        
        # 确保目录存在
        self.backup_dir.mkdir(parents=True, exist_ok=True)
    
    def update_config(self, changes: Dict[str, Any], reason: str) -> Dict[str, Any]:
        """
        安全修改配置
        
        Args:
            changes: 要修改的配置项（字典）
            reason: 修改原因（用于记录）
        
        Returns:
            操作结果字典
        """
        
        # 1. 立即快照（带时间戳）
        timestamp = datetime.now().strftime("%m%d-%H%M%S")
        backup_path = self.backup_dir / f"pre-change-{timestamp}.json"
        
        try:
            shutil.copy2(self.config_path, backup_path)
            print(f"✓ Pre-change backup created: {backup_path}")
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to create backup: {e}",
                "backup": None
            }
        
        # 2. 记录修改原因
        self._log_change(timestamp, reason, str(backup_path))
        
        # 3. 读取当前配置
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to read config: {e}",
                "backup": str(backup_path)
            }
        
        # 4. 应用修改
        original_config = config.copy()
        config.update(changes)
        
        # 5. 写入配置
        try:
            with open(self.config_path, 'w', encoding='utf-8') as f:
                json.dump(config, f, indent=2, ensure_ascii=False)
        except Exception as e:
            return {
                "success": False,
                "error": f"Failed to write config: {e}",
                "backup": str(backup_path)
            }
        
        # 6. 验证 JSON 合法性
        try:
            with open(self.config_path, 'r', encoding='utf-8') as f:
                json.load(f)
        except json.JSONDecodeError as e:
            # 验证失败，自动回滚
            print(f"✗ JSON validation failed: {e}")
            shutil.copy2(backup_path, self.config_path)
            return {
                "success": False,
                "error": f"修改导致非法 JSON，已自动回滚: {e}",
                "backup": str(backup_path),
                "rolled_back": True
            }
        
        # 7. 验证配置逻辑（可选）
        validation_result = self._validate_config_logic(config)
        if not validation_result["valid"]:
            print(f"✗ Config logic validation failed: {validation_result['error']}")
            shutil.copy2(backup_path, self.config_path)
            return {
                "success": False,
                "error": f"配置逻辑错误，已自动回滚: {validation_result['error']}",
                "backup": str(backup_path),
                "rolled_back": True
            }
        
        # 8. 成功
        print(f"✓ Config updated successfully")
        return {
            "success": True,
            "backup": str(backup_path),
            "message": "修改已应用并验证通过",
            "changes": changes
        }
    
    def _log_change(self, timestamp: str, reason: str, backup_path: str):
        """记录修改日志"""
        with open(self.changelog_path, 'a', encoding='utf-8') as f:
            f.write(f"## {timestamp}\n")
            f.write(f"- **原因**: {reason}\n")
            f.write(f"- **备份**: {backup_path}\n")
            f.write(f"- **时间**: {datetime.now().isoformat()}\n\n")
    
    def _validate_config_logic(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """
        验证配置逻辑
        检查必须存在的关键字段
        """
        required_fields = ["version", "server"]
        
        for field in required_fields:
            if field not in config:
                return {
                    "valid": False,
                    "error": f"Missing required field: {field}"
                }
        
        # 可以添加更多验证规则
        # 例如：检查端口号范围、URL 格式等
        
        return {"valid": True}
    
    def get_config(self) -> Dict[str, Any]:
        """获取当前配置"""
        with open(self.config_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    
    def list_backups(self, limit: int = 10) -> list:
        """列出最近的备份"""
        backups = sorted(
            self.backup_dir.glob("pre-change-*.json"),
            key=lambda p: p.stat().st_mtime,
            reverse=True
        )
        return [str(b) for b in backups[:limit]]


# MCP Server 实现（如果使用 MCP 协议）
try:
    from mcp.server import Server
    
    app = Server("safe-config")
    manager = SafeConfigManager()
    
    @app.tool()
    def update_openclaw_config(changes: dict, reason: str) -> dict:
        """
        安全修改 OpenClaw 配置
        
        Args:
            changes: 要修改的配置项
            reason: 修改原因
        
        Returns:
            操作结果
        """
        return manager.update_config(changes, reason)
    
    @app.tool()
    def get_openclaw_config() -> dict:
        """获取当前 OpenClaw 配置"""
        return manager.get_config()
    
    @app.tool()
    def list_config_backups(limit: int = 10) -> list:
        """列出配置备份历史"""
        return manager.list_backups(limit)
    
    if __name__ == "__main__":
        app.run()

except ImportError:
    # 如果没有 MCP 库，提供命令行接口
    import sys
    
    if __name__ == "__main__":
        if len(sys.argv) < 3:
            print("Usage: mcp-safe-config.py <changes_json> <reason>")
            print("Example: mcp-safe-config.py '{\"model\":\"claude-4\"}' 'Switch to Claude 4'")
            sys.exit(1)
        
        changes_json = sys.argv[1]
        reason = sys.argv[2]
        
        manager = SafeConfigManager()
        changes = json.loads(changes_json)
        result = manager.update_config(changes, reason)
        
        print(json.dumps(result, indent=2, ensure_ascii=False))
