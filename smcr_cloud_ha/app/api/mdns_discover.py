#!/usr/bin/env python3
"""
mDNS discovery for SMCR devices using zeroconf (no avahi-daemon required).
Outputs JSON array of found devices to stdout.
"""
import json
import time
import socket
import sys

try:
    from zeroconf import Zeroconf, ServiceBrowser
except ImportError:
    print(json.dumps({'error': 'python3-zeroconf not installed'}))
    sys.exit(1)


class SmcrListener:
    def __init__(self):
        self.found = {}

    def add_service(self, zc, type_, name):
        try:
            info = zc.get_service_info(type_, name)
            if info is None:
                return

            txt = {}
            for k, v in info.properties.items():
                k = k.decode('utf-8', errors='ignore') if isinstance(k, bytes) else str(k)
                v = v.decode('utf-8', errors='ignore') if isinstance(v, bytes) else (v or '')
                txt[k.lower()] = v

            # Filter only SMCR devices
            is_smcr = (
                txt.get('device_type', '').lower() == 'smcr' or
                txt.get('device', '').upper() == 'SMCR'
            )
            if not is_smcr:
                return

            ip = None
            for addr in info.addresses:
                try:
                    ip = socket.inet_ntoa(addr)
                    break
                except Exception:
                    continue
            if not ip:
                return

            key = f"{ip}:{info.port}"
            self.found[key] = {
                'hostname': info.server.rstrip('.') if info.server else '',
                'ip': ip,
                'port': info.port,
                'version': txt.get('version', ''),
            }
        except Exception:
            pass

    def remove_service(self, zc, type_, name):
        pass

    def update_service(self, zc, type_, name):
        self.add_service(zc, type_, name)


try:
    zc = Zeroconf()
    listener = SmcrListener()
    browser = ServiceBrowser(zc, "_http._tcp.local.", listener)
    time.sleep(4)
    zc.close()
    print(json.dumps(list(listener.found.values())))
except Exception as e:
    print(json.dumps({'error': str(e)}))
    sys.exit(1)
