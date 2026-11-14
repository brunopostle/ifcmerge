#!/usr/bin/perl

# Regression tests for lists of integers (not step IDs) changed differently in
# local and remote. These must be reported as conflicts rather than being
# merged as sets of IDs, which found no IDs and wrote out an empty list.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

my $test_dir = tempdir(CLEANUP => 1);

sub write_ifc {
    my ($name, $coord_index, $related) = @_;
    $related //= '(#3,#4)';
    open my $fh, '>', "$test_dir/$name" or die "cannot write $name: $!";
    print $fh "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION((''),'2;1');\nFILE_NAME('','',(''),(''),'','','');\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";
    print $fh "#1=IFCINDEXEDPOLYGONALFACE($coord_index);\n";
    print $fh "#2=IFCRELAGGREGATES('0abc',\$,\$,\$,#5,$related);\n";
    print $fh "#3=IFCWALL('0def',\$,\$,\$,\$,\$,\$,\$,\$);\n";
    print $fh "#4=IFCWALL('0ghi',\$,\$,\$,\$,\$,\$,\$,\$);\n";
    print $fh "#5=IFCBUILDINGSTOREY('0jkl',\$,\$,\$,\$,\$,\$,\$,\$,\$);\n";
    print $fh "#6=IFCWALL('0mno',\$,\$,\$,\$,\$,\$,\$,\$);\n";
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
    return { exit_code => $? >> 8, output => $output, records => \%records, written => -f $merged };
}

sub conflicts {
    my ($output) = @_;
    my ($json) = $output =~ /(\{.*\})/s;
    return [] unless $json;
    return decode_json($json)->{conflicts} || [];
}

# ============================================================================
# Integer list changed on both sides is a conflict
# ============================================================================

for my $case (['(1,2,3)', '(1,2,4)', '(1,3,4)', 'non-empty base'],
              ['()', '(1,2)', '(3,4)', 'empty base']) {
    my ($base, $local, $remote, $desc) = @$case;
    write_ifc('base.ifc', $base);
    write_ifc('local.ifc', $local);
    write_ifc('remote.ifc', $remote);

    for my $flag ('', '--prioritise-local') {
        my $result = run_merge($flag);
        my $label = ($flag || 'default') . ", $desc";
        is($result->{exit_code}, 1, "Integer list conflict fails the merge ($label)");
        ok(!$result->{written}, "No merged file is written ($label)");

        my ($conflict) = grep { $_->{entity_id} == 1 } @{conflicts($result->{output})};
        ok($conflict, "Conflict is reported for the face ($label)");
        is($conflict->{type}, 'attribute_conflict', "Conflict type is attribute_conflict ($label)");
        is($conflict->{attribute_index}, 1, "Conflict is on the CoordIndex attribute ($label)");
        is($conflict->{local_value}, $local, "Local value is reported ($label)");
        is($conflict->{remote_value}, $remote, "Remote value is reported ($label)");
        is($conflict->{selected_value}, $flag ? $local : $remote, "Selected value follows priority ($label)");
    }
}

# ============================================================================
# Integer list changed on one side only merges cleanly
# ============================================================================

write_ifc('base.ifc', '(1,2,3)');
write_ifc('local.ifc', '(1,2,4)');
write_ifc('remote.ifc', '(1,2,3)', '(#3)');
{
    my $result = run_merge('');
    is($result->{exit_code}, 0, 'One-sided integer list change merges');
    is($result->{records}{'#1'}, "#1=IFCINDEXEDPOLYGONALFACE((1,2,4));\n", 'Local integer list is kept');
}

# ============================================================================
# Lists of IDs changed on both sides are still merged as sets
# ============================================================================

write_ifc('base.ifc', '(1,2,3)');
write_ifc('local.ifc', '(1,2,3)', '(#3,#4,#6)');
write_ifc('remote.ifc', '(1,2,3)', '(#4)');
{
    my $result = run_merge('');
    is($result->{exit_code}, 0, 'ID list changed on both sides merges');
    is($result->{records}{'#2'}, "#2=IFCRELAGGREGATES('0abc',\$,\$,\$,#5,(#4,#6));\n",
       'ID list additions and removals from both sides are merged');
}

done_testing();
