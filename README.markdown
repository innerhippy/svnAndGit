# GitAndSvn

## Intro

There are a number of git2svn scripts out there for converting svn repos into
git ones. These are mostly for one-time imports which is fine, but not very handy 
if you need to maintain both git and svn concurrently with bi-directional commits.
Hence the need for this project.

## Motivation

I joined a large company recently that has been using svn for donkey's years, and 
now it's my job to manage the development process - and the most obvious thing
go change is the SCM. So I need to prove to the company that Git it the way forward 
before they will consider making the switch. We've earmarked a project to use Git, but
we still need a mechanism to bridge the repos - Git commits need to appear in SVN and 
vica versa.

The repos we will use in the project are still under active development by other
departments in the company, so it is imperative that we maintain this bi-directional
workflow between SVN and Git.

I am also very keen to have my developers experience the full awesomeness of Git without
having to fart around using the git-svn commands. The rebase side-effects of git-svn means
that collaboration between team members will be impossible. I need them to see a standard 
Git repo for the project - the SVN synchronization should just happen automagically.

## Warning

I've been using Git for a few years without really understanding what it does under the
hood. Writing these scripts has made me understand much more about Git but I do not 
consider myself a Git expert by any means. If you see something in these scripts which
is wrong or plain stupid, then please let me know! I've tried my best to find existing
solutions for this scenario, but with no joy - so I'm doing it myself. In short: help!

## Architecture

	                                                             -------
	                                                       ---> | dev b |
	                                                      |      -------
	 ----------         ---------          ----------     |      -------
	| SVN repo | <---> | gateway | <----> | bare-git | <----->  | dev a |
	 ----------         ---------          ----------     |      -------
	                                                      |      -------
	                                                       ---> | dev c |
	                                                             -------

	SVN repo - the SVN bit
	gateway  - git repo created with git-svn.
	bare Git - standard git repo from which developers will push/pull
	dev x    - cloned developer Git repo

Don't you just love ascii art? Hmmmm...



## Requirements

- SVN repo contains the usual trunk/branches/tags layout which must be imported to Git
- the gateway pulls changes from SVN via cron (every hour, say) and pushes to bare-git
- new tags and branches imported from SVN must propagate to the bare-git repo
- Git commits from developers will trigger the post-update hook in bare-git that will
  do the following on the gateway:
     1. pull commits from bare-git
     2. merge these commits with anything new from svn
     3. publish new commits to SVN (dcommit)
     4. merge anything new from the SVN and push back to bare-git
  

## Issues

Ideally, we'd have a perfectly linear history between Git and SVN. This is not possible 
due to the rebase operations done by git-svn-rebase and git-svn-dcommit. So we maintain 
two branches in the gateway  master that tracks the bare-git repo, and svn that deals 
with svn imports/exports.

Changes from the master branch (ie commits from our developers) are rebased onto the svn 
branch before being committed and then dcommited to the svn repo. Changes from svn are 
just merged into the master branch. We still need to converge the branches are some 
stage, but we cannot do any rebases on the master branch as this would screw up the 
developers repos.

The developers will see the history diverging and converging for each dcommit - so they'll 
have access to all SVN commits as well as all Git commits, albeit without linear history. 
They may also git confused with the duplicate commits (one from Git and the other from 
SVN that includes the SVN commit-id) - but they'll just have to understand that this hybrid 
system is not perfect.


## Usage

There are 3 shell scripts, gitImportSvn.sh that creates the initial import, gitSvnSyncer.sh that
sync the 2 sides (called as a post-update hook from bare-git and also from a cron to regularly 
import SVN changes), and gitSvnUtils.sh which contains a bunch of shared functions.

Create the gateway and bare-git repos using the gitImportSvn.sh script.
Developers will clone the bare-git repo and commit as usual.

When pushing their changes, they must activate the syncer by setting the environment variable 
GIT_SYNC=1


## Example

	./gitImportSvn --snv file:///my_svn_project --bare /opt/git/my_git_project.git --gateway /opt/gateway/my_gateway/

The --install switch can also be used to specify the path in the post-update hook where the 
gitSvnSyncer.sh will reside. If omitted, it uses the current location of the gitImportSvn.sh script.

The developer will clone the bare-git

	$ git clone /opt/git/my_git_project.git
	$ cd /my_git_project
	
	hack...
	hack...
	hack...

	$ git commit ....
	
	$ GIT_SYNC=1 git push
	

If GIT_SYNC is not set then the SVN repo will NOT be synchronised (unsurprisingly..) 


## Warning

This has not yet been tested in production and has been written to suite my own workflow! Please comment/contribute -
hopefully this will be of use to someone else.


## Thanks

Parts of the script where shamlessly ripped from http://github.com/nothingmuch/git-svn-abandon.git
Thanks to Yuval Kogman for this great work.

