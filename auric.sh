#!/usr/bin/env bash
#-----------------------------------------------------------------------------------
#                 _    
#   __ _ _  _ _ _(_)__ 
#  / _` | || | '_| / _|
#  \__,_|\_,_|_| |_\__|
#   AUR package manager
#
#-----------------------------------------------------------------------------------
VERSION="1.0.0"
#-----------------------------------------------------------------------------------
#
# AURIC is mostly just vam with a pretty face, better error trapping, makepkg
# support, JSON parsing using either jq or jshon, and a few additional features
#
# The name AURIC is a play on two words: AUR and Rick. It also means gold.
#-----------------------------------------------------------------------------------
# Authors   :   Rick Ellis      https://github.com/rickellis/AURIC
#           :   Caleb Butler    https://github.com/calebabutler/vam        
# License   :   MIT
#-----------------------------------------------------------------------------------

# Local AUR git repo
AURDIR="$HOME/.AUR"

# AUR package search URL
AURURL="https://aur.archlinux.org/rpc/?v=5&type=info&arg[]="

# GIT URL for AUR repos. %s will be replaced with package name
GITURL="https://aur.archlinux.org/%s.git"

# Successful git pull result - no spaces or punctuation
GITRES="alreadyuptodate"

# Whether to resolve pacman dependencies during download.
# Makepkg does this so its unlikely this will need to be true
USEPAC=false

# Will contain the list of all installed packages. 
# This gets set automatically
LOCALPKGS=""

# Name of installed JSON parser. This gets set automatically.
JSONPARSER=""

# Array containg all successfully downloaded packages.
# If this contains package names AURIC will prompt
# user to install after downloading
TOINSTALL=()

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

clear
heading purple "AURIC VERSION ${VERSION}"

# ----------------------------------------------------------------------------------

# Help screen
help() {
    echo 
    echo "Download a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-d${reset} ${cyn}package-name${reset}"
    echo
    echo "Install a downloaded package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-i${reset} ${cyn}package-name${reset}"
    echo
    echo "Update a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-u${reset} ${cyn}package-name${reset}"
    echo
    echo "Update all installed packages"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-u${reset}"
    echo
    echo "Search for a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-s${reset} ${cyn}package-name${reset}"
    echo
    echo "Show all local packages in AURIC"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-q${reset}"
    echo
    echo "Remove a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-r${reset} ${cyn}package-name${reset}"
    echo
    echo "Migrate previously installed AUR packages to AURIC"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}-m${reset}"
    echo
    exit 1
}

# ----------------------------------------------------------------------------------

# Validate whether an argument was passed
validate_pkgname(){
    if [[ "$1" == false ]]; then
        echo -e "${red}Error: Package name required${reset}"
        echo
        echo "See help page:"
        echo
        echo -e "   ${yel}\$${reset}   ${grn}auric${reset} ${yellow}--help${reset}"
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
    if [[ "${LOCALPKGS}" == "" ]]; then
        LOCALPKGS=$(pacman -Sl)
    fi

    # Move into the AUR folder
    cd "$AURDIR" || exit

    for PKG in $@; do

        # Fetch the JSON data associated with the submitted package name
        curl_result=$(curl -fsSk "${AURURL}${PKG}")

        # Parse the result using the installed JSON parser
        if [[ $JSONPARSER == 'jq' ]]; then
            json_result=$(echo "$curl_result" | jq -r '.results')
        else
            json_result=$(echo "$curl_result" | jshon -e results)
        fi

        # Did the package query return a valid result?
        # If not it means the package is not in the AUR
        if [[ $json_result == "[]" ]]; then
            echo -e "${red}MISSING:${reset} ${PKG} not in AUR. Makepkg will install it via pacman if needed"
        else

            # If a folder with the package name exists in the local repo we skip it
            if [[ -d "$PKG" ]]; then
                echo -e "${red}PKGSKIP:${reset} ${cyan}${PKG}${reset} already exists in local repo"
                continue
            fi

            echo -e "${yellow}CLONING:${reset} $PKG"

            # Assemble the git package URL
            printf -v URL "$GITURL" "$PKG"

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
            TOINSTALL+=("$PKG")

            # Get the package dependencies using installed json parser
            if [[ $JSONPARSER == 'jq' ]]; then
                has_depends=$(echo "$curl_result" | jq -r '.results[0].Depends') 
            else
                has_depends=$(echo "$curl_result" | jshon -e results -e 0 -e Depends)
            fi

            # If there is a result, recurisvely call this function with the dependencies
            if [[ $has_depends != "[]" ]] && [[ $has_depends != null ]]; then

                if [[ $JSONPARSER == 'jq' ]]; then
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
                    depend=${depend// /} # remove spaces just in case

                    # See if the dependency is already installed
                    echo "$LOCALPKGS" | grep "$depend" > /dev/null

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

# Install a package
install() {
    # Make sure we have a package name
    validate_pkgname "$1"

    local PKG
    PKG=$1

    if [[ ! -d "${AURDIR}/${PKG}" ]]; then
        echo -e "${red}Error: Package does not exist${reset}"
        echo
        echo "See help page:"
        echo
        echo -e "   ${yel}\$${reset}   ${grn}auric --help${reset}"
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

    echo -e "Running makepkg on ${cyan}${PKG}${reset}"
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
        echo "UPDATING ALL PACKAES"
        echo
        for DIR in ./*; do
            cd "$DIR" || exit

            echo -e "${yellow}PULLING:${reset} ${DIR:2}"

            RESULT=$(git pull 2> /dev/null)
            RESULT=${RESULT//./} # remove periods
            RESULT=${RESULT//-/} # remove dashes
            RESULT=${RESULT// /} # remove spaces
            RESULT=${RESULT,,}   # lowercase

            if [[ $RESULT != "$GITRES" ]]; then
                echo -e "${red}NEW VER:${reset} ${cyan}${DIR:2}${reset} has been updated and must be reinstalled"

                # Add the package to the install array
                TOINSTALL+=("${DIR:2}")                
            else
                echo -e "${green}CURRENT:${reset} ${DIR:2} is up to date"
            fi
            cd ..
        done
    else
        PKG=$1
        if [[ ! -d ${AURDIR}/${PKG} ]]; then
            echo -e "${red}MISSING:${reset} ${PKG} is not in ${AURDIR}"
            echo
            exit 1
        fi

        echo -e "${yellow}PULLING:${reset} ${PKG}"
        
        cd ${AURDIR}/${PKG} || exit

        RESULT=$(git pull 2> /dev/null)
        RESULT=${RESULT//./} # remove periods
        RESULT=${RESULT//-/} # remove dashes
        RESULT=${RESULT// /} # remove spaces
        RESULT=${RESULT,,}   # lowercase

        if [[ $RESULT != "$GITRES" ]]; then
            echo -e "${red}NEW VER:${reset} ${cyan}${PKG}${reset} has been updated and must be reinstalled"

            # Add the package to the install array
            TOINSTALL+=("$PKG")    
        else
            echo -e "${green}CURRENT:${reset} ${PKG} is up to date"
        fi
        cd ..
    fi   
}

# ----------------------------------------------------------------------------------

search() {
  curl -s "https://aur.archlinux.org/rpc/?v=5&type=search&arg=$1" | jshon -a -e Name -u
}

# ----------------------------------------------------------------------------------

# Migrate all previously installed AUR packages to AURIC
migrate() {

    echo "MIGRATING INSTALLED AUR PACKAGES TO AURIC"

    AURPKGS=$(pacman -Qm | awk '{print $1}')
    for PKG in $AURPKGS; do
        PKG=${PKG// /}
        download "$PKG"
    done
    TOINSTALL=()
}

# ----------------------------------------------------------------------------------

# Show locally installed packages
query() {
    echo "The following packages are installed in ${AURDIR}"
    echo
    cd $AURDIR
    PKGS=$(ls)

    for P in $PKGS; do
        echo -e "    ${cyan}${P}${reset}"
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

    sudo pacman -Rsc $PKG
    rm -rf ${AURDIR}/${PKG}

    echo
    echo -e "${red}${PKG} has been removed${reset}"
}

# ----------------------------------------------------------------------------------

# Is jq or jshon installed? 
if command -v jq &>/dev/null; then
    JSONPARSER="jq"
elif command -v jshon &>/dev/null; then
    JSONPARSER="jshon"
else
    echo -e "${red}Error: No JSON parser installed${reset}"
    echo
    echo "This script requires either jq or jshon."
    echo
    exit 1
fi

# Is curl installed?
if ! command -v curl &>/dev/null; then
    echo -e "${red}Error: This script requires Curl${reset}"
    echo
    exit 1
fi

# No arguments, we show help
if [[ -z "$1" ]]; then
    help
fi

CMD=$1          # first argument
CMD=${CMD,,}    # lowercase
CMD=${CMD//-/}  # remove dashes
CMD=${CMD// /}  # remove spaces

# Show help menu
if [[ $CMD =~ [h] ]] ; then
    echo -e "${yellow}HELP MENU${reset}"
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
   sv)  searchv "$@" ;;
    q)  query "$@" ;;
    r)  remove "$@" ;;
    m)  migrate "$@" ;;
    *)  help ;;
esac


# If the TOINSTALL array contains package names we offer to install them
if [[ ${#TOINSTALL[@]} -gt 0 ]]; then

    echo
    echo "Would you like to install the packages you downloaded?" 
    echo
    for PKG in ${TOINSTALL[@]}; do
        echo -e "  ${cyan}${PKG}${reset}"
    done
    echo
    read -p "ENTER [Y/n] " CONSENT

    if [[ $CONSENT =~ [y|Y] ]]; then
        echo

        # Run through the install array in reverse order.
        # This helps ensure that dependencies get installed first.
        # The order doesn't matter after updating, only downloading
        for (( i=${#TOINSTALL[@]}-1 ; i>=0 ; i-- )) ; do
            install "${TOINSTALL[i]}"
        done

    else
        echo
        echo "Goodbye..."
    fi
fi
echo