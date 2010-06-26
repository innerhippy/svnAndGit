#!/bin/sh
###############################################################
#
# This script is called by a git post-update hook in order to 
# synchronise between git and SVN repositories.
#
# The main problem we have is that git-svn uses rebase operations 
# in order to maintain the commits between the two systems. Rebasing 
# will re-write the commit history because the commit messages returned 
# from SVN include the SVN commit ID in the message.
#  
# This would be fine for a single repo, but we are using a remote 'bare' repo as
# the authoratative git repo for developers, so we cannot screw up the commit
# history for this repo by propagating rebased commits.
#
# So, here's what we need to do in order to preserve the linear history for
# the remote repo. We have two branches, master - tracking the bare git repo 
#(as upstream) and an svn branch that handles all commits from the SVN server. 
# Commits from the bare repo are rebased onto the svn branch before being synched 
# with the SVN server. The resulting commit (from git svn dcommit) is then merged 
# in the master branch - effectively as a receipt from talking to SVN.
# 
# The git clients will still see duplicate commit messages - original git commits 
# and the altered SVN versions comtaining the svn commit ID. Can't see any way around 
# this. If all goes ok, the the user will just see 4 messages on stdout confirming 
# the process, the first will print the log file to which all operations will be 
# written. If anything goes wrong then this logfile will need to be inspected to 
# see what's happened. In this case, subsequent calls to this script will fail 
# immediately as a non-consistent state will have been detected.
#
#################################################################

source $(dirname $0)/gitSvnUtils.sh

GIT_GATEWAY=$1

# only sync if we have been explicitly told to do so
test "$GIT_SYNC" = 1 || exit

test "$GIT_VERBOSE" = 1 && OUT=/dev/stdout || OUT=/dev/null 

LOG=/tmp/gitsync_$(date +"%Y%m%d.%H%M%S").log
echo "-- writing to logfile: $LOG"

function run_git() {
	echo -e "\n============= running: git $* ==============" | tee -a $LOG > $OUT

	eval git $* 2>&1 | tee -a $LOG > $OUT
	if [ $PIPESTATUS != 0 ]; then
		echo -e "\n========= ERROR running git \"$*\" ========="
		exit $PIPESTATUS
	fi
}

log_error() {
	echo "========= ERROR: $* ========="
	exit 1
}

#
# First step - set to master branch and tag the heads for svn and master branches
# We'll need this for the rebase
#

test -d "$GIT_GATEWAY" || log_error "Cannot find SVN bridge repo \"$GIT_GATEWAY\""
export GIT_DIR=$GIT_GATEWAY/.git
cd $GIT_GATEWAY

git diff --quiet || log_error "repository in failed state - needs investigating..."
run_git checkout master
run_git tag -f tag_start HEAD
run_git tag -f tag_target svn

#
# Pull master branch only from origin/master. No branches, no tags - just
# master - it's complicated enough without having to sync git branches and tags
#
repo=$(basename $(git config remote.origin.url))

run_git fetch origin master:refs/remotes/origin/master --no-tags
num=$(git log --pretty=oneline HEAD..FETCH_HEAD | wc -l)
if [ $num -gt 0 ]; then
	echo -n "-- merging $num commits from $repo..."
	run_git merge origin/master
	echo ok
fi	

#
# Now the fun part -
# 1. rebase all changes from the pulled commits onto the svn branch
# 2. synchonise any changes from the SVN repo
# 3. push our local commits upstream to SVN
#

run_git checkout svn
run_git reset --hard master
run_git rebase --onto tag_target tag_start svn
run_git svn fetch --all 

num=$(git log --pretty=oneline HEAD..svn/trunk | wc -l)
test $num -gt 0 && echo "-- received $num commits from svn"

echo -n "-- syncing with svn repo..."
run_git svn rebase --local
import_tags
run_git svn dcommit
echo ok

#
# Merge back in the changes into the master branch, and push to the bare repo
#
echo -n "-- merging svn back into git master branch..."
run_git checkout master
run_git merge svn -m \"Integrating commits for SVN and git\"
run_git tag -d tag_start tag_target
echo ok

# Create local new branches from last svn fetch
import_branches
PULL_REQUIRED=0

# push out of date branches to remote
for branch in $(git for-each-ref --format='%(refname)' refs/heads); do
	test $branch = "refs/heads/svn" && continue  # don't want this one pushed

	git ls-remote --heads origin | cut -f1 | grep -q $(git show-ref --hash $branch) && continue

	echo -n "-- pushing branch \"${branch#refs/heads/}\" to remote $repo..."
	GIT_SYNC=0 run_git push origin $branch
	echo ok
	PULL_REQUIRED=1
done	

# show and push any new tags we've found
for tag in $(git tag -l); do
	if test $(git ls-remote --tags origin $tag | wc -l) = 0; then
		echo "-- found new tag \"$tag\""
		GIT_SYNC=0 run_git push origin --tags $tag
		PULL_REQUIRED=1
	fi
done

if test $PULL_REQUIRED = 1; then
	echo "-- success! Now run \"git pull\" to pickup svn changes"
else	
	echo "-- no changes detected"
	rm -rf $LOG
fi	
