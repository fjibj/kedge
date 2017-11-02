#!/usr/bin/env bash

# Constants. Enter relevant repo information here.
UPSTREAM_REPO="kedgeproject"
CLI="kedge"
GITPATH="$GOPATH/src/github.com/kedgeproject/kedge"

usage() {
  echo "This will prepare $CLI for release!"
  echo ""
  echo "Requirements:"
  echo " git"
  echo " hub"
  echo " github-release"
  echo " github_changelog_generator"
  echo " GITHUB_TOKEN in your env variable"
  echo " "
  echo "Not only that, but you must have permission for:"
  echo " Tagging releases within Github"
  echo ""
}

requirements() {

  if [ "$PWD" != "$GITPATH" ]; then
    echo "ERROR: Must be in the $GITPATH directory"
    exit 0
  fi

  if ! hash git 2>/dev/null; then
    echo "ERROR: No git."
    exit 0
  fi

  if ! hash github-release 2>/dev/null; then
    echo "ERROR: No $GOPATH/bin/github-release. Please run 'go get -v github.com/aktau/github-release'"
    exit 0
  fi

  if ! hash github_changelog_generator 2>/dev/null; then
    echo "ERROR: github_changelog_generator required to generate the change log. Please run 'gem install github_changelog_generator"
    exit 0
  fi

  if ! hash hub 2>/dev/null; then
    echo "ERROR: Hub needed in order to create the relevant PR's. Please install hub @ https://github.com/github/hub"
    exit 0
  fi

  if [[ -z "$GITHUB_TOKEN" ]]; then
    echo "ERROR: export GITHUB_TOKEN=yourtoken needed for using github-release"
    exit 0
  fi
}

# Make sure that upstream had been added to the repo 
init_sync() {
  CURRENT_ORIGIN=`git config --get remote.origin.url`
  CURRENT_UPSTREAM=`git config --get remote.upstream.url`
  ORIGIN="git@github.com:$ORIGIN_REPO/$CLI.git"
  UPSTREAM="git@github.com:$UPSTREAM_REPO/$CLI.git"

  if [ $CURRENT_ORIGIN != $ORIGIN ]; then
    echo "Origin repo must be set to $ORIGIN"
    exit 0
  fi

  if [ $CURRENT_UPSTREAM != $UPSTREAM ]; then
    echo "Upstream repo must be set to $UPSTREAM"
    exit 0
  fi

  git checkout master
  git fetch upstream
  git merge upstream/master
  git checkout -b release-$1
}

replaceversion() {
  echo "Replaced version in version.go"
  sed -i "s/$1/$2/g" cmd/version.go

  echo "Replaced version in README.md"
  sed -i "s/$1/$2/g" README.md

  echo "Replaced version in docs/installation.md"
  sed -i "s/$1/$2/g" docs/installation.md

  echo "Replaced version in docs/introduction.md"
  sed -i "s/$1/$2/g" docs/introduction.md

  echo "Replaced version in build/VERSION"
  sed -i "s/$1/$2/g" build/VERSION
}

changelog() {
  echo "Generating changelog using github-changelog-generator"
  github_changelog_generator $UPSTREAM_REPO/$CLI -t $GITHUB_TOKEN --future-release v$1
}

changelog_github() {
  touch changes.txt
  echo "Write your GitHub changelog here" >> changes.txt
  $EDITOR changes.txt
}

build_binaries() {
  make cross
}

create_tarballs() {
  # cd into the bin directory so we don't have '/bin' inside the tarball
  cd bin
  for f in *
  do
    tar cvzf $f.tar.gz $f
  done
  cd ..
}

git_commit() {
  BRANCH=`git symbolic-ref --short HEAD`
  if [ -z "$BRANCH" ]; then
    echo "Unable to get branch name, is this even a git repo?"
    return 1
  fi
  echo "Branch: " $BRANCH

  git add .
  git commit -m "$1 Release"
  git push origin $BRANCH
  hub pull-request -b $UPSTREAM_REPO/$CLI:master -h $ORIGIN_REPO/$CLI:$BRANCH

  echo ""
  echo "PR opened against master to update version"
  echo "MERGE THIS BEFORE CONTINUING"
  echo ""
}

git_pull() {
  git pull
}


git_sync() {
  git fetch upstream master
  git rebase upstream/master
}

git_tag() {
  git tag v$1
}

generate_install_guide() {
  echo "
# Installation

__Linux and macOS:__

\`\`\`sh
# Linux
curl -L https://github.com/kedgeproject/kedge/releases/download/v$1/kedge-linux-amd64 -o kedge

# macOS
curl -L https://github.com/kedgeproject/kedge/releases/download/v$1/kedge-darwin-amd64 -o kedge

chmod +x kedge
sudo mv ./kedge /usr/local/bin/kedge
\`\`\`

__Windows:__

Download from [GitHub](https://github.com/kedgeproject/kedge/releases/download/v$1/kedge-windows-amd64.exe) and add the binary to your PATH.

__Checksums:__

| Filename        | SHA256 Hash |
| ------------- |:-------------:|" > install_guide.txt

  for f in bin/*
  do
    HASH=`sha256sum $f | head -n1 | awk '{print $1;}'`
    NAME=`echo $f | sed "s,bin/,,g"`
    echo "[$NAME](https://github.com/kedgeproject/kedge/releases/download/v$1/$NAME) | $HASH" >> install_guide.txt
  done

 # Append the file to the file
 cat install_guide.txt >> changes.txt
}

push() {
  CHANGES=$(cat changes.txt)
  # Release it!

  echo "Creating GitHub tag"
  github-release release \
      --user $UPSTREAM_REPO \
      --repo $CLI \
      --tag v$1 \
      --name "v$1" \
      --description "$CHANGES"
  if [ $? -eq 0 ]; then
        echo UPLOAD OK 
  else 
        echo UPLOAD FAIL
        exit
  fi

  # Upload all the binaries and tarballs generated in bin/
  for f in bin/*
  do
    echo "Uploading file $f"
    NAME=`echo $f | sed "s,bin/,,g"`
    github-release upload \
        --user $UPSTREAM_REPO \
        --repo $CLI \
        --tag v$1 \
        --file $f \
        --name $NAME
    if [ $? -eq 0 ]; then
          echo UPLOAD OK 
    else 
          echo UPLOAD FAIL
          exit
    fi
  done

  echo "DONE"
  echo "DOUBLE CHECK IT:"
  echo "!!!"
  echo "https://github.com/$UPSTREAM_REPO/$CLI/releases/edit/$1"
  echo "!!!"
}

clean() {
  rm changes.txt install_guide.txt
}

main() {
  local cmd=$1
  usage

  requirements

  echo "What is your Github username? (location of your $CLI fork)"
  read ORIGIN_REPO 
  echo "You entered: $ORIGIN_REPO"
  echo ""
  
  echo ""
  echo "First, please enter the version of the NEW release: "
  read VERSION
  echo "You entered: $VERSION"
  echo ""

  echo ""
  echo "Second, please enter the version of the LAST release: "
  read PREV_VERSION
  echo "You entered: $PREV_VERSION"
  echo ""

  clear

  echo "Now! It's time to go through each step of releasing $CLI!"
  echo "If one of these steps fails / does not work, simply re-run ./release.sh"
  echo "Re-enter the information at the beginning and continue on the failed step"
  echo ""

  PS3='Please enter your choice: '
  options=(
  "Initial sync with upstream"
  "Replace version number"
  "Generate changelog"
  "Generate GitHub changelog"
  "Create PR"
  "Sync with upstream"
  "Create tag"
  "Build binaries"
  "Create tarballs"
  "Generate install guide"
  "Upload the binaries and push to GitHub release page"
  "Clean"
  "Quit")
  select opt in "${options[@]}"
  do
      echo ""
      case $opt in
          "Initial sync with upstream")
              init_sync $VERSION
              ;;
          "Replace version number")
              replaceversion $PREV_VERSION $VERSION
              ;;
          "Generate changelog")
              changelog $VERSION
              ;;
          "Generate GitHub changelog")
              changelog_github $VERSION
              ;;
          "Create PR")
              git_commit $VERSION
              ;;
          "Sync with upstream")
              git_sync
              ;;
          "Create tag")
              git_tag $VERSION
              ;;
          "Build binaries")
              build_binaries
              ;;
          "Create tarballs")
              create_tarballs
              ;;
          "Generate install guide")
              generate_install_guide $VERSION
              ;;
          "Upload the binaries and push to GitHub release page")
              push $VERSION
              ;;
          "Clean")
              clean $VERSION
              ;;
          "Quit")
              clear
              break
              ;;
          *) echo invalid option;;
      esac
      echo ""
  done
}

main "$@"