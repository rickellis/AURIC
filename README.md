# AURIC
Minimalist AUR package manager based on vam.

<img src="https://i.imgur.com/PmepGsO.png" />

AURIC is mostly just __[vam](https://github.com/calebabutler/vam)__ with a pretty interface, color-formatted search results, better error trapping, package installation (via makepkg), JSON parsing using either jq or jshon, and a few additional features. Caleb Butler does an excellent job of describing the concept at the above link and making a case for using git pulls to manage AUR packages. His script is bare bones, so I built it into something I'd want to use.

The name AURIC is a play on two words: AUR and Rick. It's also the name of the main antagonist in the James Bond film Goldfinger.

## Usage


    $  auric -d package-name  # Download a package

    $  auric -i package-name  # Install a downloaded package from AUR

    $  auric -u package-name  # Update a specific package
    $  auric -u               # Update all packages

    $  auric -s package-name  # Search the AUR repo for a package

    $  auric -u               # List all local AUR packages

    $  auric -r package-name  # Run sudo pacman -Rsc and delete the local git repo

    $  auric -m               # Migrate previously installed AUR packages to AURIC

    $  auric -v               # Show version number

<img src="https://i.imgur.com/mIQODNc.png" />

## License

MIT

Copyright 2018 Rick Ellis, Caleb Butler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.