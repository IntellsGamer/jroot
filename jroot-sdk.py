#!/usr/bin/env python3
"""Compatibility entry point for the importable JRoot plugin SDK.

Plugin code should use ``from jroot_sdk import JRootContext``. This file remains
for users who previously invoked ``jroot-sdk.py`` directly.
"""
from jroot_sdk import JRootContext
import json


if __name__ == "__main__":
    print(json.dumps(JRootContext().list_jails(), indent=2))
