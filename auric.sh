#!/usr/bin/env bash
#-----------------------------------------------------------------------------------
#                 _    
#   __ _ _  _ _ _(_)__ 
#  / _` | || | '_| / _|
#  \__,_|\_,_|_| |_\__|
#   AUR package manager
#
#-----------------------------------------------------------------------------------
VERSION="1.1.4"
#-----------------------------------------------------------------------------------
#
# AURIC is mostly just vam with a pretty interface, better version comparison
# handling, package installation, search keyword coloring, 
# JSON parsing using either jq or jshon, and a few additional features
#
# The name AURIC is a play on two words: AUR and Rick. It's also the name
# of the main antagonist in the James Bond film Goldfinger.
#-----------------------------------------------------------------------------------
# Authors   :   Rick Ellis      https://github.com/rickellis/AURIC
#           :   Caleb Butler    https://github.com/calebabutler/vam        
# License   :   MIT
#-----------------------------------------------------------------------------------

# Local AUR git repo
AURDIR="$HOME/.AUR"

# AUR package info URL
AUR_INFO_URL="https://aur.archlinux.org/rpc/?v=5&type=info&arg[]="

# AUR package search URL
AUR_SRCH_URL="https://aur.archlinux.org/rpc/?v=5&type=search&by=name&arg="

# GIT URL for AUR repos. %s will be replaced with package name
GIT_AUR_URL="https://aur.archlinux.org/%s.git"

# Successful git pull result - lowercase with no spaces, dashes, or punctuation.
# On MacOS a git pull results in: Already up-to-date.
# On Linux a git pull results in: Already up to date.
# Stripping everything but a-z allows cross-platform reliability.
GIT_RES_STR="alreadyuptodate"

# Will contain the list of all installed packages. 
# This gets set automatically
LOCAL_PKGS=""

# Name of installed JSON parser.
# This gets set automatically.
JSON_PARSER=""

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
    echo -e "auric -i package-name\t# Install a downloaded package"
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
    if [[ "$1" == false ]]; then
        echo -e "${red}Error: Package name required${reset}"
        echo
        echo -e "auric --help \t# Help menu"
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
        # If not it means the package is not in the AUR
        if [[ $json_result == "[]" ]]; then
            echo -e "${red}MISSING:${reset} ${cyan}${PKG}${reset} ${red}not in AUR. ${reset} ${yellow}Makepkg will resolve all non-AUR dependencies${reset}"
        else

            # If a folder with the package name exists in the local repo we skip it
            if [[ -d "$PKG" ]]; then
                echo -e "${red}PKGSKIP:${reset} ${cyan}${PKG}${reset} already exists in local repo"
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
                continue
            fi

            # Extra precaution: We make sure the package folder was created in the local repo
            if [[ -d "$PKG" ]]; then
                echo -e "${green}SUCCESS:${reset} ${PKG} cloned"
            else
                echo -e "${red}PROBLEM:${reset} An unknown error occurred. ${PKG} not downloaded"
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
                        download "$depend"
                    fi
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
    read -p "Are you sure you want to install ${PKG} [Y/n]? " CONSENT 
    if [[ $CONSENT =~ [y|Y] ]]; then
        doinstall $PKG
    else
        echo
        echo "Goodbye..."
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
    if [[ ! -d "${AURDIR}/${PKG}" ]]; then
        echo -e "${red}MISSING:${reset} Package does not exist in local repo"
        echo
        exit 1
    fi

    cd ${AURDIR}/${PKG}

    # Make sure the PKGBUILD script exists
    if [[ ! -f "${AURDIR}/${PKG}/PKGBUILD" ]]; then
        echo -e "${red}ERROR: PKGBUILD script does not exist in ${AURDIR}/${PKG}"
        echo
        exit 1
    fi

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
    if [[ -z $1 ]]; then
        echo "UPDATING ALL PACKAGES"
        echo
        for DIR in ./*; do
            # Extract the package name from the directory path
            DIR=${DIR//\//}
            DIR=${DIR//./}
            doupdate $DIR
            echo
            cd ..
        done
    else
        echo "UPDATING PACKAGE"
        echo
        doupdate $1
    fi 
}

# ----------------------------------------------------------------------------------

# Perform the upate routine
doupdate() {
    local PKG
    PKG=$1

    if [[ ! -d ${AURDIR}/${PKG} ]]; then
        echo -e "${red}MISSING:${reset} ${PKG} is not a package in ${AURDIR}"
        echo
        exit 1
    fi

    cd ${AURDIR}/${PKG} || exit

    GITRESULT=$(git pull 2> /dev/null)

    # Get the version number of the currently installed package
    LOCALVER=$(pacman -Q $PKG)

    # Remove the package name, leaving only the version number
    LOCALVER=$(echo $LOCALVER | sed "s/${PKG} //")

    # Open PKGBUILD to get the new version number and release number
    NEWVER=$(grep -r "^pkgver=+*" PKGBUILD)
    NEWREL=$(grep -r "^pkgrel=+*" PKGBUILD)

    # Remove quotes
    NEWVER=$(echo $NEWVER | sed "s/['\"]//g")
    NEWREL=$(echo $NEWREL | sed "s/['\"]//g")

    # Remove pkgver= and pkgrel=
    NEWVER=$(echo $NEWVER | sed "s/pkgver=//")
    NEWREL=$(echo $NEWREL | sed "s/pkgrel=//")

    # Strip variables
    NEWVER=$(echo $NEWVER | sed "s/\$[{]*[_a-zA-Z0-9]*[}]*//g")
    NEWREL=$(echo $NEWREL | sed "s/\$[{]*[_a-zA-Z0-9]*[}]*//g")

    # If NEWVER or NEWRL is blank it means that either pkgver= or pgkrel= in PKGBUILD
    # contained a variable. Rather than trying to parse out the values of those variables,
    # we will instead use the git pull result. This has one major downside: If the
    # user doesn't immediately install the new package, the next time the update function
    # gets run the package will show as being up to date even though the installed one
    # is older. If the PKGBUILD file does not contain variables in pkgver= or pgkrel= 
    # we can do an actual version comparison using vercmp every time that update is run.
    # If we can't use vercmp we issue a warning that they need to install immediately.
    # Here we conditionally select which method of comparison to use:
    if [[ -z $NEWVER ]] || [[ -z $NEWREL ]]; then

        # Format the result string for reliability
        GITRESULT=${GITRESULT,,}   # lowercase
        GITRESULT=$(echo $GITRESULT | sed "s/[^a-z]//g") # Remove all non a-z

        if [[ $GITRESULT != "$GIT_RES_STR" ]]; then
            MUST_UPDATE=true
            MESSAGE="A new version of ${PKG} is avaiable."
            MSGXTRA="IMPORTANT: Update this package immediately. Unable to use version comparison so\n"
            MSGXTRA+="any subsequent git pulls will show the package as being current even if it isn't"
        else
            MUST_UPDATE=false
            MESSAGE="PACKAGE: ${PKG}"
            MSGXTRA=""
        fi

    elif [[ $(vercmp $NEWVER $LOCALVER) -eq 1 ]]; then
        MUST_UPDATE=true
        if [[ ! -z $NEWREL ]]; then
            NEWVER="${NEWVER}-${NEWREL}"
        fi
        MESSAGE="${PKG} ${NEWVER} is available"
        MSGXTRA=""
    else
        MUST_UPDATE=false
        MESSAGE="PACKAGE: ${PKG}"
        MSGXTRA=""
    fi

    # Show the user the restult
    if [[ $MUST_UPDATE == true ]]; then
        echo -e "${yellow}UPDATE: ${MESSAGE}${reset}"
        echo -e "${green}PKGBLD: Build files have been downloaded. ${PKG} is ready to be reinstalled${reset}"
        echo -e "${red}${MSGXTRA}${reset}"
        TO_INSTALL+=("$PKG")
    else
        echo -e "${MESSAGE}"
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
    for PKG in $AURPKGS; do
        PKG=${PKG// /}
        download "$PKG"
    done
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
    echo "Would you like to install the packages?" 
    echo
    for PKG in ${TO_INSTALL[@]}; do
        echo -e "  ${cyan}${PKG}${reset}"
    done
    echo
    read -p "ENTER [Y/n] " CONSENT

    if [[ $CONSENT =~ [y|Y] ]]; then
        # Run through the install array in reverse order.
        # This helps ensure that dependencies get installed first.
        # The order doesn't matter after updating, only downloading
        for (( i=${#TO_INSTALL[@]}-1 ; i>=0 ; i-- )) ; do
            doinstall "${TO_INSTALL[i]}"
        done
    else
        echo
        echo "Goodbye..."
    fi
fi
echo