#!/bin/sh

#####################################################################
#
# Just a bunch of functions used by the importer and syncer
#
#####################################################################

function import_branches() {

	# create local branches out of svn branches
	git for-each-ref --format='%(refname)' refs/remotes/svn/ | while read branch_ref; do
		branch=${branch_ref#refs/remotes/svn/}
		test $branch = "trunk" && continue

		# check branch doesn't already exist
		git branch -l | grep -q $branch && continue
		git branch "$branch" "$branch_ref"
		git update-ref -d "$branch_ref"
	done
}

#
# This was taken from Yuval Kogman's excellent http://github.com/nothingmuch/git-svn-abandon.git
#
function import_tags(){

	# tags from svn appear as branches - make them into, erm, tags
	git for-each-ref --format='%(refname)' refs/remotes/svn/tags/* | while read tag_ref; do
		tag=${tag_ref#refs/remotes/svn/tags/}
		tree=$( git rev-parse "$tag_ref": )

		# find the oldest ancestor for which the tree is the same
		parent_ref="$tag_ref"
		while [ "$( git rev-parse --quiet --verify "$parent_ref"^: )" = "$tree" ]; do
			parent_ref="$parent_ref"^
		done	
		parent=$( git rev-parse "$parent_ref" )

		# if this ancestor is in trunk then we can just tag it otherwise the
		# tag has diverged from trunk and it's actually more like a branch than a tag
		merge=$( git merge-base "refs/remotes/svn/trunk" $parent )
		if [ "$merge" = "$parent" ]; then
			target_ref=$parent
		else
			echo "tag has diverged: $tag"
			target_ref="$tag_ref"
		fi

		# create an annotated tag based on the last commit in the tag, and delete the "branchy" ref for the tag
		git show -s --pretty='format:%s%n%n%b' "$tag_ref" | \
			perl -ne 'next if /^git-svn-id:/; $s++, next if /^\s*r\d+\@.*:.*\|/; s/^ // if $s; print' | \
			env GIT_COMMITTER_NAME="$(  git show -s --pretty='format:%an' "$tag_ref" )" \
			GIT_COMMITTER_EMAIL="$( git show -s --pretty='format:%ae' "$tag_ref" )" \
			GIT_COMMITTER_DATE="$(  git show -s --pretty='format:%ad' "$tag_ref" )" \
			git tag -a -F - "$tag" "$target_ref"

		git update-ref -d "$tag_ref"
	done
}


