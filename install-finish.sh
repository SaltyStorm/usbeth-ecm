# Run on the device by install.cmd after the two files are copied.
for f in /system/etc/usbeth-ecm.sh /system/etc/init/usbeth-ecm.rc; do
  sed -i 's/\r$//' $f          # Windows line endings would break both files
  chown root:root $f
  chmod 644 $f
  chcon u:object_r:system_file:s0 $f
done
sh -n /system/etc/usbeth-ecm.sh && echo "script syntax ok"
ls -lZ /system/etc/usbeth-ecm.sh /system/etc/init/usbeth-ecm.rc
echo "CR characters left: $(cat /system/etc/usbeth-ecm.sh /system/etc/init/usbeth-ecm.rc | grep -c "$(printf '\r')")"
sync
mount -o remount,ro / 2>/dev/null && echo "system is read-only again"
mount | grep " / " | cut -c1-80
