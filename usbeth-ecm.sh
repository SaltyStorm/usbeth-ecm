#!/system/bin/sh
# usbeth-ecm: wired Ethernet for a Realtek 0bda:8153 adapter whose chip is too
# new for this kernel's r8152 driver (v1.08.9 says "Unknown version 0x6010").
#
# The adapter has two USB configurations: 1 = Realtek's own mode, which only
# r8152 can drive, and 2 = standard CDC Ethernet, which the generic cdc_ether
# driver can drive. Left alone, the kernel ends up in configuration 1 with no
# driver, because r8152 claims the adapter and forces its own mode.
#
# This script watches for that state and fixes it:
#   1. turn off automatic driver matching for a moment, so r8152 isn't offered
#      the adapter again
#   2. switch the adapter to configuration 2
#   3. hand its CDC Ethernet interface to cdc_ether
#   4. turn automatic matching back on
# The result is a normal eth0, which Android then configures by DHCP.
#
# It leaves alone: an adapter r8152 did accept, an adapter already on
# cdc_ether, and every other USB device. Nothing is written to storage.
# Started by /system/etc/init/usbeth-ecm.rc once boot has completed.

B=/sys/bus/usb
ID_VENDOR=0bda
ID_PRODUCT=8153
MAX_TRIES=3       # per plug-in; Realtek warns against switching modes over and over
POLL=10           # seconds between looks

say() { log -t usbeth-ecm "$*"; }

trap 'echo 1 > $B/drivers_autoprobe' EXIT

bring_up() {
  D=$1
  name=${D##*/}
  echo 0 > $B/drivers_autoprobe
  echo 2 > $D/bConfigurationValue
  sleep 1
  # Tell cdc_ether to accept this ID, which also binds it right away.
  # "02" = match the communications interface; "0 0" = use the settings of
  # cdc_ether's own generic entry, so the interface is a plain Ethernet one.
  echo "$ID_VENDOR $ID_PRODUCT 02 0 0" > $B/drivers/cdc_ether/new_id
  sleep 1
  # Take the ID back out again; the binding stays. If it were left in, the next
  # plug-in would let cdc_ether grab the adapter while r8152 is still forcing
  # it back to its own mode, and this adapter hangs when it is switched from
  # working CDC Ethernet back to Realtek mode (seen 2026-11-12).
  echo "$ID_VENDOR $ID_PRODUCT" > $B/drivers/cdc_ether/remove_id
  echo 1 > $B/drivers_autoprobe
}

last=""
tries=0
say "watching for $ID_VENDOR:$ID_PRODUCT"

while true; do
  for D in $B/devices/[0-9]*-[0-9]*; do
    case "$D" in *:*) continue ;; esac
    [ -e "$D/idVendor" ] || continue
    [ "$(cat $D/idVendor):$(cat $D/idProduct)" = "$ID_VENDOR:$ID_PRODUCT" ] || continue
    name=${D##*/}
    cfg=$(cat $D/bConfigurationValue 2>/dev/null)

    # Working already, either way: nothing to do.
    [ "$cfg" = "2" ] && [ -e "$D/$name:2.0/driver" ] && continue
    [ "$cfg" = "1" ] && [ -e "$D/$name:1.0/driver" ] && continue

    # A new plug-in gets a fresh set of tries.
    key="$name/$(cat $D/devnum 2>/dev/null)"
    if [ "$key" != "$last" ]; then last=$key; tries=0; fi
    [ $tries -ge $MAX_TRIES ] && continue
    tries=$((tries + 1))

    # Give the kernel a moment to finish its own attempt first.
    sleep 2
    say "adapter $name has no driver (config $cfg); try $tries of $MAX_TRIES"
    bring_up $D
    if [ -e "$D/$name:2.0/driver" ]; then
      say "adapter $name is on cdc_ether: $(ls $D/$name:2.0/net 2>/dev/null)"
    else
      say "adapter $name still has no driver"
    fi
  done
  sleep $POLL
done
