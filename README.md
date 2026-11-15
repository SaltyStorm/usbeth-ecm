# usbeth-ecm

Wired Ethernet for Realtek RTL8153B USB adapters (USB ID `0bda:8153`) on Android
devices whose old kernel rejects them, without rebuilding the kernel.

If your adapter shows up on USB but you get no `eth0`, and the kernel log says
this, you have the problem this fixes:

```
r8152 1-1:1.0 (unnamed net_device) (uninitialized): Unknown version 0x6010
r8152 1-1:1.0 (unnamed net_device) (uninitialized): Unknown Device
```

## Why it happens

- The kernel's `r8152` driver is older than the chip. Support for the RTL8153B
  (version `0x6010`) arrived in Linux 4.13; many Android devices still run 4.9
  or older.
- These adapters also have a second USB configuration that speaks standard CDC
  Ethernet, which the generic `cdc_ether` driver could run. Old kernels block
  that on purpose: `cdc_ether` refuses `0bda:8153`, and `r8152` claims the
  adapter and forces it back to Realtek's own mode.

So the adapter ends up in a mode with no working driver.

## What the script does

`usbeth-ecm.sh` runs as root, looks every 10 seconds for a `0bda:8153` adapter
that has no driver, and then:

1. turns the kernel's automatic driver matching off for a moment
   (`/sys/bus/usb/drivers_autoprobe`), so `r8152` isn't offered the adapter again
2. switches the adapter to configuration 2, CDC Ethernet (`bConfigurationValue`)
3. tells `cdc_ether` to accept the ID with its normal Ethernet settings (`new_id`),
   which binds it
4. takes the ID back out (`remove_id`) and turns automatic matching back on

The result is an ordinary `eth0`. Android's Ethernet service picks it up and
runs DHCP. Nothing is written to storage, and no kernel, boot image or
bootloader is touched.

It leaves alone any adapter that already has a driver, and tries at most three
times per plug-in.

## Requirements

- Root on the device. This was built for a userdebug ROM with `adb root`.
- A system partition you can write to (`adb remount`), for the boot entry.
- A kernel with `cdc_ether` built in, and an Android build whose Ethernet
  service tracks `eth0`.
- The init entry uses `seclabel u:r:su:s0`, which exists on userdebug builds.
  On other builds you will need a different way to start the script as root at
  boot, such as a Magisk boot script.

## Install

On Windows, with `adb` on your PATH and the device reachable over network adb:

```
install.cmd 192.168.1.50
```

By hand, from any OS:

```
adb root
adb remount
adb push usbeth-ecm.sh /system/etc/usbeth-ecm.sh
adb push usbeth-ecm.rc /system/etc/init/usbeth-ecm.rc
adb shell sh < install-finish.sh
adb reboot
```

`install-finish.sh` strips Windows line endings, sets owner, mode and SELinux
label, and puts the system partition back to read-only.

To remove it, run `uninstall.cmd <device-ip>`, or delete
`/system/etc/usbeth-ecm.sh` and `/system/etc/init/usbeth-ecm.rc` and reboot.

`install.cmd` and `uninstall.cmd` are tidied copies of the scripts that were run
on the test device: the device address became an argument, and `adb` is taken
from PATH. They have not been run in this exact form. The by-hand commands
above are the same steps.

## Check that it worked

```
adb shell getprop init.svc.usbeth_ecm      # running
adb logcat -d -s usbeth-ecm                # "adapter 1-1 is on cdc_ether: eth0"
adb shell ip -4 addr show eth0
```

## Warnings

- **Don't switch the adapter back to configuration 1 while it is running.** On
  the adapter this was tested with, doing that made `r8152` reset it, read a
  garbage version (`0x7cf0`), and the adapter dropped off USB until it was
  unplugged and plugged in again. The script never does this, and it removes its
  ID from `cdc_ether` after binding so a later plug-in can't cause the same
  sequence.
- A ROM update replaces the system partition. Install again afterwards.
- The kernel log shows `kevent 12 may have been dropped` now and then. It was
  harmless in testing.
- If your kernel's `r8152` does support your adapter, you don't need this, and
  the script will see that and do nothing.

## Tested on

One device, so treat it as a starting point:

| | |
| --- | --- |
| Device | Amazon Echo Show 8, 1st gen (`crown`) |
| ROM | LineageOS 18.1 unofficial, userdebug |
| Kernel | 4.9.337, `r8152` v1.08.9 |
| Adapter | USB 3.0 gigabit, reports `0bda:8153` "Realtek USB 10/100/1000 LAN", chip version `0x6010` |
| Connection | micro-USB port through a powered OTG adapter (USB 2.0) |

Measured over the wire: gateway ping about 0.5 ms with none lost, 9.6 MB/s to
the device and 17.6 MB/s from it, no interface errors. It comes back by itself
after a reboot (about 50 seconds) and after unplugging and replugging the
adapter (about 11 seconds).

## Tools

`tools/kernel_usb_ids.py` reads the USB Ethernet driver ID tables out of an
arm64 kernel inside a ROM zip, so you can see which adapters your kernel
accepts and which IDs `cdc_ether` blocks before you buy anything:

```
python -I tools/kernel_usb_ids.py your-rom.zip some-empty-folder
```

## How this was made

Written with Claude, Anthropic's AI assistant, while getting my own Echo Show
onto Ethernet, and tested by me on the device above.

## License

MIT. See `LICENSE`.
