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
# support, pacman for non-AUR dependency installation, JSON parsing using either jq 
# or jshon, and a few additional features
#
# The name AURIC is a play on two words: AUR and Rick. It also means gold.
#-----------------------------------------------------------------------------------
# Authors   :   Rick Ellis      https://github.com/rickellis/AURIC
#           :   Caleb Butler    https://github.com/calebabutler/vam        
# License   :   MIT
#-----------------------------------------------------------------------------------

# Local AUR git repo
AURDIR="$HOME/AUR"

# AUR package search URL
AURURL="https://aur.archlinux.org/rpc/?v=5&type=info&arg[]="

# Successful git pull result - no spaces or punctuation
GIT_RESULT="alreadyuptodate"

# Whether to resolve pacman dependencies during download.
# Makepkg does this so its unlikely this will need to be true
USE_PACMAN=false

# Will contain the list of all installed packages. 
# This gets set automatically
PACKAGES=""

# Name of installed JSON parser. This gets set automatically.
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

clear
heading purple "AURIC VERSION ${VERSION}"

# ----------------------------------------------------------------------------------

# Help screen
help() {
    echo "HELP MENU"
    echo 
    echo "Download a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -d${reset} ${cyn}package-name${reset}"
    echo
    echo "Install a downloaded package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -i${reset} ${cyn}package-name${reset}"
    echo
    echo "Update a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -u${reset} ${cyn}package-name${reset}"
    echo
    echo "Update all installed packages"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -u${reset}"
    echo
    echo "Search for a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -s${reset} ${cyn}package-name${reset}"
    echo
    echo "Show all local packages in ${AURDIR}"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -q${reset}"
    echo
    echo "Remove a package"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -r${reset} ${cyn}package-name${reset}"
    echo
    echo "Migrate previously installed packages to ${AURDIR}"
    echo
    echo -e "   ${yel}\$${reset}   ${grn}auric -m${reset}"
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
        echo -e "   ${yel}\$${reset}   ${grn}auric --help${reset}"
        echo
        exit 1
    fi
}

# ----------------------------------------------------------------------------------

# Download a package and its dependencies from AUR
download() {

    # Make sure we have a package name
    validate_pkgname "$1"

    local DEPENDENCIES

    # Get a list of all installed packages
    if [[ "${PACKAGES}" == "" ]]; then
        PACKAGES=$(pacman -Sl)
    fi

    # Move into the AUR folder
    cd "$AURDIR" || exit

    for ARG in $@; do

        # Fetch the JSON data associated with the submitted package name
        DEPENDENCIES=$(curl -fsSk "${AURURL}${ARG}")

        if [[ $JSON_PARSER == 'jq' ]]; then
            RESULTS=$(echo "$DEPENDENCIES" | jq -r '.results')
        else
            RESULTS=$(echo "$DEPENDENCIES" | jshon -e results)
        fi

        # Did the package query return a valid result?
        if [[ $RESULTS == "[]" ]]; then
            echo -e "${red}NOT AUR:${reset} ${ARG}"

            # makepkg takes care of all pacman dependencies
            # but if specified we do it here
            if [[ $USE_PACMAN == true ]]; then
                sudo pacman -S --noconfirm --needed ${ARG}
            fi
        else
    
            # If a folder with the package name exists we skip it
            if [[ -d "$ARG" ]]; then
                echo -e "${red}PKGSKIP:${reset} ${cyan}$ARG${reset} already exists in repo."
                continue
            fi

            echo -e "${yellow}CLONING:${reset} $ARG"

            git clone https://aur.archlinux.org/${ARG}.git 2> /dev/null

            if [[ "$?" -ne 0 ]]; then
                echo -e "${red}CLONE FAILED: GIT ERROR CODE ${?}${reset}"
                continue
            fi

            if [[ -d "$ARG" ]]; then
                echo -e "${green}SUCCESS:${reset} ${ARG} cloned"
            else
                echo -e "${red}ERROR: Unable to download $ARG${reset}"
                continue
            fi

            TO_INSTALL+=("$ARG")

            # Get the package dependencies
            if [[ $JSON_PARSER == 'jq' ]]; then
                HAS_DEPENDS=$(echo "$DEPENDENCIES" | jq -r '.results[0].Depends') 
            else
                HAS_DEPENDS=$(echo "$DEPENDENCIES" | jshon -e results -e 0 -e Depends)
            fi

            if [[ $HAS_DEPENDS != "[]" ]] && [[ $HAS_DEPENDS != null ]]; then

                if [[ $JSON_PARSER == 'jq' ]]; then
                    DEPENDS=$(echo "$DEPENDENCIES" | jq -r '.results[0].Depends[]') 
                else
                    DEPENDS=$(echo "$DEPENDENCIES" | jshon -e results -e 0 -e Depends -a -u)
                fi
        
                # Run through the dependencies
                for DEP in "${DEPENDS}"; do

                    # Remove everything after >= if the dependency name contains it
                    DEP=$(echo $DEP | sed "s/[>=].*//")
                    DEP=${DEP// /} # remove spaces just in case

                    # See if the dependency is already installed
                    echo "$PACKAGES" | grep "$DEP" > /dev/null

                    # Download it
                    if [[ "$?" == 1 ]]; then
                        download "$DEP"
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

    if [[ ! -f "${AURDIR}/${PKG}/PKGBUILD" ]]; then
        echo -e "${red}ERROR: PKGBUILD script does not exist in ${AURDIR}/${PKG}"
        echo
        exit 1
    fi

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
            RESULT=${RESULT// /} # remove spaces
            RESULT=${RESULT//./} # remove periods
            RESULT=${RESULT,,}   # lowercase

            if [[ $RESULT != "$GIT_RESULT" ]]; then
                echo -e "${red}NEW VER:${reset} ${cyan}${DIR:2}${reset} must be reinstalled"
            else
                echo -e "${green}CURRENT:${reset} ${DIR:2} is up to date"
            fi
            cd ..
        done
    else
        PKG=$1
        if [[ ! -d ${AURDIR}/${PKG} ]]; then
            echo -e "${red}NOT FOUND: ${PKG} is not in ${AURDIR}"
            echo
            exit 1
        fi

        echo -e "${yellow}PULLING:${reset} ${PKG}"
        
        cd ${AURDIR}/${PKG} || exit

        RESULT=$(git pull 2> /dev/null)
        RESULT=${RESULT// /} # remove spaces
        RESULT=${RESULT//./} # remove periods
        RESULT=${RESULT,,}   # lowercase

        if [[ $RESULT != "$GIT_RESULT" ]]; then
            echo -e "${red}NEW VER:${reset} ${cyan}${PKG}${reset} must be reinstalled"
        else
            echo -e "${green}CURRENT:${reset} ${PKG} is up to date"
        fi
        cd ..
    fi   
}

# ----------------------------------------------------------------------------------

search() {
    echo "Search not supported yet"
}

# ----------------------------------------------------------------------------------

# Migrate all previously installed AUR packages to AURIC
migrate() {

    echo "MIGRATING INSTALLED PACKAGES TO AURIC"

    LOCALPKGS=$(pacman -Qm | awk '{print $1}')
    for PKG in $LOCALPKGS; do
        PKG=${PKG// /}
        download "$PKG"
    done
    TO_INSTALL=()
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
    JSON_PARSER="jq"
elif command -v jshon &>/dev/null; then
    JSON_PARSER="jshon"
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
CMD=${CMD// /}  # remove spaces
CMD=${CMD//-/}  # remove dashes

# Help menu
if [[ $CMD =~ [h] ]] ; then
    help
fi

# Invalid arguments trigger help
if [[ $CMD =~ [^diusqrm] ]]; then
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
    *)  help ;;
esac


# If the TO_INSTALL array contains package names we offer to install
if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then

    read -p "Would you like to install the downloaded packages? [Y/n] " CONSENT

    if [[ $CONSENT =~ [y|Y] ]]; then
        echo
        for PKG in ${TO_INSTALL[@]}; do
            install $PKG
        done
    else
        echo
        echo "Goodbye..."
    fi
fi
echo