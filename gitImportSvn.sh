#!/bin/sh

#########################################################################
#
# Script to create git repositories from an existing SVN repo
#
###########################################################################

source $(dirname $0)/gitSvnUtils.sh
SYNC_SCRIPT="gitSvnSyncer.sh"
AUTHORS_FILE="/tmp/authors.map"

function usage() {

	[ -n "$1" ] && echo -e "\nError: $1\n"

	echo -e "usage: $(basename $0) <args>\n"
	echo -e "\t--svn, -s       URL for svn repo"
	echo -e "\t--bare, -b      path for bare git repo"
	echo -e "\t--gateway, -g   path for git gateway repo"
	echo -e "\t--install, -i   path of where $SYNC_SCRIPT script will be installed"
	exit 1  

}	

while [ $# -gt 0 ]; do
	case "$1" in
	--svn|-s)     shift; SVN_URL=$1;;
	--bare|-b)    shift; GIT_REPO=$1;;
	--gateway|-g) shift; GATEWAY_REPO=$1;;
	--install|-i) shift; SYNC_PATH=$1;;
	*) usage;;
	esac
	shift
done

[ -z "$SVN_URL" ] && usage "no svn URL given"
[ -z "$GATEWAY_REPO" ] && usage "no gateway repo given"
[ -z "$GIT_REPO" ] && usage "no git repo given"
[ -z "$SYNC_PATH" ] && SYNC_PATH=$(dirname $0)

SYNC_SCRIPT=${SYNC_PATH:-$(dirname $0)}/$SYNC_SCRIPT

function create_authors_file() {
	rm -f $AUTHORS_FILE
	svn log $SVN_URL -q | grep -e '^r' | awk 'BEGIN {FS = "|" };{ print $2 }' |sort -u | while read author; do
		author=${author%@*}
		if [ "$author" = "(no author)" ]; then 
			author="none"
		else
			name=$(finger "$author" 2>/dev/null| grep Name| sed 's/.*Name: //')
		fi
		echo "$author = ${name:-$author} <${author}@moving-picture.com>" >> $AUTHORS_FILE
	done
}

function add_authors_file(){
	if ! [ -f $(basename $AUTHORS_FILE ) ]; then
		mv $AUTHORS_FILE .
		git add $(basename $AUTHORS_FILE)
		git commit -m "Added authors file"
	fi
}

function compress_repo() {
	git reflog expire --all --expire=now
	git gc --aggressive
	git prune
	git fsck --full
}

function create_bare_git_repo(){

	git init --shared=all --bare $GIT_REPO
	git checkout master

	# Add remote master branch on remote as origin 
	git remote add -m master origin $GIT_REPO

	# Push all branches except svn, which is special
	git for-each-ref --format='%(refname)' refs/heads | while read branch; do
		[ $branch = "refs/heads/svn" ] && continue
		echo "Creating branch $branch on remote"
		git push origin $branch
	done

	git push origin --tags
	git branch --set-upstream master origin/master
	echo "Created git repo $GIT_REPO"
}

if test -d $GIT_REPO; then
	echo "Directory $GIT_REPO already exists"
	exit
fi

if test -d $GATEWAY_REPO; then
	echo "Directory $GATEWAY_REPO already exists"
	exit
fi

mkdir $GATEWAY_REPO
cd $GATEWAY_REPO

# Create a temp file to create default username. This is required
# or the fetch operation will fail. Dumb or what.
CREATE_AUTHORS=/tmp/create_author.sh
cat > $CREATE_AUTHORS << EOD
#!/bin/sh
echo 'Name <email>'
EOD
chmod u+x $CREATE_AUTHORS

git svn init --stdlayout --prefix=svn/ $SVN_URL || exit
create_authors_file
git svn fetch --authors-file=${AUTHORS_FILE} --authors-prog=${CREATE_AUTHORS} || exit
git update-ref -d master
import_tags
import_branches
add_authors_file
compress_repo
create_bare_git_repo
git branch --track svn svn/trunk

# Create the post-update script that triggers an svn sync each time a git pull is done from the client
cat > ${GIT_REPO}/hooks/post-update << EOD
$SYNC_SCRIPT $GATEWAY_REPO
EOD
chmod 0777 ${GIT_REPO}/hooks/post-update

echo done
