@echo off
rem Removes usbeth-ecm from an Android device. After the next reboot the
rem adapter goes back to having no driver.
rem Usage:  uninstall.cmd DEVICE_IP
if "%~1"=="" (
  echo Usage: uninstall.cmd DEVICE_IP
  exit /b 1
)
set "DEV=%~1:5555"
adb connect %DEV%
adb -s %DEV% root
ping -n 7 127.0.0.1 >nul
adb connect %DEV%
adb -s %DEV% remount
adb -s %DEV% shell "rm -f /system/etc/usbeth-ecm.sh /system/etc/init/usbeth-ecm.rc; sync; mount -o remount,ro /"
echo Done. Reboot the device.
