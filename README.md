<div align="center" markdown="1">
 <sup>Special thanks to:</sup>
 <br>
 <a href="https://github.com/exelban/stats">
  <img width="200" alt="Stats" src="https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"/>
 </a>
 <br>
 <a>Mornits is built based on Stats</a>
</div>

---

<p align="center">
  <b>English</b> | <a href="README_zh.md">简体中文</a>
</p>

# Mornits

<a href="https://github.com/4ving/mornits/releases"><p align="center"><img src="https://github.com/4ving/Mornits/blob/main/Mornits/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="120"></p></a>

![Mornits screenshot](https://github.com/user-attachments/assets/cec7f89d-b8fb-4473-b695-4123ad67a003)

macOS and remote Linux system monitor in your menu bar

## Installation
### Manual
You can download the latest version [here](https://github.com/4ving/mornits/releases/latest/download/Mornits.dmg).
This will download a file called `Mornits.dmg`. Open it and move the app to the application folder.
Note for macOS users: If you see a "Developer cannot be verified" warning, please Right-click the app and select Open, or go to System Settings > Privacy & Security and click Open Anyway.

## Requirements
Stats is supported on the released macOS version starting from macOS 10.15 (Catalina).

## Features
Mornits is an application that allows you to monitor macOS systems and remote Linux servers.

 - Remote server monitoring and aggregated data display
 - CPU utilization
 - Memory usage
 - Disk utilization
 - Network usage
 - GPU utilization
 - Battery level
 - Fan's control (not maintained)
 - Sensors information (Temperature/Voltage/Power)
 - Bluetooth devices
 - Multiple time zone clock

## FAQs
### Why it doesn't work with my LXD server?
Currently, Mornits only supports full-system Linux servers. We filter out virtual hardware for disks and network interfaces. We generally only use it to monitor the status of remote physical servers, right?

### Why macOS is asking to install a new helper tool?
This permission requirement is for macOS system sensors (such as CPU temperature and fan speed) are located within the low-level System Management Controller (SMC). Standard applications running with user-level privileges do not have the necessary permissions to directly read or modify this data.

### How do you change the order of the menu bar icons?
macOS decides the order of the menu bar items not `Mornits` - it may change after the first reboot after installing Mornits.

To change the order of any menu bar icon - macOS Mojave (version 10.14) and up.

1. Hold down ⌘ (command key).
2. Drag the icon to the desired position on the menu bar.
3. Release ⌘ (command key)

### How to reduce energy impact or CPU usage of Mornits?
Mornits tries to be efficient as it's possible. But reading some data periodically is not a cheap task. Each module has its own "price". So, if you want to reduce energy impact from the Mornits you need to disable some Mornits modules. The most inefficient modules are Sensors and Bluetooth. Disabling these modules could reduce CPU usage and power efficiency by up to 50% in some cases.

### Sensors show incorrect CPU/GPU core count
CPU/GPU sensors are simply thermal zones (sensors) on the CPU/GPU. They have no relation to the number of cores or specific cores.
For example, a CPU is typically divided into two clusters: efficiency and performance. Each cluster contains multiple temperature sensors, and Mornits simply displays these sensors. However, "CPU Efficient Core 1" does not represent the temperature of a single efficient core—it only indicates one of the temperature sensors within the efficiency core cluster.
Additionally, with each new SoC, Apple changes the sensor keys. As a result, it takes time to determine which SMC values correspond to the appropriate sensors. If anyone knows how to accurately match the sensors for Apple Silicon, please contact me.

### App crash – what to do?
First, ensure that you are using the latest version of Mornits. There is a high chance that a fix preventing the crash has already been released. If you are already running the latest version, check the open issues. Only if none of the existing issues address your problem should you open a new issue.

### Why my issue was closed without any response?
Most probably because it's a duplicated issue and there is an answer to the question, report, or proposition. Please use a search by closed issues to get an answer.
So, if your issue was closed without any response, most probably it already has a response.


## Supported languages
- English
- Polski
- Українська
- Русский
- 中文 (简体) (thanks to [chenguokai](https://github.com/chenguokai), [Tai-Zhou](https://github.com/Tai-Zhou), and [Jerry](https://github.com/Jerry23011))
- Türkçe (thanks to [yusufozgul](https://github.com/yusufozgul) and [setanarut](https://github.com/setanarut))
- 한국어 (thanks to [escapeanaemia](https://github.com/escapeanaemia) and [iamhslee](https://github.com/iamhslee))
- German (thanks to [natterstefan](https://github.com/natterstefan) and [aneitel](https://github.com/aneitel))
- 中文 (繁體) (thanks to [iamch15542](https://github.com/iamch15542) and [jrthsr700tmax](https://github.com/jrthsr700tmax))
- Spanish (thanks to [jcconca](https://github.com/jcconca))
- Vietnamese (thanks to [HXD.VN](https://github.com/xuandung38))
- French (thanks to [RomainLt](https://github.com/RomainLt))
- Italian (thanks to [gmcinalli](https://github.com/gmcinalli))
- Portuguese (Brazil) (thanks to [marcelochaves95](https://github.com/marcelochaves95) and [pedroserigatto](https://github.com/pedroserigatto))
- Norwegian Bokmål (thanks to [rubjo](https://github.com/rubjo))
- 日本語 (thanks to [treastrain](https://github.com/treastrain))
- Portuguese (Portugal) (thanks to [AdamModus](https://github.com/AdamModus))
- Czech (thanks to [mpl75](https://github.com/mpl75))
- Magyar (thanks to [moriczr](https://github.com/moriczr))
- Bulgarian (thanks to [zbrox](https://github.com/zbrox))
- Romanian (thanks to [razluta](https://github.com/razluta))
- Dutch (thanks to [ngohungphuc](https://github.com/ngohungphuc))
- Hrvatski (thanks to [milotype](https://github.com/milotype))
- Danish (thanks to [casperes1996](https://github.com/casperes1996) and [aleksanderbl29](https://github.com/aleksanderbl29))
- Catalan (thanks to [davidalonso](https://github.com/davidalonso))
- Indonesian (thanks to [yooody](https://github.com/yooody))
- Hebrew (thanks to [BadSugar](https://github.com/BadSugar))
- Slovenian (thanks to [zigapovhe](https://github.com/zigapovhe))
- Greek (thanks to [sudoxcess](https://github.com/sudoxcess) and [vaionicle](https://github.com/vaionicle))
- Persian (thanks to [ShawnAlisson](https://github.com/ShawnAlisson))
- Slovenský (thanks to [martinbernat](https://github.com/martinbernat))
- Thai (thanks to [apiphoomchu](https://github.com/apiphoomchu))
- Estonian (thanks to [postylem](https://github.com/postylem))
- Hindi (thanks to [patiljignesh](https://github.com/patiljignesh))
- Finnish (thanks to [eightscrow](https://github.com/eightscrow))

You can help by adding a new language or improving the existing translation.

## License
[MIT License](https://github.com/4ving/mornits/blob/master/LICENSE)
