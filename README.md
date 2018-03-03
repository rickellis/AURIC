# AURIC
Minimalist AUR package manager

AURIC is mostly just __[vam](https://github.com/calebabutler/vam)__ with a pretty face, better search results, more error trapping, makepkg support, JSON parsing using either jq or jshon, and a few additional features. Caleb Butler does an excellent job of describing the concept at the above link. His script is bare bones, so I built it into something I'd want to use.

The name AURIC is a play on two words: AUR and Rick. It's also the name of the main antagonist in the James Bond film Goldfinger.

## Usage


    $  auric -d package-name  # Download a package

    $  auric -i package-name  # Install a downloaded package

    $  auric -u package-name  # Update a specific package
    $  auric -u               # Update all packages

    $  auric -s package-name  # Search the AUR repo for a package

    $  auric -u               # List all local AUR packages

    $  auric -r package-name  # Uninstall a package and remove all unused dependencies

    $  auric -m               # Migrate previously installed AUR packages to AURIC