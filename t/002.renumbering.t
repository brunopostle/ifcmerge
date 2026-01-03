#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile tempdir);
use Digest::MD5;

# Regression test for ID renumbering behavior
# Verifies that default priority (remote over local) and ID renumbering
# logic remains consistent across versions

my $fixtures = 't/fixtures';
die "Fixtures directory not found at $fixtures" unless -d $fixtures;

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

my $test_dir = tempdir(CLEANUP => 1);

# Helper to compute MD5 checksum of file content (excluding timestamp)
sub file_checksum {
    my ($path) = @_;

    open my $fh, '<', $path or die "Cannot open $path: $!";
    my $md5 = Digest::MD5->new;

    while (my $line = <$fh>) {
        # Skip FILE_NAME line which contains timestamp
        next if $line =~ /^FILE_NAME/;
        $md5->add($line);
    }
    close $fh;

    return $md5->hexdigest;
}

# Helper to get highest entity ID from IFC file
sub highest_entity_id {
    my ($path) = @_;

    open my $fh, '<', $path or die "Cannot open $path: $!";
    my $max_id = 0;

    while (my $line = <$fh>) {
        if ($line =~ /#(\d+)=/) {
            $max_id = $1 if $1 > $max_id;
        }
    }
    close $fh;

    return $max_id;
}

# Helper to count entities in ID range
sub count_entities_in_range {
    my ($path, $min, $max) = @_;

    open my $fh, '<', $path or die "Cannot open $path: $!";
    my $count = 0;

    while (my $line = <$fh>) {
        if ($line =~ /#(\d+)=/) {
            $count++ if $1 >= $min && $1 <= $max;
        }
    }
    close $fh;

    return $count;
}

# ============================================================================
# Test 1: Basic ID renumbering with overlapping additions
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";
    my $merged = "$test_dir/renumber_test.ifc";

    my $output = `$ifcmerge $base $local $remote $merged 2>&1`;
    my $exit_code = $? >> 8;

    ok($exit_code == 0, 'ID renumbering merge succeeds');
    ok(-f $merged, 'Merged file created');

    # Verify highest ID is reasonable (should be higher than base due to additions)
    my $base_max = highest_entity_id($base);
    my $merged_max = highest_entity_id($merged);

    ok($merged_max > $base_max, 'Merged file has higher IDs than base');
    cmp_ok($merged_max, '>=', 3900, 'Highest ID is in expected range (>= 3900)');
    cmp_ok($merged_max, '<=', 4000, 'Highest ID is in expected range (<= 4000)');
}

# ============================================================================
# Test 2: Remote IDs are preserved (not renumbered)
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_window_wall1.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";
    my $merged = "$test_dir/remote_priority_test.ifc";

    my $output = `$ifcmerge $base $local $remote $merged 2>&1`;
    my $exit_code = $? >> 8;

    ok($exit_code == 0, 'Remote priority merge succeeds');

    # Get ID range from remote file (entities added beyond base)
    my $base_max = highest_entity_id($base);
    my $remote_max = highest_entity_id($remote);

    # Count how many entities from remote appear in merged file
    # (in their original ID range, i.e., not renumbered)
    my $remote_entities_preserved = count_entities_in_range(
        $merged,
        $base_max + 1,
        $remote_max
    );

    ok($remote_entities_preserved > 0,
       'Remote entities appear in merged file with original IDs (not renumbered)');
}

# ============================================================================
# Test 3: Local IDs are renumbered when overlapping with remote
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";
    my $merged = "$test_dir/local_renumber_test.ifc";

    my $output = `$ifcmerge $base $local $remote $merged 2>&1`;

    my $base_max = highest_entity_id($base);
    my $local_max = highest_entity_id($local);
    my $remote_max = highest_entity_id($remote);
    my $merged_max = highest_entity_id($merged);

    # If local and remote both add entities, local should be renumbered
    # So merged max should be greater than just remote max
    if ($local_max > $base_max && $remote_max > $base_max) {
        ok($merged_max > $remote_max,
           'Local IDs were renumbered (merged max > remote max)');
    } else {
        pass('Skipping: scenario not applicable');
    }
}

# ============================================================================
# Test 4: Regression - Known good checksum
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";
    my $merged = "$test_dir/checksum_test.ifc";

    my $output = `$ifcmerge $base $local $remote $merged 2>&1`;
    my $exit_code = $? >> 8;

    ok($exit_code == 0, 'Checksum test merge succeeds');

    my $checksum = file_checksum($merged);

    # This is the known good checksum from verified output
    # Both main and refactoring branches should produce this
    my $expected_checksum = '29d4ac548d16b2006666dbdef3a80de2';

    is($checksum, $expected_checksum,
       'Output matches known good checksum (renumbering behavior unchanged)');
}

# ============================================================================
# Test 5: Symmetry - swapping local/remote changes result appropriately
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";

    # First: local=A, remote=B
    my $merged1 = "$test_dir/symmetry_test1.ifc";
    `$ifcmerge $base $fixtures/add_five_new_elements.ifc $fixtures/add_eight_new_elements.ifc $merged1 2>&1`;

    # Second: local=B, remote=A (swapped)
    my $merged2 = "$test_dir/symmetry_test2.ifc";
    `$ifcmerge $base $fixtures/add_eight_new_elements.ifc $fixtures/add_five_new_elements.ifc $merged2 2>&1`;

    my $checksum1 = file_checksum($merged1);
    my $checksum2 = file_checksum($merged2);

    # These should be different (because different IDs are renumbered)
    isnt($checksum1, $checksum2,
         'Swapping local/remote produces different output (priority matters)');
}

# ============================================================================
# Test 6: Clean merge produces consistent output
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_window_wall1.ifc";
    my $remote = "$fixtures/add_door_wall3.ifc";

    # Run merge twice
    my $merged1 = "$test_dir/clean_test1.ifc";
    my $merged2 = "$test_dir/clean_test2.ifc";

    `$ifcmerge $base $local $remote $merged1 2>&1`;
    `$ifcmerge $base $local $remote $merged2 2>&1`;

    my $checksum1 = file_checksum($merged1);
    my $checksum2 = file_checksum($merged2);

    is($checksum1, $checksum2,
       'Repeated merges produce identical output (deterministic behavior)');
}

done_testing();
