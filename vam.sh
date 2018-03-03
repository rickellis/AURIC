#!/bin/bash
aurdir="$HOME/AUR"
mkdir -p "$aurdir"

download() {
  local packages
  local depends
  packages=$(pacman -Sl)
  cd "$aurdir" || exit
  for arg in "$@"; do
    depends=$(curl -sg "https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$arg")
    if [[ $(echo "$depends" | jshon -e results) != "[]" ]]; then
      git clone https://aur.archlinux.org/"$arg".git 2> /dev/null
      echo ":: $arg downloaded $aurdir/$arg"
      if [[ $(echo "$depends" | jshon -e results -e 0 -e Depends) != "[]" ]]; then
        depends=$(echo "$depends" | jshon -e results -e 0 -e Depends -a -u)
        for dep in $depends; do
          echo "$packages" | grep "$dep" > /dev/null
          if [[ "$?" == 1 ]]; then
            download "$dep"
          fi
        done
      fi
    fi
  done
}

update() {
  cd "$aurdir" || exit
  for dir in ./*; do
    cd "$dir" || exit
    if [[ $(git pull 2> /dev/null) != "Already up to date." ]]; then
      echo ":: $dir needs to be reinstalled in $aurdir/$dir"
    fi
    cd ..
  done
}

search() {
  curl -s "https://aur.archlinux.org/rpc/?v=5&type=search&arg=$1" \
           | jshon -e results -a -e Name -u
}

if [[ "$1" == "-d" ]]; then
  echo "note: only folders in $aurdir get updated."
  shift
  download "$@"
elif [[ "$1" == "-u" ]]; then
  update
elif [[ "$1" == "-s" ]]; then
  shift
  search "$@"
else
  echo "vam aur helper: -d = download, -u = update, -s = search"
fi