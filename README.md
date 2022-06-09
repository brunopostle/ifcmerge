# IFC Merge

*Collaborative BIM*

*ifcmerge* is a three-way-merge tool for IFC files, intended to support a
modern *fork, branch, pull-request and merge* workflow using revision control
systems such as git or mercurial.  This enables multiple people to work on
separate copies of the same IFC data, periodically merging their work.

This tool requires that a *Native IFC* application is used for all authoring
and editing.  A Native IFC application behaves in the following ways when
editing a pre-existing file:

* IFC entities *must* be written in the same format as received, in numeric
  order and with the same numeric ids as before.

* Attribute changes to entities *must* be written in-place.

* Numeric ids of deleted entities *must not* be reused.

* New entities *must* be appended to the end of the file.

If you use a traditional BIM application that saves in a proprietary format,
and that can import/export IFC files, you probably do not have a *Native IFC*
application :(

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
