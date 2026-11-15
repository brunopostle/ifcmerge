#!/usr/bin/perl

# Regression tests for step IDs reused after deleting the last entities in a
# file. An application that loads such a file will allocate new IDs starting
# after the highest remaining ID, so new entities get the IDs of deleted base
# entities. These should be treated as deleted and added, not as modified.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

my $test_dir = tempdir(CLEANUP => 1);

sub write_ifc {
    my ($name, @records) = @_;
    open my $fh, '>', "$test_dir/$name" or die "cannot write $name: $!";
    print $fh "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION((''),'2;1');\nFILE_NAME('','',(''),(''),'','','');\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";
    print $fh "$_;\n" for @records;
    print $fh "ENDSEC;\nEND-ISO-10303-21;\n";
    close $fh;
}

sub run_merge {
    my ($flag) = @_;
    my $merged = "$test_dir/merged.ifc";
    unlink $merged;
    my $output = `$ifcmerge $flag $test_dir/base.ifc $test_dir/local.ifc $test_dir/remote.ifc $merged 2>&1`;
    my %records;
    if (open my $fh, '<', $merged) {
        for (<$fh>) { $records{$1} = $_ if /^(#[0-9]+)=/ }
        close $fh;
    }
    return { exit_code => $? >> 8, output => $output, records => \%records };
}

my $wall_a = "IFCWALL('0wallAAAAAAAAAAAAAAAAA',\$,'Wall A',\$,\$,#3,\$,\$,\$)";
my @base = (
    "#1=IFCCARTESIANPOINT((0.,0.,0.))",
    "#2=IFCAXIS2PLACEMENT3D(#1,\$,\$)",
    "#3=IFCLOCALPLACEMENT(\$,#2)",
    "#4=IFCCARTESIANPOINT((1.,0.,0.))",
    "#5=$wall_a",
);
my $moved = "#1=IFCCARTESIANPOINT((0.,0.,1.))";

# #4 and #5 deleted, then a new wall and placement created as #4 and #5
my $wall_b = "IFCWALL('1wallBBBBBBBBBBBBBBBBB',\$,'Wall B',\$,\$,#5,\$,\$,\$)";
my @reused = (@base[0 .. 2], "#4=$wall_b", "#5=IFCLOCALPLACEMENT(\$,#2)");

sub records_are {
    my ($result, $expected, $label) = @_;
    is($result->{exit_code}, 0, "Merge succeeds ($label)")
        or diag $result->{output};
    is_deeply([sort keys %{$result->{records}}], [sort keys %$expected], "Expected entities ($label)");
    for my $id (sort keys %$expected) {
        is($result->{records}{$id}, "$id=$expected->{$id};\n", "$id ($label)");
    }
}

# ============================================================================
# Reused IDs on one side are moved after the base IDs
# ============================================================================

for my $flag ('', '--prioritise-local') {
    my $label = $flag || 'default';
    my %expected = (
        '#1' => 'IFCCARTESIANPOINT((0.,0.,1.))',
        '#2' => 'IFCAXIS2PLACEMENT3D(#1,$,$)',
        '#3' => 'IFCLOCALPLACEMENT($,#2)',
        '#6' => "IFCWALL('1wallBBBBBBBBBBBBBBBBB',\$,'Wall B',\$,\$,#7,\$,\$,\$)",
        '#7' => 'IFCLOCALPLACEMENT($,#2)',
    );

    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', @reused);
    write_ifc('remote.ifc', $moved, @base[1 .. 4]);
    records_are(run_merge($flag), \%expected, "local reused IDs, $label");

    write_ifc('local.ifc', $moved, @base[1 .. 4]);
    write_ifc('remote.ifc', @reused);
    records_are(run_merge($flag), \%expected, "remote reused IDs, $label");
}

# ============================================================================
# Reused IDs combined with additions on the other side
# ============================================================================

{
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', @reused);
    write_ifc('remote.ifc', @base, "#6=IFCCARTESIANPOINT((5.,5.,5.))");
    records_are(run_merge(''), {
        '#1' => 'IFCCARTESIANPOINT((0.,0.,0.))',
        '#2' => 'IFCAXIS2PLACEMENT3D(#1,$,$)',
        '#3' => 'IFCLOCALPLACEMENT($,#2)',
        '#6' => 'IFCCARTESIANPOINT((5.,5.,5.))',
        '#7' => "IFCWALL('1wallBBBBBBBBBBBBBBBBB',\$,'Wall B',\$,\$,#8,\$,\$,\$)",
        '#8' => 'IFCLOCALPLACEMENT($,#2)',
    }, 'local reused IDs, remote additions');
    records_are(run_merge('--prioritise-local'), {
        '#1' => 'IFCCARTESIANPOINT((0.,0.,0.))',
        '#2' => 'IFCAXIS2PLACEMENT3D(#1,$,$)',
        '#3' => 'IFCLOCALPLACEMENT($,#2)',
        '#6' => "IFCWALL('1wallBBBBBBBBBBBBBBBBB',\$,'Wall B',\$,\$,#7,\$,\$,\$)",
        '#7' => 'IFCLOCALPLACEMENT($,#2)',
        '#8' => 'IFCCARTESIANPOINT((5.,5.,5.))',
    }, 'local reused IDs, remote additions, --prioritise-local');
}

# ============================================================================
# A replaced entity of the same class is detected by its GlobalId
# ============================================================================

{
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', @base[0 .. 3],
              "#5=IFCWALL('1wallBBBBBBBBBBBBBBBBB',\$,'Wall B',\$,\$,#6,\$,\$,\$)",
              "#6=IFCLOCALPLACEMENT(\$,#2)");
    write_ifc('remote.ifc', @base[0 .. 2], "#4=IFCCARTESIANPOINT((2.,0.,0.))", $base[4]);
    records_are(run_merge(''), {
        '#1' => 'IFCCARTESIANPOINT((0.,0.,0.))',
        '#2' => 'IFCAXIS2PLACEMENT3D(#1,$,$)',
        '#3' => 'IFCLOCALPLACEMENT($,#2)',
        '#4' => 'IFCCARTESIANPOINT((2.,0.,0.))',
        '#6' => "IFCWALL('1wallBBBBBBBBBBBBBBBBB',\$,'Wall B',\$,\$,#7,\$,\$,\$)",
        '#7' => 'IFCLOCALPLACEMENT($,#2)',
    }, 'replaced wall with new GlobalId');
}

# ============================================================================
# Conflicts with the deleted entities are still reported
# ============================================================================

{
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', @reused);
    (my $renamed = $wall_a) =~ s/Wall A/Wall C/;
    write_ifc('remote.ifc', @base[0 .. 3], "#5=$renamed");
    my $result = run_merge('');
    is($result->{exit_code}, 1, 'Modifying an entity deleted before ID reuse fails');
    like($result->{output}, qr/entity_deleted_and_modified/, 'entity_deleted_and_modified conflict is reported');
    unlike($result->{output}, qr/class_changed/, 'No class_changed conflict');
}

{
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', @reused);
    write_ifc('remote.ifc', @base, "#6=IFCPOLYLINE((#1,#4))");
    my $result = run_merge('');
    is($result->{exit_code}, 1, 'Referring to an entity deleted before ID reuse fails');
    like($result->{output}, qr/required_entity_deleted/, 'required_entity_deleted conflict is reported');
}

# ============================================================================
# Class changes that are not ID reuse still conflict
# ============================================================================

# IfcOpenShell reassign_class keeps the ID and GlobalId
{
    write_ifc('base.ifc', @base);
    (my $reassigned = $wall_a) =~ s/IFCWALL/IFCWALLSTANDARDCASE/;
    write_ifc('local.ifc', @base[0 .. 3], "#5=$reassigned");
    write_ifc('remote.ifc', $moved, @base[1 .. 4]);
    my $result = run_merge('');
    is($result->{exit_code}, 1, 'Class reassigned in place fails');
    like($result->{output}, qr/class_changed/, 'class_changed conflict is reported');
}

# An unchanged entity still refers to the ID, so it wasn't deleted
{
    my @base_ref = (@base[0 .. 3], "#5=IFCPOLYLINE((#1,#4))");
    write_ifc('base.ifc', @base_ref);
    write_ifc('local.ifc', @base_ref[0 .. 2], "#4=IFCDIRECTION((1.,0.,0.))", $base_ref[4]);
    write_ifc('remote.ifc', $moved, @base_ref[1 .. 4]);
    my $result = run_merge('');
    is($result->{exit_code}, 1, 'Class changed for a referenced entity fails');
    like($result->{output}, qr/class_changed/, 'class_changed conflict is reported');
}

done_testing();
