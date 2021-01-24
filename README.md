# rndr-watchdog
This Windows Powershell script ensures the RenderToken.com RNDRclient.exe (RNDR) is running at all time and allows to start/shutdown an alternative workload (Dual) when the client signals it is idle.

- Before starting the watchdog please edit the user config file: RNDR_Watchdog_Userconfig.ini

- For the dual workload to work properly you need to set the correct values for DualLauchCommand, DualProcessName in the user config file. If the software you want to use besides RNDR features a web API you can set the value DualWebAPIShutdownCommand accordingly. If not you should leave that value blank.

- The RNDR client application rndrclient.exe needs to be in the same folder as the watchdog.

- To launch the watchdog please doubleclick the batch file RNDR_Watchdog_START.bat

- If you want to Autostart the Watchdog with Windows, create a shortcut to RNDR_Watchdog_START.bat and run the command shell:startup to copy the shortcut into your computer's startup folder.

- This project has been implemented using T-Rex crypto mining software and crypto mining pool Ethermine. See https://github.com/trexminer/T-Rex/ and https://ethermine.org/start for downloads and configuration.

- The project will not be maintained on a regular basis and the author is not a professional developer.

### DISCLAIMER: This is a community built solution. No official RNDR project team support is provided for this script. If you prefer stability the team recommends not to use any custom scripts at all.

### DISCLAIMER: RNDR client runtime does not equal rendertime. The measured runtime includes all overhead for download/load/save/upload as well as failed jobs etc.
