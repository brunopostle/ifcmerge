#!/usr/bin/perl

# Regression tests for a single-reference attribute (#123) changed differently
# in local and remote. Placement references are auto-resolved, any other
# reference must be reported as a conflict rather than written out empty.

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use JSON::PP;

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

my $test_dir = tempdir(CLEANUP => 1);

# A wall with a Representation (attribute 7) and an ObjectPlacement (attribute 6)
sub write_ifc {
    my ($name, $wall_name, $placement, $representation) = @_;
    open my $fh, '>', "$test_dir/$name" or die "cannot write $name: $!";
    print $fh "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION((''),'2;1');\nFILE_NAME('','',(''),(''),'','','');\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";
    print $fh "#1=IFCLOCALPLACEMENT(\$,\$);\n";
    print $fh "#2=IFCLOCALPLACEMENT(\$,\$);\n";
    print $fh "#3=IFCLOCALPLACEMENT(\$,\$);\n";
    print $fh "#4=IFCPRODUCTDEFINITIONSHAPE(\$,\$,());\n";
    print $fh "#5=IFCPRODUCTDEFINITIONSHAPE(\$,\$,());\n";
    print $fh "#6=IFCPRODUCTDEFINITIONSHAPE(\$,\$,());\n";
    print $fh "#7=IFCWALL('0abc',\$,$wall_name,\$,\$,$placement,$representation,\$,\$);\n";
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
        ($record) = grep { /^#7=/ } <$fh>;
        close $fh;
    }
    return { exit_code => $? >> 8, output => $output, record => $record };
}

sub conflicts {
    my ($output) = @_;
    my ($json) = $output =~ /(\{.*\})/s;
    return [] unless $json;
    return decode_json($json)->{conflicts} || [];
}

write_ifc('base.ifc', "'Wall'", '#1', '#4');

# ============================================================================
# Non-placement reference changed on both sides is a conflict
# ============================================================================

write_ifc('local.ifc', "'Wall'", '#1', '#5');
write_ifc('remote.ifc', "'Wall'", '#1', '#6');

for my $flag ('', '--prioritise-local') {
    my $result = run_merge($flag);
    my $label = $flag || 'default';
    is($result->{exit_code}, 1, "Representation conflict fails the merge ($label)");
    ok(!defined $result->{record}, "No merged file is written ($label)");
    unlike($result->{output}, qr/uninitialized/, "No uninitialized value warning ($label)");

    my ($conflict) = grep { $_->{entity_id} == 7 } @{conflicts($result->{output})};
    ok($conflict, "Conflict is reported for the wall ($label)");
    is($conflict->{type}, 'attribute_conflict', "Conflict type is attribute_conflict ($label)");
    is($conflict->{attribute_index}, 7, "Conflict is on the Representation attribute ($label)");
    is($conflict->{local_value}, '#5', "Local value is reported ($label)");
    is($conflict->{remote_value}, '#6', "Remote value is reported ($label)");
    is($conflict->{selected_value}, $flag ? '#5' : '#6', "Selected value follows priority ($label)");
}

# Reported alongside another conflicting attribute in the same entity

write_ifc('local.ifc', "'Wall A'", '#1', '#5');
write_ifc('remote.ifc', "'Wall B'", '#1', '#6');
{
    my $result = run_merge('');
    is($result->{exit_code}, 1, 'Name and Representation conflict fails the merge');
    my @indexes = sort { $a <=> $b } map { $_->{attribute_index} }
        grep { $_->{entity_id} == 7 } @{conflicts($result->{output})};
    is_deeply(\@indexes, [3, 7], 'Both the Name and Representation conflicts are reported');
}

# ============================================================================
# Placement reference changed on both sides is still auto-resolved
# ============================================================================

write_ifc('local.ifc', "'Wall'", '#2', '#4');
write_ifc('remote.ifc', "'Wall B'", '#3', '#4');

for my $flag ('', '--prioritise-local') {
    my $result = run_merge($flag);
    my $label = $flag || 'default';
    my $placement = $flag ? '#2' : '#3';
    is($result->{exit_code}, 0, "Placement conflict is auto-resolved ($label)");
    unlike($result->{output}, qr/uninitialized/, "No uninitialized value warning ($label)");
    is($result->{record}, "#7=IFCWALL('0abc',\$,'Wall B',\$,\$,$placement,#4,\$,\$);\n",
       "Placement follows priority and other changes are merged ($label)");
}

# ============================================================================
# Reference changed on one side only merges cleanly
# ============================================================================

write_ifc('local.ifc', "'Wall'", '#1', '#5');
write_ifc('remote.ifc', "'Wall B'", '#1', '#4');
{
    my $result = run_merge('');
    is($result->{exit_code}, 0, 'One-sided reference change merges');
    is($result->{record}, "#7=IFCWALL('0abc',\$,'Wall B',\$,\$,#1,#5,\$,\$);\n",
       'Local reference change and remote name change are both kept');
}

done_testing();
