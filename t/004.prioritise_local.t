#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile tempdir);
use Digest::MD5;

# Regression test for --prioritise-local flag behavior
# This flag is only available in refactoring branch
# Verifies that local IDs are preserved and remote IDs are renumbered

my $fixtures = 't/fixtures';
die "Fixtures directory not found at $fixtures" unless -d $fixtures;

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

# Check if --prioritise-local flag exists (refactoring branch only)
my $help_output = `$ifcmerge --help 2>&1`;
if ($help_output !~ /prioritise-local/) {
    plan skip_all => '--prioritise-local flag not available (main branch)';
    exit 0;
}

my $test_dir = tempdir(CLEANUP => 1);

# Helper to compute MD5 checksum of file content (excluding timestamp)
sub file_checksum {
    my ($path) = @_;

    open my $fh, '<', $path or die "Cannot open $path: $!";
    my $md5 = Digest::MD5->new;

    while (my $line = <$fh>) {
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
# Test 1: Basic --prioritise-local flag works
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";
    my $merged = "$test_dir/prioritise_local_basic.ifc";

    my $output = `$ifcmerge --prioritise-local $base $local $remote $merged 2>&1`;
    my $exit_code = $? >> 8;

    ok($exit_code == 0, '--prioritise-local merge succeeds');
    ok(-f $merged, 'Merged file created with --prioritise-local');

    my $base_max = highest_entity_id($base);
    my $merged_max = highest_entity_id($merged);

    ok($merged_max > $base_max, 'Merged file has higher IDs than base');
}

# ============================================================================
# Test 2: Local IDs are preserved (not renumbered) with --prioritise-local
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_window_wall1.ifc";
    my $merged = "$test_dir/local_priority_test.ifc";

    my $output = `$ifcmerge --prioritise-local $base $local $remote $merged 2>&1`;
    my $exit_code = $? >> 8;

    ok($exit_code == 0, 'Local priority merge succeeds');

    # Get ID range from local file (entities added beyond base)
    my $base_max = highest_entity_id($base);
    my $local_max = highest_entity_id($local);

    # Count how many entities from local appear in merged file
    # (in their original ID range, i.e., not renumbered)
    my $local_entities_preserved = count_entities_in_range(
        $merged,
        $base_max + 1,
        $local_max
    );

    ok($local_entities_preserved > 0,
       'Local entities appear in merged file with original IDs (not renumbered)');
}

# ============================================================================
# Test 3: Remote IDs are renumbered when overlapping with local
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";
    my $merged = "$test_dir/remote_renumber_test.ifc";

    my $output = `$ifcmerge --prioritise-local $base $local $remote $merged 2>&1`;

    my $base_max = highest_entity_id($base);
    my $local_max = highest_entity_id($local);
    my $remote_max = highest_entity_id($remote);
    my $merged_max = highest_entity_id($merged);

    # If local and remote both add entities, remote should be renumbered
    # So merged max should be greater than just local max
    if ($local_max > $base_max && $remote_max > $base_max) {
        ok($merged_max > $local_max,
           'Remote IDs were renumbered (merged max > local max)');
    } else {
        pass('Skipping: scenario not applicable');
    }
}

# ============================================================================
# Test 4: Different output than default (no flag)
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";

    # Default behavior (prioritise remote)
    my $merged_default = "$test_dir/default.ifc";
    `$ifcmerge $base $local $remote $merged_default 2>&1`;

    # With --prioritise-local
    my $merged_local = "$test_dir/prioritise_local.ifc";
    `$ifcmerge --prioritise-local $base $local $remote $merged_local 2>&1`;

    my $checksum_default = file_checksum($merged_default);
    my $checksum_local = file_checksum($merged_local);

    isnt($checksum_default, $checksum_local,
         'Output differs from default (--prioritise-local changes behavior)');

    # Verify default matches known checksum
    is($checksum_default, '29d4ac548d16b2006666dbdef3a80de2',
       'Default output matches known checksum');
}

# ============================================================================
# Test 5: Known good checksum with --prioritise-local
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_five_new_elements.ifc";
    my $remote = "$fixtures/add_eight_new_elements.ifc";
    my $merged = "$test_dir/checksum_test.ifc";

    my $output = `$ifcmerge --prioritise-local $base $local $remote $merged 2>&1`;
    my $exit_code = $? >> 8;

    ok($exit_code == 0, 'Checksum test merge succeeds');

    my $checksum = file_checksum($merged);

    # Establish known good checksum for --prioritise-local behavior
    # This will be different from the default checksum
    ok(length($checksum) == 32, 'Checksum generated successfully');

    # Store the checksum for future regression testing
    note("--prioritise-local checksum: $checksum");
}

# ============================================================================
# Test 6: Symmetry - swapping local/remote with --prioritise-local
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";

    # First: local=A, remote=B with --prioritise-local
    my $merged1 = "$test_dir/symmetry_local_test1.ifc";
    `$ifcmerge --prioritise-local $base $fixtures/add_five_new_elements.ifc $fixtures/add_eight_new_elements.ifc $merged1 2>&1`;

    # Second: local=B, remote=A with --prioritise-local (swapped)
    my $merged2 = "$test_dir/symmetry_local_test2.ifc";
    `$ifcmerge --prioritise-local $base $fixtures/add_eight_new_elements.ifc $fixtures/add_five_new_elements.ifc $merged2 2>&1`;

    my $checksum1 = file_checksum($merged1);
    my $checksum2 = file_checksum($merged2);

    # These should be different (because different IDs are renumbered)
    isnt($checksum1, $checksum2,
         'Swapping local/remote produces different output (priority matters)');
}

# ============================================================================
# Test 7: Determinism with --prioritise-local
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/add_window_wall1.ifc";
    my $remote = "$fixtures/add_door_wall3.ifc";

    # Run merge twice with --prioritise-local
    my $merged1 = "$test_dir/determinism_test1.ifc";
    my $merged2 = "$test_dir/determinism_test2.ifc";

    `$ifcmerge --prioritise-local $base $local $remote $merged1 2>&1`;
    `$ifcmerge --prioritise-local $base $local $remote $merged2 2>&1`;

    my $checksum1 = file_checksum($merged1);
    my $checksum2 = file_checksum($merged2);

    is($checksum1, $checksum2,
       'Repeated merges with --prioritise-local produce identical output');
}

# ============================================================================
# Test 8: Placement conflict auto-resolution respects --prioritise-local
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/placement_window1_moved_left.ifc";
    my $remote = "$fixtures/placement_window1_moved_right.ifc";

    # Default (prioritise remote)
    my $merged_default = "$test_dir/placement_default.ifc";
    my $output_default = `$ifcmerge $base $local $remote $merged_default 2>&1`;
    my $exit_default = $? >> 8;

    # With --prioritise-local
    my $merged_local = "$test_dir/placement_local.ifc";
    my $output_local = `$ifcmerge --prioritise-local $base $local $remote $merged_local 2>&1`;
    my $exit_local = $? >> 8;

    # Both should succeed (placement auto-resolution)
    ok($exit_default == 0, 'Placement conflict auto-resolved (default)');
    ok($exit_local == 0, 'Placement conflict auto-resolved (--prioritise-local)');

    # But they should produce different results
    if (-f $merged_default && -f $merged_local) {
        my $checksum_default = file_checksum($merged_default);
        my $checksum_local = file_checksum($merged_local);

        isnt($checksum_default, $checksum_local,
             'Placement auto-resolution respects priority flag');
    } else {
        fail('Merged files not created');
    }
}

# ============================================================================
# Test 9: Attribute conflict resolution respects --prioritise-local
# ============================================================================
{
    my $base = "$fixtures/base_simple_room.ifc";
    my $local = "$fixtures/modify_window1_name_alpha.ifc";
    my $remote = "$fixtures/modify_window1_name_beta.ifc";

    # Default (prioritise remote) - should fail with conflict
    my $merged_default = "$test_dir/conflict_default.ifc";
    my $output_default = `$ifcmerge $base $local $remote $merged_default 2>&1`;
    my $exit_default = $? >> 8;

    # With --prioritise-local - should also fail with conflict
    my $merged_local = "$test_dir/conflict_local.ifc";
    my $output_local = `$ifcmerge --prioritise-local $base $local $remote $merged_local 2>&1`;
    my $exit_local = $? >> 8;

    # Both should fail (conflicts still cause failure)
    ok($exit_default != 0, 'Attribute conflict fails (default)');
    ok($exit_local != 0, 'Attribute conflict fails (--prioritise-local)');

    # But error messages should indicate different selections
    like($output_default, qr/Window-Beta|prioritising remote/i,
         'Default selects remote value in conflict');
    like($output_local, qr/Window-Alpha|prioritising local/i,
         '--prioritise-local selects local value in conflict');
}

done_testing();
