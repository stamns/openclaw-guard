#!/usr/bin/env python3
"""
alert.py - 统一告警通知脚本
支持飞书、钉钉、Slack 多渠道告警
"""

import os
import sys
import json
import requests
from datetime import datetime
from typing import Optional, Dict, Any

class AlertManager:
    """告警管理器"""
    
    def __init__(self):
        self.channels = {
            'feishu': os.getenv('ALERT_WEBHOOK_FEISHU'),
            'dingtalk': os.getenv('ALERT_WEBHOOK_DINGTALK'),
            'slack': os.getenv('ALERT_WEBHOOK_SLACK')
        }
        self.threshold = os.getenv('ALERT_LEVEL_THRESHOLD', 'warning')
        self.level_priority = {
            'debug': 0,
            'info': 1,
            'warning': 2,
            'error': 3,
            'critical': 4
        }
    
    def should_send(self, level: str) -> bool:
        """判断是否应该发送告警"""
        return self.level_priority.get(level, 0) >= self.level_priority.get(self.threshold, 2)
    
    def send(self, level: str, title: str, message: str, context: Optional[Dict[str, Any]] = None):
        """发送告警到所有配置的渠道"""
        
        if not self.should_send(level):
            print(f"Alert level {level} below threshold {self.threshold}, skipping")
            return
        
        # 构建通用消息体
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        # 发送到飞书
        if self.channels['feishu']:
            self._send_feishu(level, title, message, context, timestamp)
        
        # 发送到钉钉
        if self.channels['dingtalk']:
            self._send_dingtalk(level, title, message, context, timestamp)
        
        # 发送到 Slack
        if self.channels['slack']:
            self._send_slack(level, title, message, context, timestamp)
    
    def _send_feishu(self, level: str, title: str, message: str, context: Optional[Dict], timestamp: str):
        """发送到飞书"""
        color = self._get_color(level)
        
        payload = {
            "msg_type": "interactive",
            "card": {
                "header": {
                    "title": {
                        "tag": "plain_text",
                        "content": f"[{level.upper()}] {title}"
                    },
                    "template": color
                },
                "elements": [
                    {
                        "tag": "div",
                        "text": {
                            "tag": "lark_md",
                            "content": message
                        }
                    },
                    {
                        "tag": "hr"
                    },
                    {
                        "tag": "div",
                        "text": {
                            "tag": "lark_md",
                            "content": f"**时间:** {timestamp}\n**级别:** {level}\n**主机:** {os.uname().nodename}"
                        }
                    }
                ]
            }
        }
        
        if context:
            payload["card"]["elements"].insert(-1, {
                "tag": "div",
                "text": {
                    "tag": "lark_md",
                    "content": f"**上下文:**\n```json\n{json.dumps(context, indent=2, ensure_ascii=False)}\n```"
                }
            })
        
        try:
            response = requests.post(
                self.channels['feishu'],
                json=payload,
                timeout=5
            )
            if response.status_code == 200:
                print(f"✓ Alert sent to Feishu")
            else:
                print(f"✗ Feishu alert failed: {response.text}")
        except Exception as e:
            print(f"✗ Feishu alert error: {e}")
    
    def _send_dingtalk(self, level: str, title: str, message: str, context: Optional[Dict], timestamp: str):
        """发送到钉钉"""
        
        text = f"### [{level.upper()}] {title}\n\n"
        text += f"{message}\n\n"
        text += f"**时间:** {timestamp}\n"
        text += f"**级别:** {level}\n"
        text += f"**主机:** {os.uname().nodename}\n"
        
        if context:
            text += f"\n**上下文:**\n```json\n{json.dumps(context, indent=2, ensure_ascii=False)}\n```"
        
        payload = {
            "msgtype": "markdown",
            "markdown": {
                "title": f"[{level.upper()}] {title}",
                "text": text
            }
        }
        
        try:
            response = requests.post(
                self.channels['dingtalk'],
                json=payload,
                timeout=5
            )
            if response.status_code == 200:
                print(f"✓ Alert sent to DingTalk")
            else:
                print(f"✗ DingTalk alert failed: {response.text}")
        except Exception as e:
            print(f"✗ DingTalk alert error: {e}")
    
    def _send_slack(self, level: str, title: str, message: str, context: Optional[Dict], timestamp: str):
        """发送到 Slack"""
        color = self._get_slack_color(level)
        
        payload = {
            "attachments": [
                {
                    "color": color,
                    "title": f"[{level.upper()}] {title}",
                    "text": message,
                    "fields": [
                        {
                            "title": "Time",
                            "value": timestamp,
                            "short": True
                        },
                        {
                            "title": "Level",
                            "value": level,
                            "short": True
                        },
                        {
                            "title": "Host",
                            "value": os.uname().nodename,
                            "short": True
                        }
                    ],
                    "footer": "OpenClaw Guard",
                    "ts": int(datetime.now().timestamp())
                }
            ]
        }
        
        if context:
            payload["attachments"][0]["fields"].append({
                "title": "Context",
                "value": f"```{json.dumps(context, indent=2)}```",
                "short": False
            })
        
        try:
            response = requests.post(
                self.channels['slack'],
                json=payload,
                timeout=5
            )
            if response.status_code == 200:
                print(f"✓ Alert sent to Slack")
            else:
                print(f"✗ Slack alert failed: {response.text}")
        except Exception as e:
            print(f"✗ Slack alert error: {e}")
    
    def _get_color(self, level: str) -> str:
        """获取飞书颜色模板"""
        colors = {
            'debug': 'grey',
            'info': 'blue',
            'warning': 'yellow',
            'error': 'orange',
            'critical': 'red'
        }
        return colors.get(level, 'grey')
    
    def _get_slack_color(self, level: str) -> str:
        """获取 Slack 颜色"""
        colors = {
            'debug': '#808080',
            'info': '#36a64f',
            'warning': '#ffcc00',
            'error': '#ff9900',
            'critical': '#ff0000'
        }
        return colors.get(level, '#808080')


def main():
    """命令行入口"""
    if len(sys.argv) < 4:
        print("Usage: alert.py <level> <title> <message> [context_json]")
        print("Example: alert.py critical 'Config Corrupted' 'Auto recovered' '{\"file\":\"openclaw.json\"}'")
        sys.exit(1)
    
    level = sys.argv[1]
    title = sys.argv[2]
    message = sys.argv[3]
    context = None
    
    if len(sys.argv) > 4:
        try:
            context = json.loads(sys.argv[4])
        except json.JSONDecodeError:
            print(f"Warning: Invalid JSON context: {sys.argv[4]}")
    
    alert = AlertManager()
    alert.send(level, title, message, context)


if __name__ == '__main__':
    main()
