#!/usr/bin/env bash
#-----------------------------------------------------------------------------------
#                 _    
#   __ _ _  _ _ _(_)__ 
#  / _` | || | '_| / _|
#  \__,_|\_,_|_| |_\__|
#   AUR package manager
#
#-----------------------------------------------------------------------------------
VERSION="1.2.8"
#-----------------------------------------------------------------------------------
#
# AURIC is a fork of vam with a pretty interface, SRCINFO version comparison,
# package installation (with PKGBUILD auditing), dependency verification, 
# search keyword coloring, JSON parsing using either jq or jshon, and a 
# few additional features
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

# Whether to show the AURIC version number heading and clear
# screen with each request. Boolean: true or false
SHOW_HEADING=true

# ----------------------------------------------------------------------------------

# THESE GET SET AUTOMATICALLY

# Will contain the list of all installed packages.
LOCAL_PKGS=""

# Name of installed JSON parser. 
JSON_PARSER=""

# Whether a package is a dependency.
IS_DEPEND=false

# Flag gets set during migration to ignore dependencies since 
# these will already have been installed previously
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
    if [[ $1 == "error" ]]; then
        echo -e "${red}INVALID REQUEST. SHOWING HELP MENU${reset}"
    else
        echo -e "AURIC COMMANDS"
    fi
    echo 
    echo -e "auric -d  package-name\t# Download a package"
    echo
    echo -e "auric -i  package-name\t# Install a package if it has been downloaded."
    echo -e "\t\t\t# If local package does not exist it hands it off to auric -d"
    echo
    echo -e "auric -u  package-name\t# Update a package"
    echo -e "auric -u \t\t# Update all installed packages"
    echo
    echo -e "auric -s  package-name\t# Search for a package"
    echo
    echo -e "auric -q \t\t# Show all local packages managed by AURIC"
    echo
    echo -e "auric -vl package-name\t# Verify that all dependencies for a local package are installed"
    echo -e "auric -vr package-name\t# Verify that all dependencies for a remote package are installed"
    echo
    echo -e "auric -m  package-name \t# Migrate a specific package to AURIC"
    echo -e "auric -m \t\t# Migrate all previously installed AUR packages to AURIC"
    echo
    echo -e "auric -r  package-name\t# Remove a package"
    echo
    exit 1
}

# ----------------------------------------------------------------------------------

# Validate whether an argument was passed
validate_pkgname(){
    if [[ -z "$1" ]]; then
        echo -e "${red}Error: Package name required${reset}"
        echo
        echo -e "Enter ${cyan}auric --help${reset} for more info"
        echo
        exit 1
    fi
}

# ----------------------------------------------------------------------------------

# Download handler
download() {
    # Make sure we have a package name
    validate_pkgname "$1"

    # Perform the download
    do_download "$1"

    # Offer to install the downloaded package(s)
    offer_to_install
}

# ----------------------------------------------------------------------------------

# Download a package and its dependencies from AUR
do_download() {

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
                for depend in $dependencies; do

                    # Remove everything after >= in $depend
                    # Some dependencies have minimum version requirements
                    # which screws up the package name
                    depend=$(echo $depend | sed "s/>=.*//")

                    # See if the dependency is already installed
                    echo "$LOCAL_PKGS" | grep "$depend" > /dev/null

                    # Download it
                    if [[ "$?" == 1 ]]; then
                        IS_DEPEND=true
                        do_download "$depend"
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

    # If the package isn't currently managed by AURIC...
    if [[ ! -d ${AURDIR}/${PKG} ]]; then
        download $PKG
        return 0
    fi

    # Is the package installed on the system?...
    pacman -Q $PKG  >/dev/null 2>&1

    # Package is installed
    if [[ "$?" -eq 0 ]]; then
        echo -e "${red}ERROR: $PKG is already installed${reset}"
        echo
        exit 1
    fi

    read -p "Are you sure you want to install ${PKG} [Y/n]? " CONSENT
    if [[ ! -z $CONSENT ]] && [[ ! $CONSENT =~ [y|Y] ]]; then
        echo
        echo "Goodbye..."
    else
        do_install $PKG
    fi
    echo
}

# ----------------------------------------------------------------------------------

# This function gets called automatically after a new package is downloaded or
# when an update is available so the user can elect to install the package(s)
offer_to_install(){

    if [[ ${#TO_INSTALL[@]} -eq 0 ]]; then
        return 0
    fi

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
            do_install "${TO_INSTALL[i]}"
        done
    fi
    echo
}

# ----------------------------------------------------------------------------------

# Install a package
do_install() {
    # Make sure we have a package name
    validate_pkgname "$1"
    local PKG
    PKG=$1
    echo

    cd ${AURDIR}/${PKG}

    # Make sure the PKGBUILD script exists
    if [[ ! -f "${AURDIR}/${PKG}/PKGBUILD" ]]; then
        echo -e "${red}ERROR:${reset} PKGBUILD script does not exist in ${AURDIR}/${PKG}"
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
            do_update $DIR
            cd ..
        done
    else
        echo
        do_update $1
    fi
    echo

    # Offer to install the package updates
    offer_to_install
}

# ----------------------------------------------------------------------------------

# Perform the upddate routine
do_update() {
    local PKG
    PKG=$1

    if [[ ! -d ${AURDIR}/${PKG} ]]; then
        echo -e "${red}MISSING:${reset} ${PKG} is not a package in ${AURDIR}"
        echo
        exit 1
    fi

    if [[ ! -f ${AURDIR}/${PKG}/.SRCINFO ]]; then
        echo -e "${red}ERROR:${reset} .SRCINFO does not exist in ${AURDIR}/${PKG}"
        echo
        exit 1
    fi

    # Get the version number of the currently installed package.
    local_pkgver=$(pacman -Q $PKG)

    # No version number? Package isn't installed
    if [[ "$?" -ne 0 ]]; then
        echo -e "${red}ERROR:${reset} ${PKG} does not appper to be installed on your system"
        echo
        exit 1
    fi

    # Remove the package name, leaving only the version/release number
    local_pkgver=$(echo $local_pkgver | sed "s/${PKG} //")
    local_pkgver=$(echo $local_pkgver | sed "s/[ ]//")

    cd ${AURDIR}/${PKG} || exit
    git pull >/dev/null 2>&1

    # Open .SRCINFO and get the version/release numbers
    # for comparison with the installed version
    pkgver=$(sed -n 's/pkgver[ ]*=//p'  .SRCINFO)
    pkgrel=$(sed -n 's/pkgrel[ ]*=//p'  .SRCINFO)

    # Kill stray spaces
    pkgver=$(echo $pkgver | sed "s/[ ]//g")
    pkgrel=$(echo $pkgrel | sed "s/[ ]//g")

    # Combine pkgver and pkgrel into the new full version number for comparison
    if [[ ! -z $pkgrel ]]; then
        new_pkgver="${pkgver}-${pkgrel}"
    else
        new_pkgver="${pkgver}"
    fi

    if [[ $(vercmp $new_pkgver $local_pkgver) -eq 1 ]]; then
        echo -e "${green}NEW VER: ${PKG} ${pkgver} is available${reset}"
        echo -e "${yellow}PKG BLD: Build files have been downloaded. ${PKG} is ready to be reinstalled${reset}" 
        TO_INSTALL+=("$PKG")
    else
        echo -e "PACKAGE: ${PKG}"
        echo -e "${cyan}CURRENT: ${PKG} is up to date${reset}"
    fi
}

# ----------------------------------------------------------------------------------

# Verify that all dependencies for a remote AUR package are installed. 
verify_rdep() {
    validate_pkgname "$1"
    local PKG
    PKG=$1

    echo -e "VERIFYING DEPENDENCIES FOR ${cyan}${PKG}${reset}"
    echo

    # Verify whether the package is an AUR or official package
    curl_result=$(curl -fsSk "${AUR_INFO_URL}${PKG}")

    # Parse the result using the installed JSON parser
    if [[ $JSON_PARSER == 'jq' ]]; then
        json_result=$(echo "$curl_result" | jq -r '.results')
    else
        json_result=$(echo "$curl_result" | jshon -e results)
    fi

    # Did the package query return a valid result?
    if [[ $json_result == "[]" ]]; then
        echo -e "${red}ERROR: $PKG is not an AUR package${reset}"
        echo
        echo "This function only verifies dependencies for installed AUR packages"
        echo
        return 0
    fi

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
        for depend in $dependencies; do

            # Remove everything after >= in $depend
            # Some dependencies have minimum version requirements
            # which screws up the package name
            depend=$(echo $depend | sed "s/>=.*//")

            # Make sure the dependency is installed
            pacman -Q $depend  >/dev/null 2>&1

            if [[ "$?" -eq 0 ]]; then
                echo -e " ${green}INSTALLED:${reset} ${depend}"
            else
                echo -e " ${red}NOT INSTALLED:${reset} ${depend}"
            fi
        done
    else
        echo -e "${red}$PKG requires no dependencies${reset}"
    fi
    echo
}

# ----------------------------------------------------------------------------------

# Verify that all dependencies for a local AUR package are installed. This is a 
# helper function that is useful to run prior to installing any new updates
# in case a new package dependency was needed
verify_ldep() {
    validate_pkgname "$1"
    local depend
    local PKG
    PKG=$1

    # If the package isn't currently managed by AURIC...
    if [[ ! -d ${AURDIR}/${PKG} ]]; then

        # Is the package installed on the system?...
        pacman -Q $PKG  >/dev/null 2>&1

        if [[ "$?" -eq 0 ]]; then

            # Verify whether the package is an AUR or official package
            curl_result=$(curl -fsSk "${AUR_INFO_URL}${PKG}")

            # Parse the result using the installed JSON parser
            if [[ $JSON_PARSER == 'jq' ]]; then
                json_result=$(echo "$curl_result" | jq -r '.results')
            else
                json_result=$(echo "$curl_result" | jshon -e results)
            fi

            # Did the package query return a valid result?
            if [[ $json_result == "[]" ]]; then
                echo -e "${red}ERROR: $PKG is not an AUR package${reset}"
                echo
                echo "This function only verifies dependencies for installed AUR packages"
                echo
                exit 1
            else
                echo -e "${red}ERROR: $PKG is installed but not currently under AURIC management${reset}"
                echo
                echo -e "To migrate the package to AURIC run: ${cyan}auric -m${reset}"
                echo
                exit 1
            fi
        else
            echo -e "${red}ERROR: ${PKG} is not installed on your system${reset}"
            echo
            echo "This function only verifies dependencies for installed packages"
            echo
            exit 1
        fi
    fi

    if [[ ! -f ${AURDIR}/${PKG}/.SRCINFO ]]; then
        echo -e "${red}ERROR:${reset} .SRCINFO does not exist in ${AURDIR}/${PKG}"
        echo
        exit 1
    fi

    echo -e "VERIFYING DEPENDENCIES FOR ${cyan}${PKG}${reset}"
    echo

    # Preserve the old input field separator
    OLDIFS=$IFS
    # Change the input field separator from a space to a null
    IFS=$'\n'

    # Read the .SRCINFO file line by line
    for line in `cat ${AURDIR}/${PKG}/.SRCINFO `; do
        
        # Remove tabs and spaces
        line=$(echo $line | sed "s/[ \t]//g")

        # Ignore lines that don't list dependencies
        if [[ ${line:0:8} != "depends=" ]]; then
            continue
        fi

        # Remove "depends=" leaving only the package name
        depend=$(echo $line | sed "s/depends=//")

        # Remove everything after >= in $depend
        # Some dependencies have minimum version requirements
        # which screws up the package name
        depend=$(echo $depend | sed "s/>=.*//")        

        # Make sure the dependency is installed
        pacman -Q $depend  >/dev/null 2>&1

        if [[ "$?" -eq 0 ]]; then
            echo -e " ${green}INSTALLED:${reset} ${depend}"
        else
            echo -e " ${red}NOT INSTALLED:${reset} ${depend}"
        fi
    done

    # Restore input field separator
    IFS=$OLDIFS
    echo
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

    if [[ $json_result == "[]" ]] || [[ $json_result == null ]] || [[ -z $json_result ]]; then
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
    echo
}

# ----------------------------------------------------------------------------------

# Migrate all previously installed AUR packages to AURIC
migrate() {
    
    # No argument, migrate all installed packages
    if [[ -z "$1" ]]; then
        echo "MIGRATING INSTALLED AUR PACKAGES TO AURIC"
        echo
        IS_MIGRATING=true
        AURPKGS=$(pacman -Qm | awk '{print $1}')
        for PKG in $AURPKGS; do
            PKG=${PKG// /}
            download "$PKG"
        done
        IS_MIGRATING=false
        TO_INSTALL=()
        return 0
    fi

    local PKG
    PKG=$1

    # If the supplied package name is already managed by AURIC...
    if [[ -d ${AURDIR}/${PKG} ]]; then
        echo -e "${red}ERROR: ${PKG} has already been migrated${reset}"
        echo
        exit 1
    fi

    # Before migrating, let's make sure it's an installed AUR package
    pacman -Q $PKG  >/dev/null 2>&1

    # Package is installed
    if [[ "$?" -eq 0 ]]; then

        # Search for the package at AUR
        curl_result=$(curl -fsSk "${AUR_INFO_URL}${PKG}")

        # Parse the result using the installed JSON parser
        if [[ $JSON_PARSER == 'jq' ]]; then
            json_result=$(echo "$curl_result" | jq -r '.results')
        else
            json_result=$(echo "$curl_result" | jshon -e results)
        fi

        # Did the package query return a valid result?
        if [[ $json_result == "[]" ]]; then
            echo -e "${red}ERROR: $PKG is not an AUR package${reset}"
            echo
            echo "Only AUR packages can be migrated to AURIC"
            echo
            exit 1
        fi
    else
        echo -e "${red}ERROR: ${PKG} is not installed on your system${reset}"
        echo
        echo "Only installed AUR packages can be migrated"
        echo
        exit 1
    fi

    echo "MIGRATING $1 TO AURIC"
    echo
    IS_MIGRATING=true
    download "$1"
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
    echo
}

# ----------------------------------------------------------------------------------

# Remove both the local git repo and the package via pacman
remove() {
    cd "$AURDIR" || exit
    PKG=$1
    if [[ ! -d ${AURDIR}/${PKG} ]]; then
        echo -e "${red}ERROR:${reset} ${PKG} is not an installed package"
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
    echo
}

# ----------------------------------------------------------------------------------
#  BEGIN OUTPUT
# ----------------------------------------------------------------------------------

if [[ $SHOW_HEADING == true ]]; then
    clear
    heading purple "AURIC $VERSION"
else
    echo
fi

# ----------------------------------------------------------------------------------

# DEPENDENCY CHECKS

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

# ----------------------------------------------------------------------------------

# VALIDATE REQUEST

# No arguments, we show help
if [[ -z "$1" ]]; then
    help "error"
fi

CMD=$1          # first argument
CMD=${CMD,,}    # lowercase
CMD=${CMD//-/}  # remove dashes
CMD=${CMD// /}  # remove spaces

# Invalid arguments trigger help
if [[ $CMD =~ [^diusqrlmvh] ]]; then
    help "error"
fi

# Create the local AUR folder if it doesn't exist
if [[ ! -d "$AURDIR" ]]; then
    mkdir -p "$AURDIR"
fi

# ----------------------------------------------------------------------------------

# PROCESS REQUEST

shift
case "$CMD" in
    d)  download "$@" ;;
    i)  install "$@" ;;
    u)  update "$@" ;;
    s)  search "$@" ;;
    q)  query "$@" ;;
    r)  remove "$@" ;;
    m)  migrate "$@" ;;
    vl) verify_ldep "$@";;
    vr) verify_rdep "$@";;
    h)  help ;;
esac
