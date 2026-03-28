#!/usr/bin/env python3
"""
SMCR mDNS discovery via python3-zeroconf.
Browses _http._tcp.local. and filters SMCR devices by TXT records.
Outputs a JSON array to stdout.
"""
import json
import time
import socket
from zeroconf import Zeroconf, ServiceBrowser, ServiceStateChange

found = {}


def on_change(zeroconf, service_type, name, state_change):
    if state_change is not ServiceStateChange.Added:
        return

    info = zeroconf.get_service_info(service_type, name, timeout=3000)
    if info is None:
        return

    # Resolve IP (compatible with older and newer zeroconf versions)
    if hasattr(info, 'parsed_addresses'):
        addrs = info.parsed_addresses()
    else:
        addrs = []

    if not addrs:
        try:
            addrs = [socket.inet_ntoa(a) for a in (info.addresses or []) if len(a) == 4]
        except Exception:
            addrs = []

    if not addrs:
        return

    ip = addrs[0]
    port = info.port

    # Decode TXT records
    props = {}
    for k, v in (info.properties or {}).items():
        try:
            key_str = k.decode() if isinstance(k, bytes) else str(k)
            val_str = v.decode() if isinstance(v, bytes) else (v or '')
            props[key_str] = val_str
        except Exception:
            pass

    # Filter: only SMCR devices
    device_type = props.get('device_type', props.get('device', ''))
    if device_type.lower() != 'smcr':
        return

    version = props.get('version', '')
    hostname = (info.server or '').rstrip('.')

    key = f"{ip}:{port}"
    found[key] = {
        'hostname': hostname,
        'ip':       ip,
        'port':     port,
        'version':  version,
    }


zc = Zeroconf()
ServiceBrowser(zc, "_http._tcp.local.", handlers=[on_change])
time.sleep(7)
zc.close()

print(json.dumps(list(found.values())))
