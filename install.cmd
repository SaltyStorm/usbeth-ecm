@echo off
rem Installs usbeth-ecm on an Android device so it runs at boot.
rem Needs: adb on your PATH, adb over network on, and root allowed for adb
rem (on LineageOS: Developer options > Rooted debugging).
rem Usage:  install.cmd DEVICE_IP
if "%~1"=="" (
  echo Usage: install.cmd DEVICE_IP
  exit /b 1
)
set "DEV=%~1:5555"
adb connect %DEV%
adb -s %DEV% root
ping -n 7 127.0.0.1 >nul
adb connect %DEV%
adb -s %DEV% remount
adb -s %DEV% push "%~dp0usbeth-ecm.sh" /system/etc/usbeth-ecm.sh
adb -s %DEV% push "%~dp0usbeth-ecm.rc" /system/etc/init/usbeth-ecm.rc
adb -s %DEV% shell sh < "%~dp0install-finish.sh"
echo Done. Reboot the device to start the helper.
