#!/usr/bin/env bash
# Common utilities shared across ServoBox library files

# Smart virsh wrapper: uses sudo only if we can't connect to libvirt
# Always connects to qemu:///system for persistence
# Tests actual connectivity rather than group membership (groups command is session-specific)
virsh_cmd() {
  # Try without sudo first - if it works, we have access
  if virsh -c qemu:///system version >/dev/null 2>&1; then
    virsh -c qemu:///system "$@"
  else
    # Need sudo for access
    sudo virsh -c qemu:///system "$@"
  fi
}

# Check if a command exists
have() { 
  command -v "$1" >/dev/null 2>&1
}

