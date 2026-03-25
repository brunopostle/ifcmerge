# IFC Merge

*Collaborative BIM*

*ifcmerge* is a three-way-merge tool for IFC files, intended to support a
modern *fork, branch, pull-request and merge* workflow using revision control
systems such as git or mercurial.  This enables multiple people to work on
separate copies of the same IFC data, periodically merging their work.

This tool requires that a *Native IFC* application, such as *BonsaiBIM*, is
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

This video presentation shows interactive use of ifcmerge in the BonsaiBIM application:
https://peertube.linuxrocks.online/w/jotEqADodmuYz8J1Sku7B2

## Quickstart

Given a base IFC file and two different forked versions of it, combine the
changes from the two forks into a merged result like so:

    ifcmerge base.ifc local_fork.ifc remote_fork.ifc result_merged.ifc

### Command Line Options

By default, ifcmerge prioritises the remote fork when renumbering entity IDs
and resolving conflicts. You can reverse this behavior:

    ifcmerge --prioritise-local base.ifc local_fork.ifc remote_fork.ifc result_merged.ifc

**`--prioritise-local`**: Preserves local entity IDs and renumbers remote IDs when
there are conflicts. Also affects which values are selected during conflict
resolution (though conflicts still cause the merge to fail).

### Error Reporting

When conflicts are detected, ifcmerge outputs structured JSON error reports:

```json
{
  "status": "failed",
  "message": "Merge failed due to conflicts",
  "conflicts": [
    {
      "type": "attribute_conflict",
      "entity_id": 748,
      "entity_class": "IFCWINDOW",
      "attribute_index": 3,
      "message": "Attribute conflict in both local and remote (prioritising remote)",
      "base_value": "'Window-1'",
      "local_value": "'Window-Local'",
      "remote_value": "'Window-Remote'",
      "selected_value": "'Window-Remote'"
    }
  ]
}
```

This JSON output makes it easier to integrate ifcmerge with automated tools and
provides detailed information about what conflicts occurred and where.

### Automatic Conflict Resolution

Some conflicts that previously required manual intervention are now resolved
automatically:

- **IfcLocalPlacement conflicts**: When both forks modify object placements,
  ifcmerge automatically selects one based on the priority setting (remote by
  default, or local with `--prioritise-local`)

Other conflicts (attribute modifications, entity deletions, etc.) still cause
the merge to fail and require manual resolution.

## Using ifcmerge with git

Configure git to add *ifcmerge* to the list of available merge tools (set the
path to suit your installation location):

    git config --global mergetool.ifcmerge.cmd '/path/to/ifcmerge $BASE $LOCAL $REMOTE $MERGED'
    git config --global mergetool.ifcmerge.trustExitCode true

A second tool, *ifcmerge-forward*, uses `--prioritise-local` so that the
local (checked-out) branch takes priority.  BonsaiBIM configures both tools
automatically, but you can add them manually:

    git config --global mergetool.ifcmerge-forward.cmd '/path/to/ifcmerge --prioritise-local $BASE $LOCAL $REMOTE $MERGED'
    git config --global mergetool.ifcmerge-forward.trustExitCode true

The reason two tools are needed is that when step-IDs are renumbered to
resolve overlapping additions, they should always be renumbered in the
temporary branch, never in *main* or *master*.  The choice of tool depends on
which branch you have checked out:

- **On a working branch, merging from main/master/origin**: use *ifcmerge*.
  The remote is main, so main's step-IDs are preserved and your branch's IDs
  are renumbered.

- **On main/master, merging in a temporary branch**: use *ifcmerge-forward*.
  The local branch is main, so main's step-IDs are preserved and the temporary
  branch's IDs are renumbered.

In both cases the invariant holds: step-IDs in main/master are never
rewritten.

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

Commit the merge if it is successful (i.e. ifcmerge exits 0 and reports no conflicts):

    git commit -i test_model.ifc

Otherwise, if *ifcmerge* refuses because it can't safely merge the branches,
such as when an entity has been modified in one branch and deleted in the
other, you can always abandon the merge:

    git merge --abort

If your repository only contains IFC files, you can set `git mergetool` to
default to using *ifcmerge*:

    git config merge.tool ifcmerge

## Installation with Windows

1. **Download `ifcmerge.exe`** from the [latest release](https://github.com/brunopostle/ifcmerge/releases/latest).

2. **Add to PATH** so that `ifcmerge` can be found by git and other tools:
   1. Create a directory such as `C:\Program Files\ifcmerge\` and place `ifcmerge.exe` there.
   2. Open **Environment Variables**: right-click `This PC` → `Properties` → `Advanced system settings` → `Environment Variables...`.
   3. Under `System Variables` (or `User Variables`), select `Path` and click `Edit...`.
   4. Click `New` and add `C:\Program Files\ifcmerge`.
   5. Click `OK` to save.

3. **Configure git** to use ifcmerge as a merge tool (in a Command Prompt or Git Bash):

       git config --global mergetool.ifcmerge.cmd 'ifcmerge "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'
       git config --global mergetool.ifcmerge.trustExitCode true
       git config --global mergetool.ifcmerge-forward.cmd 'ifcmerge --prioritise-local "$BASE" "$LOCAL" "$REMOTE" "$MERGED"'
       git config --global mergetool.ifcmerge-forward.trustExitCode true

   See [Using ifcmerge with git](#using-ifcmerge-with-git) for guidance on
   which tool to use depending on merge direction.  GUI git clients such as
   Sourcetree and TortoiseGit only support a single custom merge tool, so
   prefer the command-line git configuration above to get both.

## About

Copyright 2022, Bruno Postle <bruno@postle.net>
License: GPLv3
