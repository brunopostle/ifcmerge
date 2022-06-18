# IFC Merge

*Collaborative BIM*

*ifcmerge* is a three-way-merge tool for IFC files, intended to support a
modern *fork, branch, pull-request and merge* workflow using revision control
systems such as git or mercurial.  This enables multiple people to work on
separate copies of the same IFC data, periodically merging their work.

This tool requires that a *Native IFC* application, such as *BlenderBIM*, is
used for all authoring and editing.  A *Native IFC* application behaves in the
following ways when editing a pre-existing file:

* IFC entities *must* be written in the same format as received, with the same
  numeric IDs as before.

* Attribute changes to entities *must* be written in-place.

* Numeric IDs of deleted entities *must not* be reused for new entities.

If you use a traditional BIM application that saves in a proprietary format,
and that can export IFC files, you probably do not have a *Native IFC*
application :(

## Quickstart

Configure git to add *ifcmerge* to the list of optional merge tools (set the
path to suit your installation location):

    git config --global mergetool.ifcmerge.cmd '/path/to/ifcmerge $BASE $LOCAL $REMOTE $MERGED'

Assuming you have a git repository containing `test_model.ifc`, create a new
branch, edit and commit some changes to the IFC file in this branch:

    git branch my_branch
    git switch my_branch
      [some editing of the IFC file]
    git commit test_model.ifc

(The procedure is similar with a remote pull request: create a temporary local
branch and use `git pull` to update it with the remote changes rather than
committing those changes yourself)

Switch back to the original *main* branch where the IFC file is unmodified,
edit and commit some different changes:

    git switch main
      [some editing of the IFC file]
    git commit test_model.ifc

At this point the two branches have diverged, merge them like this:

    git merge my_branch

This will fail, leaving an unresolved conflict, because the default git merge
will *always* find conflicts between two versions of the same IFC file.
Resolve the conflict using ifcmerge:

    git mergetool --tool=ifcmerge

Commit the merge if it is successful (with no error messages):

    git commit -i test_model.ifc

If *ifcmerge* refuses because it can't safely merge the branches, such as when
an entity has been modified in one branch and deleted in the other, you can
always abandon the merge:

    git merge --abort

If your repository only contains IFC files, you can set `git mergetool` to
default to *ifcmerge*:

    git config merge.tool ifcmerge

## About

Copyright 2022, Bruno Postle <bruno@postle.net>
License: GPLv3
