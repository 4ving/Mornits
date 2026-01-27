#! /bin/sh

sudo launchctl unload /Library/LaunchDaemons/com.4ving.Mornits.SMC.Helper.plist
sudo rm /Library/LaunchDaemons/com.4ving.Mornits.SMC.Helper.plist
sudo rm /Library/PrivilegedHelperTools/com.4ving.Mornits.SMC.Helper
sudo rm $HOME/Library/Application Support/Stats
