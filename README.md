# AURIC
Arch User Repository package manager based on vam.

<img src="https://i.imgur.com/8ZIisx8.png" />

AURIC is a fork of __[vam](https://github.com/calebabutler/vam)__ with a pretty interface, `SRCINFO` version comparison for better reliability, package installation (with `PKGBUILD` auditing), local and remote dependency verification, search keyword coloring, and a few additional features.

The name AURIC is a play on two words: AUR and Rick. It's also the name of the main antagonist in the James Bond film Goldfinger.

## Background Info
There are two basic ways to install and update packages from the Arch User Repository: Use a package manager or do it manually. If you are a new Arch Linux user, you should always use the later method before settling on one of the many available package managers, as this will better equip you to run Arch.

So how do you install packages manually? The classic way, prior to AUR moving to github was this:

* Search for your desired package at the __[AUR website](https://aur.archlinux.org/)__.
* Download and unpack the tar.gz archive.
* Audit the `PKGBUILD` file for security.
* Run `makepkge` to install it.

The process wasn't that hard, but it did require keeping track of version numbers so you could periodically check the AUR site for version updates, along with managing AUR dependencies. If you had only a few AUR packages installed it was no big deal, but as your software stash grew it could get cumbersome. This is where a package manager comes in. It does all that for you.

After the AUR moved everything to github the process got simpler: You could use `git clone` to keep local repos with your AUR packages. To check for updates, instead of looking up version numbers, you run a `git pull`. If the pull is already up to date there's nothing to do. If the pull results in changes you run `makepkg` on the new `PKGBUILD` that got downloaded when you pulled. Definitely easier, but you still had to manage AUR dependencies.

AURIC started life as my desire to write a shell script that automates the above process, including the dependency management. When I stumbled onto vam I realized that someone else had a similar idea and had written the core functionality. At a mere 55 lines of code, however, that script is extremely lean. It only handles package and dependency downloading, and runs a git pull to check for updates. I took vam and built it into AURIC.

The way it works is this: AURIC creates a hidden folder in your home directory called .AUR in which it stores git clones of your AUR packages. When you tell AURIC to check for updates it does a git pull for each of the packages and compares the installed version to the new version. If the new version number is greater, it informs you that `makepkg` should be run and offers to do it for you.

The one major downside to using a `git pull` to determine if a package is out of date is this: You can only do a git pull once. Since the pull updates your local repo, subsequent pulls will show the package as being current, even if you didn't actually run `makepkg`. In other words, you might have applications that are out of date even though git thinks you are current.

So more reliable version comparison was one thing I wanted to solve in AURIC. I did that by using the `SRCINFO` file data and comparing it to the installed version number returned by pacman. That way, regardless of whether your git repo is current you'll be informed that you need to update. I also wanted AURIC to handle the package installation (and with that, `PKGBUILD` auditing). Along the way I added much more thorough error handling, package dependency verification, automated migration of currently installed packages to AURIC, colored keyword search results, and support for jq and jshon.

Should you use AURIC? If you are happy with your current package manager then probably not. If you are looking for a simple tool that helps automate the tasks you are already comfortable doing then you might give it a try.

## Usage

    $  auric -i  package-name  # Download and install a package and its dependencies

    $  auric -u  package-name  # Check for updates on a specific package
    $  auric -u                # Check for updates on all packages

    $  auric -s  package-name  # Search the AUR repo for a package

    $  auric -q                # List all your local AUR packages

    $  auric -vl package-name  # Verify that all dependencies for a local package are installed
    $  auric -vr package-name  # Verify that all dependencies for a remote package are installed

    $  auric -m  package-name  # Migrate a specific package to AURIC
    $  auric -m                # Migrate all previously installed AUR packages to AURIC

    $  auric -r  package-name  # Remove package. It runs sudo pacman -Rsc and deletes the local git repo


## Dependencies
AURIC requires the following packages:

    * Curl for remote data fetching
    * Either jq or jshon to parse the query results
    * vercmp to compare versions (installed by default in Arch)
    * Bash 4 or newer


## Terminal Alias
To make running the script more convenient you can add the following alias to your __.bashrc__ file, and then just enter the various __auric__ commands from your terminal without having to traverse into the auric directory.

    auric() {
        /path/to/AURIC/auric.sh $@
    }

## License

MIT

Copyright 2018 Rick Ellis, Caleb Butler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.