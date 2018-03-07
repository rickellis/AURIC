#!/usr/bin/env bash
#-----------------------------------------------------------------------------------
#                 _    
#   __ _ _  _ _ _(_)__ 
#  / _` | || | '_| / _|
#  \__,_|\_,_|_| |_\__|
#   AUR package manager
#
#-----------------------------------------------------------------------------------
VERSION="1.2.7"
#-----------------------------------------------------------------------------------
#
# AURIC is a fork of vam with a pretty interface, SRCINFO version comparison,
# package installation (with PKGBUILD auditing), search keyword coloring, 
# JSON parsing using either jq or jshon, and a few additional features
#
# The name AURIC is a play on two words: AUR and Rick. It's also the name
# of the main antagonist in the James Bond film Goldfinger.
#-----------------------------------------------------------------------------------
# Authors   :   AURIC :  Rick Ellis      https://github.com/rickellis/AURIC
#           :   VAM   :  Caleb Butler    https://github.com/calebabutler/vam        
# License   :   MIT
#-----------------------------------------------------------------------------------

# Name of local AUR git repo directory
AURDIR="$HOME/.AUR"

# AUR package info URL
AUR_INFO_URL="https://aur.archlinux.org/rpc/?v=5&type=info&arg[]="

# AUR package search URL
AUR_SRCH_URL="https://aur.archlinux.org/rpc/?v=5&type=search&by=name&arg="

# GIT URL for AUR repos. %s will be replaced with package name
GIT_AUR_URL="https://aur.archlinux.org/%s.git"

# Will contain the list of all installed packages. This gets set automatically
LOCAL_PKGS=""

# Name of installed JSON parser. This gets set automatically.
JSON_PARSER=""

# Whether a package is a dependency. This gets set automatically.
IS_DEPEND=false

# Flag gets set during migration to ignore dependencies since 
# these will already have been installed previously
# This gets set automatically.
IS_MIGRATING=false

# Array containg all successfully downloaded packages.
# If this contains package names AURIC will prompt
# user to install after downloading
TO_INSTALL=()

# ----------------------------------------------------------------------------------

# Load colors script to display pretty headings and colored text
# This is an optional (but recommended) dependency
BASEPATH=$(dirname "$0")
if [[ -f "${BASEPATH}/colors.sh" ]]; then
    . "${BASEPATH}/colors.sh"
else
    heading() {
        echo "----------------------------------------------------------------------"
        echo " $2"
        echo "----------------------------------------------------------------------"
        echo
    }
fi

# ----------------------------------------------------------------------------------

# Help screen
help() {
    echo 
    echo -e "auric -d package-name\t# Download a package"
    echo -e "auric -i package-name\t# Installs package if local version exists."
    echo -e "\t\t\t# If package does not exist it hands it off to auric -d package-name"
    echo -e "auric -u package-name\t# Update a package"
    echo -e "auric -u \t\t# Update all installed packages"
    echo -e "auric -s package-name\t# Search for a package"
    echo -e "auric -q \t\t# Show all local packages in AURIC"
    echo -e "auric -r package-name\t# Remove a package"
    echo -e "auric -m \t\t# Migrate previously installed AUR packages to AURIC"
    echo -e "auric -v \t\t# Show version info"
    echo
    exit 1
}

# ----------------------------------------------------------------------------------

# Validate whether an argument was passed
validate_pkgname(){
    if [[ -z "$1" ]]; then
        echo -e "${red}Error: Package name required${reset}"
        echo
        echo "See help menu for more info:"
        echo
        echo -e "\t${cyan}auric --help${reset}"
        echo
        exit 1
    fi
}

# ----------------------------------------------------------------------------------

# Download a package and its dependencies from AUR
download() {
    # Make sure we have a package name
    validate_pkgname "$1"

    # Get a list of all installed packages
    if [[ "${LOCAL_PKGS}" == "" ]]; then
        LOCAL_PKGS=$(pacman -Sl)
    fi

    # Move into the AUR folder
    cd "$AURDIR" || exit

    for PKG in $@; do

        # Fetch the JSON data associated with the submitted package name
        curl_result=$(curl -fsSk "${AUR_INFO_URL}${PKG}")

        # Parse the result using the installed JSON parser
        if [[ $JSON_PARSER == 'jq' ]]; then
            json_result=$(echo "$curl_result" | jq -r '.results')
        else
            json_result=$(echo "$curl_result" | jshon -e results)
        fi

        # Did the package query return a valid result?
        if [[ $json_result == "[]" ]]; then

            # Presumably, if the user is migrating existing packages to AURIC
            # all the dependencies will already be installed. We don't need
            # to issue warnings in that case
            if [[ $IS_MIGRATING == true ]]; then
                continue
            fi

            # If it's a non-AUR dependency we inform them that makepkg will deal with this
            if [[ $IS_DEPEND == true ]]; then
                echo -e "${red}NON-AUR:${reset} ${cyan}${PKG}${reset} is not in the AUR"
                echo -e "${yellow}Makepkg will resolve this dependency automatically during installation${reset}"
                echo
            else
                echo -e "${red}MISSING:${reset} ${cyan}${PKG}${reset} is not in the AUR"
                echo -e "${yellow}Check package name spelling or use pacman to search in the offical Arch repoitories${reset}"
                echo
            fi
        else

            # If a folder with the package name exists in the local repo we skip it
            if [[ -d "$PKG" ]]; then
                echo -e "${red}PKGSKIP:${reset} ${cyan}${PKG}${reset} already exists in local repo"
                echo
                continue
            fi

            echo -e "${yellow}CLONING:${reset} $PKG"

            # Assemble the git package URL
            printf -v URL "$GIT_AUR_URL" "$PKG"

            # Clone it
            git clone $URL 2> /dev/null

            # Was the clone successful?
            if [[ "$?" -ne 0 ]]; then
                echo -e "${red}FAILURE:${reset} Unable to clone. Git error code: ${?}"
                echo
                continue
            fi

            # Extra precaution: We make sure the package folder was created in the local repo
            if [[ -d "$PKG" ]]; then
                echo -e "${green}SUCCESS:${reset} ${PKG} cloned"
                echo
            else
                echo -e "${red}PROBLEM:${reset} An unknown error occurred. ${PKG} not downloaded"
                echo
                continue
            fi

            # We don't bother with dependencies during migration since they'll already be installed
            if [[ $IS_MIGRATING == true ]]; then
                continue
            fi            

            # Add the package to the install array
            TO_INSTALL+=("$PKG")

            # Get the package dependencies using installed json parser
            if [[ $JSON_PARSER == 'jq' ]]; then
                has_depends=$(echo "$curl_result" | jq -r '.results[0].Depends') 
            else
                has_depends=$(echo "$curl_result" | jshon -e results -e 0 -e Depends)
            fi

            # If there is a result, recurisvely call this function with the dependencies
            if [[ $has_depends != "[]" ]] && [[ $has_depends != null ]]; then

                if [[ $JSON_PARSER == 'jq' ]]; then
                    dependencies=$(echo "$curl_result" | jq -r '.results[0].Depends[]') 
                else
                    dependencies=$(echo "$curl_result" | jshon -e results -e 0 -e Depends -a -u)
                fi
        
                # Run through the dependencies
                for depend in "${dependencies}"; do

                    # Remove everything after >= in $depend
                    # Some dependencies have minimum version requirements
                    # which screws up the package name
                    depend=$(echo $depend | sed "s/[>=].*//")

                    # See if the dependency is already installed
                    echo "$LOCAL_PKGS" | grep "$depend" > /dev/null

                    # Download it
                    if [[ "$?" == 1 ]]; then
                        IS_DEPEND=true
                        download "$depend"
                    fi
                    IS_DEPEND=false
                done
            fi
        fi
    done
}

# ----------------------------------------------------------------------------------

install() {
    # Make sure we have a package name
    validate_pkgname "$1"
    local PKG
    PKG=$1

    # If the local package doesn't exist we hand off the task to the download function
    if [[ ! -d "${AURDIR}/${PKG}" ]]; then
        download $PKG
        return 0
    fi

    read -p "Are you sure you want to install ${PKG} [Y/n]? " CONSENT
    if [[ ! -z $CONSENT ]] && [[ ! $CONSENT =~ [y|Y] ]]; then
        echo
        echo "Goodbye..."
    else
        doinstall $PKG
    fi
}

# ----------------------------------------------------------------------------------

# Install a package
doinstall() {
    # Make sure we have a package name
    validate_pkgname "$1"
    local PKG
    PKG=$1
    echo

    cd ${AURDIR}/${PKG}

    # Make sure the PKGBUILD script exists
    if [[ ! -f "${AURDIR}/${PKG}/PKGBUILD" ]]; then
        echo -e "${red}ERROR: PKGBUILD script does not exist in ${AURDIR}/${PKG}"
        echo
        exit 1
    fi

    read -p "Before installing, do you want to audit the PKGBUILD file? [Y/n] " AUDIT

    if [[ ! $AUDIT =~ [y|Y] ]] && [[ ! $AUDIT =~ [n|N] ]] && [[ ! -z $AUDIT ]]; then
        echo
        echo "Invalid entry. Aborting..."
        return 0
    fi

    if [[ -z $AUDIT ]] || [[ $AUDIT =~ [y|Y] ]]; then
        nano PKGBUILD
        echo
        read -p "Continue installing? [Y/n] " CONSENT
        if [[ ! -z $CONSENT ]] && [[ ! $CONSENT =~ [y|Y] ]]; then
            echo
            echo "Goodbye..."
            return 0
         fi
    fi

    echo
    echo -e "RUNNING MAKEPKG ON ${cyan}${PKG}${reset}"
    echo

    # MAKEPKG FLAGS
    # -s = Resolve and sync pacman dependencies prior to building
    # -i = Install the package if built successfully.
    # -r = Remove build-time dependencies after build.
    # -c = Clean up temporary build files after build.
    makepkg -sic
}

# ----------------------------------------------------------------------------------

# Update git repos
update() {
    cd "$AURDIR" || exit
    echo "CHECKING FOR UPDATES"
    if [[ -z $1 ]]; then
        for DIR in ./*; do
            echo
            # Extract the package name from the directory path
            DIR=${DIR//\//}
            DIR=${DIR//./}
            doupdate $DIR
            cd ..
        done
    else
        echo
        doupdate $1
    fi
}

# ----------------------------------------------------------------------------------

# Perform the upddate routine
doupdate() {
    local PKG
    PKG=$1

    if [[ ! -d ${AURDIR}/${PKG} ]]; then
        echo -e "${red}MISSING:${reset} ${PKG} is not a package in ${AURDIR}"
        echo
        exit 1
    fi

    cd ${AURDIR}/${PKG} || exit
    git pull >/dev/null 2>&1

    # Get the version number of the currently installed package
    local_pkgver=$(pacman -Q $PKG)

    # Remove the package name, leaving only the version/release number
    local_pkgver=$(echo $local_pkgver | sed "s/${PKG} //")
    local_pkgver=$(echo $local_pkgver | sed "s/[ ]//")

    # Open .SRCINFO and get the version/release numbers
    # for comparison with the installed version
    pkgver=$(sed -n 's/pkgver[ ]*=//p'  .SRCINFO)
    pkgrel=$(sed -n 's/pkgrel[ ]*=//p'  .SRCINFO)

    # Kill stray spaces
    pkgver=$(echo $pkgver | sed "s/[ ]//")
    pkgrel=$(echo $pkgrel | sed "s/[ ]//")

    # Combine pkgver and pkgrel into the new full version number for comparison
    if [[ ! -z $pkgrel ]]; then
        new_pkgver="${pkgver}-${pkgrel}"
    else
        new_pkgver="${pkgver}"
    fi

    echo -e "PACKAGE: ${PKG}"

    if [[ $(vercmp $new_pkgver $local_pkgver) -eq 1 ]]; then
        echo -e "${green}NEW VER: ${PKG} ${pkgver} is available${reset}"
        echo -e "${yellow}PKG BLD: Build files have been downloaded. ${PKG} is ready to be reinstalled${reset}" 

        TO_INSTALL+=("$PKG")
    else
        echo -e "${cyan}CURRENT: ${PKG} is up to date${reset}"
    fi
}

# ----------------------------------------------------------------------------------

# AUR package name search
search() {
    local json_result
    local PKG
    PKG=$1

    # Fetch the JSON data associated with the package name search
    curl_result=$(curl -fsSk "${AUR_SRCH_URL}${PKG}")

    # Parse the result using the installed JSON parser
    if [[ $JSON_PARSER == 'jq' ]]; then
        json_result=$(echo "$curl_result" | jq -r '.results[] .Name')
    else
        json_result=$(echo "$curl_result" | jshon -e results -a -e Name -u)
    fi

    if [[ $json_result == "[]" ]] || [[ $json_result == null ]]; then
        echo -e "${red}NO RESULTS:${reset} No results for the term \"${cyan}${PKG}${reset}\""
    else
        echo "SEARCH RESULTS"
        echo
        for res in $json_result; do
            # Capture the search term and surround it with %s
            # so we can use printf to replace with color variables
            res=$(echo "$res" | sed "s/\(.*\)\(${PKG}\)\(.*\)/\1%s\2%s\3/")

            printf -v res "$res" "${cyan}" "${reset}"

            echo -e " ${res}"
        done
    fi
}

# ----------------------------------------------------------------------------------

# Migrate all previously installed AUR packages to AURIC
migrate() {
    echo "MIGRATING INSTALLED AUR PACKAGES TO AURIC"
    echo
    AURPKGS=$(pacman -Qm | awk '{print $1}')
    IS_MIGRATING=true
    for PKG in $AURPKGS; do
        PKG=${PKG// /}
        download "$PKG"
    done
    IS_MIGRATING=false
    TO_INSTALL=()
}

# ----------------------------------------------------------------------------------

# Show locally installed packages
query() {
    echo "INSTALLED PACKAGES"
    echo
    cd $AURDIR
    PKGS=$(ls)

    for P in $PKGS; do
        echo -e "  ${cyan}${P}${reset}"
    done
}

# ----------------------------------------------------------------------------------

# Remove both the local git repo and the package via pacman
remove() {
    cd "$AURDIR" || exit
    PKG=$1
    if [[ ! -d ${AURDIR}/${PKG} ]]; then
        echo -e "${red}ERROR: ${PKG} is not an installed package"
        echo
        exit 1
    fi

    echo -e "Are you sure you want to remove the following package?"
    echo
    echo -e " ${cyan}${PKG}${reset}"
    echo
    read -p "ENTER [Y/n] " CONSENT

    if [[ $CONSENT =~ [y|Y] ]]; then
        sudo pacman -Rsc $PKG --noconfirm
        rm -rf ${AURDIR}/${PKG}
        echo
        echo -e "${red}REMOVED:${reset} ${PKG}"
    else
        echo
        echo "Goodbye..."
    fi
}

# ----------------------------------------------------------------------------------

function version() {
    heading purple "AURIC VERSION ${VERSION}"
}

# ----------------------------------------------------------------------------------

# A little space to get things going...
echo

# Is jq or jshon installed? 
if command -v jq &>/dev/null; then
    JSON_PARSER="jq"
elif command -v jshon &>/dev/null; then
    JSON_PARSER="jshon"
else
    echo -e "${red}DEPENDENCY ERROR:${reset} No JSON parser installed"
    echo
    echo "This script requires either jq or jshon"
    echo
    exit 1
fi

# Is curl installed?
if ! command -v curl &>/dev/null; then
    echo -e "${red}DEPENDENCY ERROR:${reset} Curl not installed"
    echo
    echo "This script requires Curl to retrieve search results and package info"
    echo
    exit 1
fi

# Is vercmp installed?
if ! command -v vercmp &>/dev/null; then
    echo -e "${red}DEPENDENCY ERROR:${reset} vercmp not installed"
    echo
    echo "This script requires vercmp to to compare version numbers"
    echo
    exit 1
fi

# No arguments, we show help
if [[ -z "$1" ]]; then
    echo -e "AURIC COMMANDS"
    help
fi

CMD=$1          # first argument
CMD=${CMD,,}    # lowercase
CMD=${CMD//-/}  # remove dashes
CMD=${CMD// /}  # remove spaces

# Show help menu
if [[ $CMD =~ [h] ]] ; then
    echo -e "AURIC COMMANDS"
    help
fi

# Invalid arguments trigger help
if [[ $CMD =~ [^diusqrmv] ]]; then
    echo -e "${red}INVALID REQUEST. SHOWING HELP MENU${reset}"
    help
fi

# Create the local AUR folder if it doesn't exist
if [[ ! -d "$AURDIR" ]]; then
    mkdir -p "$AURDIR"
fi

# Remove the first argument since we're done with it
shift

# Process the request
case "$CMD" in
    d)  download "$@" ;;
    i)  install "$@" ;;
    u)  update "$@" ;;
    s)  search "$@" ;;
    q)  query "$@" ;;
    r)  remove "$@" ;;
    m)  migrate "$@" ;;
    v)  version ;;
    *)  help ;;
esac

# ----------------------------------------------------------------------------------

# If the TO_INSTALL array contains package names we offer to install them
if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    echo

    if [[ ${#TO_INSTALL[@]} == 1 ]]; then
        echo "Would you like to install the package?"
    else
        echo "Would you like to install the packages?"
    fi 
    
    echo
    for PKG in ${TO_INSTALL[@]}; do
        echo -e "  ${cyan}${PKG}${reset}"
    done
    echo
    read -p "ENTER [Y/n] " CONSENT

    if [[ ! -z $CONSENT ]] && [[ ! $CONSENT =~ [y|Y] ]]; then
        echo
        echo "Goodbye..."
    else
        # Run through the install array in reverse order.
        # This helps ensure that dependencies get installed first.
        # The order doesn't matter after updating, only downloading
        for (( i=${#TO_INSTALL[@]}-1 ; i>=0 ; i-- )) ; do
            doinstall "${TO_INSTALL[i]}"
        done
    fi
fi
echo