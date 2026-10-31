#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

my $test_dir = tempdir(CLEANUP => 1);

sub write_ifc {
    my ($name, $closed, $index, $label, $description) = @_;
    open my $fh, '>', "$test_dir/$name" or die;
    print $fh "ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION((''),'2;1');\nFILE_NAME('','',(''),(''),'','','');\nFILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";
    print $fh "#1=IFCCARTESIANPOINTLIST3D(((0.,0.,0.),(1.,0.,0.),(1.,1.,0.)),\$);\n";
    print $fh "#2=IFCTRIANGULATEDFACESET(#1,\$,$closed,$index,\$);\n";
    print $fh "#3=IFCPROPERTYSINGLEVALUE($label,$description,IFCLABEL('a, (b)'),\$);\n";
    print $fh "ENDSEC;\nEND-ISO-10303-21;\n";
    close $fh;
}

sub merged_record {
    my ($id) = @_;
    open my $fh, '<', "$test_dir/merged.ifc" or die;
    my ($record) = grep { /^#$id=/ } <$fh>;
    close $fh;
    return $record;
}

my $triangles = 40000;
my $base_index = '(' . join(',', ('(1,2,3)') x $triangles) . ')';
my $remote_index = '(' . join(',', ('(1,2,3)') x ($triangles - 1), '(3,2,1)') . ')';

write_ifc('base.ifc', '.F.', $base_index, "'Name'", '$');
write_ifc('local.ifc', '.T.', $base_index, "'It''s, here'", '$');
write_ifc('remote.ifc', '.F.', $remote_index, "'Name'", "'d'");

my $output = `./ifcmerge $test_dir/base.ifc $test_dir/local.ifc $test_dir/remote.ifc $test_dir/merged.ifc 2>&1`;
is($? >> 8, 0, 'Merge of a face set with 40000 triangles succeeds');
is(merged_record(2), "#2=IFCTRIANGULATEDFACESET(#1,\$,.T.,$remote_index,\$);\n", 'Large list of lists is kept whole');
is(merged_record(3), "#3=IFCPROPERTYSINGLEVALUE('It''s, here','d',IFCLABEL('a, (b)'),\$);\n", 'Quoted commas, brackets and escaped quotes are not split');

done_testing();
