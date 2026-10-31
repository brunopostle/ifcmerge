#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

my $fixtures = 't/fixtures';
my $test_dir = tempdir(CLEANUP => 1);
my $merged = "$test_dir/merged.ifc";

my $output = `./ifcmerge $fixtures/nested_list_base.ifc $fixtures/nested_list_local.ifc $fixtures/nested_list_remote.ifc $merged 2>&1`;
is($? >> 8, 0, 'Both sides change different attributes of an entity with a list of lists');

open my $fh, '<', $merged or die "cannot read $merged";
my ($record) = grep { /^#2=/ } <$fh>;
close $fh;
is($record, "#2=IFCTRIANGULATEDFACESET(#1,\$,.T.,((1,2,4),(2,3,4)),\$);\n", 'Nested list attribute is kept whole');

done_testing();
