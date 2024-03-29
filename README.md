# IFC Merge

*Collaborative BIM*

*ifcmerge* is a three-way-merge tool for IFC files, intended to support a
modern *fork, branch, pull-request and merge* workflow using revision control
systems such as git or mercurial.  This enables multiple people to work on
separate copies of the same IFC data, periodically merging their work.

This tool requires that a *Native IFC* application, such as *BlenderBIM*, is
used for all authoring and editing.

A *Native IFC* application behaves in the following ways when editing a
pre-existing IFC (STEP/SPF) file:

1. IFC entities *must* be written in the same format as received, with the same
   numeric IDs as before.

2. Attribute changes to entities *must* be written in-place.

3. Numeric IDs of deleted entities *must not* be reused for new entities.

If you use a traditional BIM application that saves in a proprietary format,
and that exports IFC files, you probably do not have a *Native IFC*
application :(

This whitepaper shows why you might want to use *Native IFC* for your work:
https://github.com/brunopostle/ifcmerge/blob/main/docs/whitepaper.rst

This video presentation shows interactive use of ifcmerge in the BlenderBIM application:
https://peertube.linuxrocks.online/w/jotEqADodmuYz8J1Sku7B2

## Quickstart

Given a base IFC file and two different forked versions of it, combine the
changes from the two forks into a merged result like so:

    ifcmerge base.ifc local_fork.ifc remote_fork.ifc result_merged.ifc

## Using ifcmerge with git

Configure git to add *ifcmerge* to the list of available merge tools (set the
path to suit your installation location):

    git config --global mergetool.ifcmerge.cmd '/path/to/ifcmerge $BASE $LOCAL $REMOTE $MERGED'
    git config --global mergetool.ifcmerge.trustExitCode true

Assuming you already have a git repository containing `test_model.ifc`.  Create
a new branch, edit and commit some changes to the IFC file in this branch:

    git branch my_branch
    git switch my_branch
      [some editing of the IFC file]
    git commit test_model.ifc

(The procedure is similar with a remote pull request: create a temporary local
branch and use `git pull` to update it with the remote changes rather than
making those changes yourself)

Switch back to the original *main* branch where the IFC file remains
unmodified, edit and commit some different changes:

    git switch main
      [some editing of the IFC file]
    git commit test_model.ifc

At this point the two branches have diverged, instruct git to merge them:

    git merge my_branch

This will not complete, resulting in an unresolved conflict, because the
default git merge will *always* find conflicts between two versions of the same
IFC file.  Complete the merge by resolving the conflict using *ifcmerge*:

    git mergetool --tool=ifcmerge

Commit the merge if it is successful (i.e. with no error messages):

    git commit -i test_model.ifc

Otherwise, if *ifcmerge* refuses because it can't safely merge the branches,
such as when an entity has been modified in one branch and deleted in the
other, you can always abandon the merge:

    git merge --abort

If your repository only contains IFC files, you can set `git mergetool` to
default to using *ifcmerge*:

    git config merge.tool ifcmerge

## About

Copyright 2022, Bruno Postle <bruno@postle.net>
License: GPLv3
