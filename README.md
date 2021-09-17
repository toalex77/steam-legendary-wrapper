This is a wrapper to launch games from the Epic Games Store, through the alternative launcher "Legendary" (https://github.com/derrod/legendary), inside the Steam Client for Linux, within the Steam Linux Runtime environment.  

So you have to have installed the binary version (at the moment the Python Script is not supported. Legendary [requires](https://github.com/derrod/legendary#requirements) Python 3.8+, while Steam Linux Runtime provides Python 3.7) for Linux of "Legendary" (ex. https://github.com/derrod/legendary/releases/download/0.20.6/legendary). It must be on one of the folder of your PATH environment varibale.
You can get it from here https://github.com/derrod/legendary/releases  

If none was found, the wrapper search if you have a system wide version of Heroic Games Launcher (https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher) in /opt/Heroic, and use it's bundled "legendary" binary executable.  
Then put "steam-legendary-wrapper.sh" wherever you want and give it the execute permission with chmod +x steam-legendary-wrapper.sh

Now you can create in the Steam Client for Linux a non-Steam Game (Games -> Add a Non-Steam Game to My Library), specifying the full path to where you have put steam-legendary-wrapper.sh (ex. ~/bin/steam-legendary-wrapper.sh) and the game name in the Launch Options, surrounded by double quotes, if the name containing spaces (ex. "Absolute Drift").  

In the Launch Options, you can specify also a second optional parameter, with the desired Proton Version (ex. "Proton 6.3"). If omitted, at the moment, the wrapper set to the latest installed stable version.  
Then you can specify also a third optional parameter, with the desired Steam Linux Runtime version. If omitted, at the moment, the wrapper set "Steam Linux Runtime - Soldier". 

If you have to specify arguments for the game, you can add them after a "--". You can also use %command% syntax.

So for example you can run a game, specifying the Launch Options, as follow:  
`PROTON_LOG=1 taskset -c 1-4 %command% "Absolute Drift" "Proton-6.16-GE-1" -- --game-arg-1 --game-arg-2`

You can also use it as a Steam Compatibility Tool. Just call the wrapper with "compat-tool-install" parameter, or install manually, by copying the "Proton-LegendaryWrapper" folder under ~/.local/share/Steam/compatibilitytools.d and fixing the "steam-legendary-wrapper" symbolic link to point where you have putted the wrapper. For example, if you have cloned this repository in ~/bin, with commands:
- `mkdir -p ~/.local/share/Steam/compatibilitytools.d`
- `cp -a ~/bin/steam-legendary-wrapper/Proton-LegendaryWrapper ~/.local/share/Steam/compatibilitytools.d`
- `ln -sf ~/bin/steam-legendary-wrapper/steam-legendary-wrapper.sh ~/.local/share/Steam/compatibilitytools.d/Proton-LegendaryWrapper/proton`
to respectively make sure that ~/.local/share/Steam/compatibilitytools.d exists, copy the Proton-LegendaryWrapper folder in right place, and fix the symbolic link inside that folder.

Other parameters are "list-proton-versions" to lists all found versions of Proton and "list-runtime-versions" to lists all availabe versions of the Steam Linux Runtime. If called with "help" or "--help" it shows an usage help.