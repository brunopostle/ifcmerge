# IFC Merge

*Collaborative BIM*

*ifcmerge* is a three-way-merge tool for IFC files, intended to support a
modern *fork, branch, pull-request and merge* workflow using revision control
systems such as git or mercurial.  This enables multiple people to work on
separate copies of the same IFC data, periodically merging their work.

This tool requires that a *Native IFC* application is used for all authoring
and editing.  A Native IFC application behaves in the following ways when
editing a pre-existing file:

* IFC entities *must* be written in the same format as received, with the same
  numeric ids as before.

* Attribute changes to entities *must* be written in-place.

* Numeric ids of deleted entities *must not* be reused.

If you use a traditional BIM application that saves in a proprietary format,
and that can then import/export IFC files, you probably do not have a *Native
IFC* application :(

## Quickstart

Configure git to use ifcmerge for the current repository:

    git config mergetool.ifcmerge.cmd '/path/to/ifcmerge $BASE $LOCAL $REMOTE $MERGED'

Create a branch, edit and commit some changes to an IFC file:

    git branch my_branch
    git switch my_branch
      [some editing of the IFC file]
    git commit test_model.ifc

Switch back to the previous branch and try to merge the new branch:

    git switch main
      [some editing of the IFC file]
    git commit test_model.ifc
    git merge my_branch

This will fail because there are *always* conflicts between two versions of the
same IFC file.  Try and resolve the conflict using ifcmerge:

    git mergetool --tool=ifcmerge

Commit the merge if it is successful:

    git commit -i test_model.ifc

You can always abandon the merge:

    git merge --abort

If your repository only contains IFC files, you can set git to always use
ifcmerge when merging:

    git config merge.tool ifcmerge

## About

Copyright 2022, Bruno Postle <bruno@postle.net>
License: GPLv3
