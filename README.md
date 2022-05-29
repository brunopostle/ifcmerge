# IFC Merge

*Collaborative BIM*

## Quickstart

Create a branch, edit and commit some changes to an IFC file:

    git branch my_branch
    git switch my_branch
    git commit project.ifc

Switch back to the previous branch and try and merge the new branch:

    git switch main
    git merge my_branch

This will fail if there have been any conflicting changes in the meantime,
configure git to use ifcmerge:

     git config mergetool.ifcmerge.cmd '/home/bruno/src/ifcmerge/ifcmerge $BASE $LOCAL $REMOTE $MERGED'

Try and resolve the conflict:

     git mergetool --tool=ifcmerge
     git commit -i project.ifc

You can always abandon the merge:

     git merge --abort

## About

Copyright 2022, Bruno Postle <bruno@postle.net>
License: GPLv3
