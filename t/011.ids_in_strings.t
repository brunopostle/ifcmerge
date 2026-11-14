#!/usr/bin/perl

# Regression tests for text that looks like a step ID (#123) inside quoted
# strings. Renumbering must only change references, not string contents, and
# a string must not make an entity look like it requires a deleted entity.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

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

my @base = (
    "#1=IFCCARTESIANPOINT((0.,0.))",
    "#2=IFCCARTESIANPOINT((1.,0.))",
);

# ============================================================================
# Renumbered entities keep string contents unchanged
# ============================================================================

# Both sides add #3 and #4, so one side's additions are renumbered to #5 and #6
my $prop = "IFCPROPERTYSINGLEVALUE('Door #3',\$,IFCLABEL('see #2 and #4, it''s #3'),\$)";
my $rel = "IFCRELDEFINESBYPROPERTIES('0abc',\$,'Rel #4',\$,(#1),#4)";
my $pset = "IFCPROPERTYSET('0def',\$,'Pset #3',\$,(#3))";

{
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', @base, "#3=$prop", "#4=$pset");
    write_ifc('remote.ifc', @base, "#3=IFCCARTESIANPOINT((9.,9.))", "#4=IFCCARTESIANPOINT((8.,8.))");
    my $result = run_merge('');
    is($result->{exit_code}, 0, 'Merge with local renumbering succeeds');
    is($result->{records}{'#5'},
       "#5=IFCPROPERTYSINGLEVALUE('Door #3',\$,IFCLABEL('see #2 and #4, it''s #3'),\$);\n",
       'Strings in renumbered local entity are unchanged');
    is($result->{records}{'#6'}, "#6=IFCPROPERTYSET('0def',\$,'Pset #3',\$,(#5));\n",
       'References in renumbered local entity are renumbered, strings are not');
}

{
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', @base, "#3=IFCCARTESIANPOINT((9.,9.))", "#4=IFCCARTESIANPOINT((8.,8.))");
    write_ifc('remote.ifc', @base, "#3=$prop", "#4=$pset");
    my $result = run_merge('--prioritise-local');
    is($result->{exit_code}, 0, 'Merge with remote renumbering succeeds');
    is($result->{records}{'#5'},
       "#5=IFCPROPERTYSINGLEVALUE('Door #3',\$,IFCLABEL('see #2 and #4, it''s #3'),\$);\n",
       'Strings in renumbered remote entity are unchanged');
    is($result->{records}{'#6'}, "#6=IFCPROPERTYSET('0def',\$,'Pset #3',\$,(#5));\n",
       'References in renumbered remote entity are renumbered, strings are not');
}

# Modified entity that refers to an added entity is renumbered in the same way
{
    my @base_rel = (@base, "#3=$rel");
    write_ifc('base.ifc', @base_rel);
    write_ifc('local.ifc', @base_rel[0, 1], "#3=IFCRELDEFINESBYPROPERTIES('0abc',\$,'Rel #4',\$,(#1),#5)",
              "#4=IFCCARTESIANPOINT((7.,7.))", "#5=$pset");
    write_ifc('remote.ifc', @base_rel, "#4=IFCCARTESIANPOINT((9.,9.))", "#5=IFCCARTESIANPOINT((8.,8.))");
    my $result = run_merge('');
    is($result->{exit_code}, 0, 'Merge with modified entity succeeds');
    is($result->{records}{'#3'}, "#3=IFCRELDEFINESBYPROPERTIES('0abc',\$,'Rel #4',\$,(#1),#7);\n",
       'Strings in modified entity are unchanged when renumbering');
}

# ============================================================================
# IDs in strings don't count as references to deleted entities
# ============================================================================

for my $flag ('', '--prioritise-local') {
    my $label = $flag || 'default';
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', $base[0]);
    write_ifc('remote.ifc', @base, "#3=IFCPROPERTYSINGLEVALUE('Point #2',\$,\$,\$)");
    my $result = run_merge($flag);
    is($result->{exit_code}, 0, "Deleting an entity named in a string merges ($label)");
    unlike($result->{output}, qr/required_entity_deleted/, "No required_entity_deleted conflict ($label)");
    ok(!$result->{records}{'#2'}, "Deleted entity stays deleted ($label)");
    is($result->{records}{'#3'}, "#3=IFCPROPERTYSINGLEVALUE('Point #2',\$,\$,\$);\n",
       "Added entity is kept ($label)");
}

# A real reference to a deleted entity is still a conflict
{
    write_ifc('base.ifc', @base);
    write_ifc('local.ifc', $base[0]);
    write_ifc('remote.ifc', @base, "#3=IFCPOLYLINE((#1,#2))");
    my $result = run_merge('');
    is($result->{exit_code}, 1, 'Deleting a referenced entity fails the merge');
    like($result->{output}, qr/required_entity_deleted/, 'required_entity_deleted conflict is reported');
}

done_testing();
