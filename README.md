# AURIC
Minimalist Arch User Repository package manager based on vam.

<img src="https://i.imgur.com/klpv9KP.png" />

AURIC is mostly just __[vam](https://github.com/calebabutler/vam)__ with a pretty interface, better version comparison handling, package installation, search keyword coloring, JSON parsing using either jq or jshon, and a few additional features. 

The name AURIC is a play on two words: AUR and Rick. It's also the name of the main antagonist in the James Bond film Goldfinger.

## Background Info
There are two basic ways to install and update packages from the Arch User Repository: Use a package manager or do it manually. If you are a new Arch Linux user, you should always use the latter method before settling on one of the many available package managers, as this will give you much more insight.

So how do you install packages manually? The classic way prior to AUR moving to github was this:

* Search for your desired package at the __[AUR](https://aur.archlinux.org/)__ website.
* Download and unpack the tar.gz archive.
* Audit the `PKGBUILD` file for security.
* Run `makepkge` to install it.1

The process wasn't that hard, but it did require keeping track of version numbers and needed dependencies so you could periodically check the AUR site for version updates. If you had only a few AUR packages installed it was no big deal, but as your software stash grew it could get cumbersome. This is where a package manager comes in. It does all this for you.

After the AUR moved everything to github the process got simpler: Instead of manually downloading a package, you just use `git clone`. To check for updates, instead of looking up version numbers, you run a `git pull`. If the pull is already up to date there's nothing to do. If the pull results in changes you run `makepkg` again. Definitely easier, but if the package contains dependencies that are not from the official repositories (makepkg resolves all pacman dependencies automatically) then you still have to manage them yourself.

AURIC started life as my desire to write a shell script that automates the above process. When I stumbled onto vam I realized that someone else had the same idea and had written the core functionality. I took that script an built it into AURIC.

The one major downside to using a `git pull` to determine if a package is out of date is this: You can only do a git pull once to determine if a package is out of date. Since the pull updates your local repo, subsequent calls to `git pull` will show the package as being current--even if you didn't actually run `makepkg` to update the package. In other words, you might have applications that are out of date even though git thinks you are current.

So better version comparison was one thing I wanted to solve in AURIC, and I wanted it to handle the package installation. Along the way I also added much more thorough error handling and a few other things, like automated migration of currently installed packages to git management.

Should you use AURIC? If you are happy with your current package manager I would say no. If you are looking for something extremely simple that helps automate the tasks you are already comfortable doing, then you might give it a try.

## Usage

    $  auric -d package-name  # Download a package

    $  auric -i package-name  # Install package downloaded from AUR

    $  auric -u package-name  # Update a specific package
    $  auric -u               # Update all packages

    $  auric -s package-name  # Search the AUR repo for a package

    $  auric -q               # List all local AUR packages

    $  auric -r package-name  # Runs sudo pacman -Rsc and deletes the local git repo

    $  auric -m               # Migrate previously installed AUR packages to AURIC

    $  auric -v               # Show version number

## License

MIT

Copyright 2018 Rick Ellis, Caleb Butler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.