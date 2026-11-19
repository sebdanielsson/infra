#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# Kill switch for everything in this container's network namespace,
# piecemeal included: nothing leaves except through the tunnel, WireGuard's
# own packets to the VPN server, and KILLSWITCH_ALLOWED_NETWORKS (the local
# networks that must stay reachable). linuxserver runs /custom-cont-init.d
# before the tunnel comes up, and nothing removes the rules, so they hold
# while the tunnel is down, missing or restarting. IPv4 and IPv6 alike:
# IPv6 leaves only through the tunnel, so a tunnel without IPv6 can't leak
# it, and one with IPv6 carries it.
set -euo pipefail

# If the rules can't be installed, take the default routes away instead:
# no internet at all rather than the home connection.
trap 'echo "[killswitch] failed; removing the default routes"; ip -4 route del default 2>/dev/null || true; ip -6 route del default 2>/dev/null || true' ERR

allowed4=""
allowed6=""
for net in ${KILLSWITCH_ALLOWED_NETWORKS:-}; do
  case "${net}" in
    *:*) allowed6="${allowed6:+${allowed6}, }${net}" ;;
    *) allowed4="${allowed4:+${allowed4}, }${net}" ;;
  esac
done

{
  echo 'table inet killswitch'
  echo 'delete table inet killswitch'
  echo 'table inet killswitch {'
  echo '  chain output {'
  echo '    type filter hook output priority filter; policy drop;'
  echo '    oifname "lo" accept'
  echo '    oifname "wg*" accept'
  # WireGuard's encrypted packets to the VPN server carry wg-quick's fwmark.
  echo '    meta mark 0x0000ca6c accept'
  if [[ -n "${allowed4}" ]]; then
    echo "    ip daddr { ${allowed4} } accept"
  fi
  if [[ -n "${allowed6}" ]]; then
    echo "    ip6 daddr { ${allowed6} } accept"
  fi
  # Refuse rather than drop, so connections fail at once instead of hanging.
  echo '    meta l4proto tcp reject with tcp reset'
  echo '    reject with icmpx admin-prohibited'
  echo '  }'
  echo '}'
} | nft -f -

echo "[killswitch] traffic may leave only through the tunnel, to the VPN server, and to: ${KILLSWITCH_ALLOWED_NETWORKS:-no other networks}"
