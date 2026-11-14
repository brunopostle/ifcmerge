#!/usr/bin/perl

# Regression tests for lists of step IDs changed differently in local and
# remote. Only lists known to be unordered sets with add/remove semantics are
# merged by combining both sides' changes. Ordered lists, and sets that are
# edited by replacing members, are reported as conflicts.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

my $test_dir = tempdir(CLEANUP => 1);

# #1-#9 are spare entities that lists can refer to, #10 is the entity under test
sub write_ifc {
    my ($name, $record) = @_;
    open my $fh, '>', "$test_dir/$name" or die "cannot write $name: $!";
    print $fh "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION((''),'2;1');\nFILE_NAME('','',(''),(''),'','','');\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";
    print $fh "#$_=IFCCARTESIANPOINT(($_.,0.));\n" for 1 .. 9;
    print $fh "#10=$record;\n";
    print $fh "ENDSEC;\nEND-ISO-10303-21;\n";
    close $fh;
}

sub run_merge {
    my ($flag) = @_;
    my $merged = "$test_dir/merged.ifc";
    unlink $merged;
    my $output = `$ifcmerge $flag $test_dir/base.ifc $test_dir/local.ifc $test_dir/remote.ifc $merged 2>&1`;
    my $record;
    if (open my $fh, '<', $merged) {
        ($record) = grep { /^#10=/ } <$fh>;
        close $fh;
    }
    return { exit_code => $? >> 8, output => $output, record => $record, written => -f $merged };
}

sub conflicts {
    my ($output) = @_;
    my ($json) = $output =~ /(\{.*\})/s;
    return [] unless $json;
    return decode_json($json)->{conflicts} || [];
}

# The template has a single %s for the list attribute
sub merge_list {
    my ($template, $base, $local, $remote, $flag) = @_;
    write_ifc('base.ifc', sprintf($template, $base));
    write_ifc('local.ifc', sprintf($template, $local));
    write_ifc('remote.ifc', sprintf($template, $remote));
    return run_merge($flag // '');
}

# ============================================================================
# Ordered lists and replace-semantics sets changed on both sides conflict
# ============================================================================

my @conflicting = (
    ['IfcPolyline points', "IFCPOLYLINE(%s)", 1],
    ['IfcMaterialLayerSet layers', "IFCMATERIALLAYERSET(%s,'Wall',\$)", 1],
    ['IfcRelNests related objects', "IFCRELNESTS('0abc',\$,\$,\$,#9,%s)", 6],
    ['IfcCompositeCurve segments', "IFCCOMPOSITECURVE(%s,.F.)", 1],
    ['IfcShapeRepresentation items', "IFCSHAPEREPRESENTATION(#9,'Body','Tessellation',%s)", 4],
    ['IfcProductDefinitionShape representations', "IFCPRODUCTDEFINITIONSHAPE(\$,\$,%s)", 3],
    ['IfcUnitAssignment units', "IFCUNITASSIGNMENT(%s)", 1],
    ['IfcWallType representation maps', "IFCWALLTYPE('0abc',\$,\$,\$,\$,\$,%s,\$,\$,.STANDARD.)", 7],
);

for my $case (@conflicting) {
    my ($desc, $template, $index) = @$case;
    # local appends a member, remote replaces the second member
    for my $flag ('', '--prioritise-local') {
        my $label = ($flag || 'default') . ", $desc";
        my $result = merge_list($template, '(#1,#2,#3)', '(#1,#2,#3,#4)', '(#1,#5,#3)', $flag);
        is($result->{exit_code}, 1, "Merge fails ($label)");
        ok(!$result->{written}, "No merged file is written ($label)");
        my ($conflict) = grep { $_->{entity_id} == 10 } @{conflicts($result->{output})};
        ok($conflict, "Conflict is reported ($label)");
        is($conflict->{type}, 'attribute_conflict', "Conflict type is attribute_conflict ($label)");
        is($conflict->{attribute_index}, $index, "Conflict is on attribute $index ($label)");
        is($conflict->{selected_value}, $flag ? '(#1,#2,#3,#4)' : '(#1,#5,#3)',
           "Selected value follows priority ($label)");
    }
}

# Changed on one side only still merges cleanly
{
    my $result = merge_list("IFCPOLYLINE(%s)", '(#1,#2,#3)', '(#1,#2,#3,#4)', '(#1,#2,#3)');
    is($result->{exit_code}, 0, 'One-sided ordered list change merges');
    is($result->{record}, "#10=IFCPOLYLINE((#1,#2,#3,#4));\n", 'Local ordered list is kept');
}

# ============================================================================
# Unordered sets changed on both sides are merged
# ============================================================================

my @mergeable = (
    ['IfcRelAggregates related objects', "IFCRELAGGREGATES('0abc',\$,\$,\$,#9,%s)"],
    ['IfcRelContainedInSpatialStructure related elements', "IFCRELCONTAINEDINSPATIALSTRUCTURE('0abc',\$,\$,\$,%s,#9)"],
    ['IfcRelDefinesByType related objects', "IFCRELDEFINESBYTYPE('0abc',\$,\$,\$,%s,#9)"],
    ['IfcPropertySet properties', "IFCPROPERTYSET('0abc',\$,'Pset',\$,%s)"],
    ['IfcComplexProperty properties', "IFCCOMPLEXPROPERTY('P',\$,'U',%s)"],
    ['IfcElementQuantity quantities', "IFCELEMENTQUANTITY('0abc',\$,'Qto',\$,\$,%s)"],
    ['IfcWallType property sets', "IFCWALLTYPE('0abc',\$,\$,\$,\$,%s,\$,\$,\$,.STANDARD.)"],
    ['IfcDoorStyle property sets', "IFCDOORSTYLE('0abc',\$,\$,\$,\$,%s,\$,\$,.SINGLE_SWING_LEFT.,.WOOD.,.F.,.F.)"],
    ['IfcPresentationLayerAssignment assigned items', "IFCPRESENTATIONLAYERASSIGNMENT('Layer',\$,%s,\$)"],
    ['IfcExternalReferenceRelationship related resource objects', "IFCEXTERNALREFERENCERELATIONSHIP(\$,\$,#9,%s)"],
);

for my $case (@mergeable) {
    my ($desc, $template) = @$case;
    # local adds #4 and removes #1, remote adds #5 and removes #2
    my $result = merge_list($template, '(#1,#2,#3)', '(#2,#3,#4)', '(#1,#3,#5)');
    is($result->{exit_code}, 0, "Set merges ($desc)");
    is($result->{record}, '#10=' . sprintf($template, '(#3,#4,#5)') . ";\n",
       "Additions and removals from both sides are merged ($desc)");
}

done_testing();
