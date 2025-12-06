# Sena Firmware Archive

This repository preserves older firmware versions and installers for the Sena 50S motorcycle communication system, after Sena made firmware downgrades more difficult.

## Background

After upgrading my Sena 50S to firmware version 1.5, I experienced issues sharing music, and noticed that my ability to change the music volume with my phone's volume buttons stopped working.

I then spent an inordinate amount of time trying to figure out how to downgrade the Sena firmware. It turns out that Sena's newer installers prevent downgrading.

Below is a screenshot of the newest manager (v4.4.17), which lacks the ability to browse for a specific firmware version.
![](./new-manager-no-browse.png)

Whereas here's v4.4.9 which does have a browse button:
![](./old-manager-has-browse.png)

## Downgrade Instructions
### Steps to Downgrade

1. **Download the firmware file**
   - Choose the desired version from the `firmware` directory. For me, v1.3.1 works the best.
   - Download the firmware file to your computer

2. **Download the Sena Device Manager v4.4.9 Installer**
   - Look in the `installers` directory of this repo, and find the installer that works for your operating system. As far as I can tell, 4.4.9 is the last version of Sena installers that you can browse for a specific firmware file.
   - Download the installer and run it. 
   - Note, at the time of writing, you can also download it from the website if you prefer, by changing the download link to the version number you want, ie: `https://firmware.sena.com/senabluetoothmanager/SENADeviceManagerForMAC-v4.4.9.pkg` (the same works for windows).

3. **Run the Sena Device Manager installer, open the device manager**
   - Make sure you click NO when it prompts you to update the device manager.

3. **Connect your Sena**
   - For the 50S, you can connect it via USB-C cable to your computer, and just keep it off.

4. **Install older firmware**
   - Click next on the welcome screen, and have the device manager recognise your Sena.
   - Under the `Firmware to Update` title, click the `Browse` button, select the firmware file you downloaded in step 1.
   - Wait for it to complete

## Important Notes

- **In order to get all of the old functionality back** I also had to delete the Sena App from my phone.

## Contributing
Have you got other Sena firmware? Send it my way and I'll add it to this repo. Email me at joe AT joegaebel.com

## Thanks
- Thanks to Brandon Danowski for posting the 50S firmware!
- Thanks to Frank Albrecht for posting the R1 Evo firmware

## Disclaimer

This is an unofficial archive. Firmware files are property of Sena Technologies. Use at your own risk. The maintainers of this repository are not responsible for anything.
