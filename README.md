# AURIC
Minimalist Arch User Repository package manager based on vam.

<img src="https://i.imgur.com/mgxQwZS.png" />

AURIC is a fork of __[vam](https://github.com/calebabutler/vam)__ with a pretty interface, SRCINFO version comparison for better reliability, package installation (with PKGBUILD auditing), search keyword coloring, JSON parsing using either jq or jshon, and a few additional features. 

The name AURIC is a play on two words: AUR and Rick. It's also the name of the main antagonist in the James Bond film Goldfinger.

## Background Info
There are two basic ways to install and update packages from the Arch User Repository: Use a package manager or do it manually. If you are a new Arch Linux user, you should always use the later method before settling on one of the many available package managers, as this will better equip you to run Arch.

So how do you install packages manually? The classic way prior to AUR moving to github was this:

* Search for your desired package at the __[AUR](https://aur.archlinux.org/)__ website.
* Download and unpack the tar.gz archive.
* Audit the `PKGBUILD` file for security.
* Run `makepkge` to install it.

The process wasn't that hard, but it did require keeping track of version numbers and needed dependencies so you could periodically check the AUR site for version updates. If you had only a few AUR packages installed it was no big deal, but as your software stash grew it could get cumbersome. This is where a package manager comes in. It does all this for you.

After the AUR moved everything to github the process got simpler: Instead of manually downloading a package, you can run `git clone`. To check for updates, instead of looking up version numbers, you run a `git pull`. If the pull is already up to date there's nothing to do. If the pull results in changes you run `makepkg`.

Definitely easier, but if the package contains dependencies that are not from the official repositories (`makepkg` resolves all pacman dependencies automatically) then you still have to manage them yourself.

AURIC started life as my desire to write a shell script that automates the above process. When I stumbled onto vam I realized that someone else had a similar idea and had written the core functionality. I took that script and built it into AURIC.

The way it works is this: AURIC creates a hidden folder in your home directory called .AUR in which it stores git clones of AUR packages. When you tell AURIC to check for updates it does a git pull for each of the packages and compares the installed version to the new version. If the new version number is greater, it informs you that `makepkg` should be run (which you can do by calling the AURIC install function).

The one major downside to using a `git pull` to determine if a package is out of date is this: You can only do a git pull once. Since the pull updates your local repo, subsequent pulls will show the package as being current, even if you didn't actually run `makepkg`. In other words, you might have applications that are out of date even though git thinks you are current.

So better version comparison was one thing I wanted to solve in AURIC. I did that by using the SRCINFO file data and comparing it to the installed version number. I also wanted it to handle the package installation (and with that, PKGBUILD auditing). Along the way I added much more thorough error handling and a few other things, like automated migration of currently installed packages to AURIC, colored keyword search results, and support for jq and jshon parsing.

Should you use AURIC? If you are happy with your current package manager I would say no. If you are looking for something extremely simple that helps automate the tasks you are already comfortable doing, then you might give it a try.

## Usage

    $  auric -d package-name  # Download a package

    $  auric -i package-name  # Install a package you downloaded from AUR

    $  auric -u package-name  # Check for updates on a specific package
    $  auric -u               # Check for updates on all packages

    $  auric -s package-name  # Search the AUR repo for a package

    $  auric -q               # List all your local AUR packages

    $  auric -r package-name  # Remove package. It runs sudo pacman -Rsc and deletes the local git repo

    $  auric -m               # Migrate previously installed AUR packages to AURIC

    $  auric -v               # Show version number

## Terminal Shortcut
To make running the script more convenient you can add the following alias to your __.bashrc__ file, and then just enter the various __auric__ commands from your terminal without having to traverse into the AURIC directory.

    # AURIC AUR Helper
    function auric() {
        /path/to/AURIC/auric.sh $@
    }

## License

MIT

Copyright 2018 Rick Ellis, Caleb Butler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.