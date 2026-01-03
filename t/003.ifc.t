#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempfile tempdir);
use File::Copy;

# Test directory with fixtures
my $fixtures = 't/fixtures';
die "Fixtures directory not found at $fixtures" unless -d $fixtures;

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

# Create temp directory for test outputs
my $test_dir = tempdir(CLEANUP => 1);

# Helper function to run merge
sub run_merge {
    my ($base, $local, $remote, $merged, $extra_args) = @_;
    $extra_args //= '';

    my $base_path = "$fixtures/$base";
    my $local_path = "$fixtures/$local";
    my $remote_path = "$fixtures/$remote";
    my $merged_path = "$test_dir/$merged";

    my $cmd = "$ifcmerge $extra_args $base_path $local_path $remote_path $merged_path 2>&1";
    my $output = `$cmd`;
    my $exit_code = $? >> 8;

    return {
        exit_code => $exit_code,
        output => $output,
        merged_file => $merged_path,
        success => ($exit_code == 0)
    };
}

# Helper to check if merged file was created and is valid
sub merged_file_valid {
    my ($result) = @_;
    return 0 unless -f $result->{merged_file};

    # Check if it's a valid IFC file
    open my $fh, '<', $result->{merged_file} or return 0;
    my $first_line = <$fh>;
    close $fh;

    return ($first_line && $first_line =~ /ISO-10303-21/);
}

# ============================================================================
# Test 1: Clean merge - non-overlapping additions
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'add_window_wall1.ifc',
        'add_door_wall3.ifc',
        'test1_merged.ifc'
    );

    ok($result->{success}, 'Test 1: Clean merge succeeds');
    ok(merged_file_valid($result), 'Test 1: Merged file is valid IFC');
    like($result->{output}, qr/Success/i, 'Test 1: Success message printed');
}

# ============================================================================
# Test 2: Clean merge - different window additions
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'add_window_wall1.ifc',
        'add_window_wall2.ifc',
        'test2_merged.ifc'
    );

    ok($result->{success}, 'Test 2: Non-conflicting additions merge cleanly');
    ok(merged_file_valid($result), 'Test 2: Merged file is valid');
}

# ============================================================================
# Test 3: Clean merge - addition + modification of different entities
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'add_window_wall1.ifc',
        'modify_wall3_height_3000.ifc',
        'test3_merged.ifc'
    );

    ok($result->{success}, 'Test 3: Addition + modification merge cleanly');
    ok(merged_file_valid($result), 'Test 3: Merged file is valid');
}

# ============================================================================
# Test 4: Delete-modify conflict
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'delete_wall4.ifc',
        'modify_wall4_height_3500.ifc',
        'test4_merged.ifc'
    );

    ok(!$result->{success}, 'Test 4: Delete-modify conflict fails');
    like($result->{output}, qr/deleted.*modified|modified.*deleted/i,
         'Test 4: Error message mentions delete and modify');
}

# ============================================================================
# Test 5: Delete-modify conflict (reversed)
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'modify_wall4_height_3500.ifc',
        'delete_wall4.ifc',
        'test5_merged.ifc'
    );

    ok(!$result->{success}, 'Test 5: Delete-modify conflict (reversed) fails');
    like($result->{output}, qr/deleted.*modified|modified.*deleted/i,
         'Test 5: Error message mentions delete and modify');
}

# ============================================================================
# Test 6: Modify-modify conflict on same attribute
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'modify_window1_name_alpha.ifc',
        'modify_window1_name_beta.ifc',
        'test6_merged.ifc'
    );

    # On main branch: this will conflict
    # On refactoring branch: this will auto-resolve (prioritise remote by default)
    # We expect main branch behavior here
    ok(!$result->{success}, 'Test 6: Modify-modify conflict on same attribute');
    like($result->{output}, qr/conflict/i, 'Test 6: Conflict message present');
}

# ============================================================================
# Test 7: Modify different entities - wall and different window
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'modify_window1_name_alpha.ifc',
        'modify_window2_name_gamma.ifc',
        'test7_merged.ifc'
    );

    ok($result->{success}, 'Test 7: Modifications to different entities merge cleanly');
    ok(merged_file_valid($result), 'Test 7: Merged file is valid');
}

# ============================================================================
# Test 8: Floor deletion + wall addition (no actual dependency in this case)
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'delete_floor.ifc',
        'add_wall_and_window.ifc',
        'test8_merged.ifc'
    );

    # On main branch: succeeds (no required entity check for this scenario)
    # On refactoring branch: might detect dependency and fail
    ok($result->{success}, 'Test 8: Floor deletion + wall addition succeeds on main');
    ok(merged_file_valid($result), 'Test 8: Merged file is valid');
}

# ============================================================================
# Test 9: ID renumbering with overlapping additions
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'add_five_new_elements.ifc',
        'add_eight_new_elements.ifc',
        'test9_merged.ifc'
    );

    ok($result->{success}, 'Test 9: Overlapping ID ranges merge successfully');
    ok(merged_file_valid($result), 'Test 9: Merged file is valid after renumbering');
}

# ============================================================================
# Test 10: Combined operations - deletion and addition
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'delete_window_wall1.ifc',
        'add_door_wall3.ifc',
        'test10_merged.ifc'
    );

    ok($result->{success}, 'Test 10: Deletion in local + addition in remote succeeds');
    ok(merged_file_valid($result), 'Test 10: Merged file is valid');
}

# ============================================================================
# Test 11: Combined operations in same file
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'add_window_modify_wall3.ifc',
        'add_door_wall3.ifc',
        'test11_merged.ifc'
    );

    ok($result->{success}, 'Test 11: Combined operations merge successfully');
    ok(merged_file_valid($result), 'Test 11: Merged file is valid');
}

# ============================================================================
# Test 12: Boundary modification conflict
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'boundary_wall1_type_physical.ifc',
        'boundary_wall1_type_virtual.ifc',
        'test12_merged.ifc'
    );

    ok(!$result->{success}, 'Test 12: Boundary type conflict fails');
    like($result->{output}, qr/conflict/i, 'Test 12: Conflict message present');
}

# ============================================================================
# Test 13: Placement modification conflict
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'placement_window1_moved_left.ifc',
        'placement_window1_moved_right.ifc',
        'test13_merged.ifc'
    );

    # On main branch: this should conflict
    # On refactoring branch: this might auto-resolve for IfcLocalPlacement
    ok(!$result->{success}, 'Test 13: Placement conflict on main branch');
    like($result->{output}, qr/conflict/i, 'Test 13: Conflict message present');
}

# ============================================================================
# Test 14: Wall modification + window modification (different entities)
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'modify_wall3_height_3000.ifc',
        'modify_window1_name_beta.ifc',
        'test14_merged.ifc'
    );

    ok($result->{success}, 'Test 14: Modifications to different entities succeed');
    ok(merged_file_valid($result), 'Test 14: Merged file is valid');
}

# ============================================================================
# Test 15: Multiple deletions
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'delete_two_windows.ifc',
        'add_window_wall2.ifc',
        'test15_merged.ifc'
    );

    ok($result->{success}, 'Test 15: Deletions + additions on different entities succeed');
    ok(merged_file_valid($result), 'Test 15: Merged file is valid');
}

# ============================================================================
# Test 16: Symmetry test - swap local and remote
# ============================================================================
{
    my $result1 = run_merge(
        'base_simple_room.ifc',
        'modify_window1_name_alpha.ifc',
        'modify_window1_name_beta.ifc',
        'test16a_merged.ifc'
    );

    my $result2 = run_merge(
        'base_simple_room.ifc',
        'modify_window1_name_beta.ifc',
        'modify_window1_name_alpha.ifc',
        'test16b_merged.ifc'
    );

    # Both should fail (conflict)
    ok(!$result1->{success}, 'Test 16a: Conflict in original order');
    ok(!$result2->{success}, 'Test 16b: Conflict in swapped order');

    # On main branch, both should behave the same (both fail)
    # The actual merged content might differ, but both should report conflicts
    is($result1->{success}, $result2->{success},
       'Test 16: Swapping local/remote gives consistent success/failure');
}

# ============================================================================
# Test 17: No changes (base = local = remote)
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'base_simple_room.ifc',
        'base_simple_room.ifc',
        'test17_merged.ifc'
    );

    ok($result->{success}, 'Test 17: No changes merge successfully');
    ok(merged_file_valid($result), 'Test 17: Merged file is valid');
}

# ============================================================================
# Test 18: Only local changes
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'add_window_wall1.ifc',
        'base_simple_room.ifc',
        'test18_merged.ifc'
    );

    ok($result->{success}, 'Test 18: Only local changes merge successfully');
    ok(merged_file_valid($result), 'Test 18: Merged file is valid');
}

# ============================================================================
# Test 19: Only remote changes
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'base_simple_room.ifc',
        'add_door_wall3.ifc',
        'test19_merged.ifc'
    );

    ok($result->{success}, 'Test 19: Only remote changes merge successfully');
    ok(merged_file_valid($result), 'Test 19: Merged file is valid');
}

# ============================================================================
# Test 20: Complex combined operations
# ============================================================================
{
    my $result = run_merge(
        'base_simple_room.ifc',
        'modify_window1_and_wall3.ifc',
        'add_two_windows.ifc',
        'test20_merged.ifc'
    );

    ok($result->{success}, 'Test 20: Complex combined operations succeed');
    ok(merged_file_valid($result), 'Test 20: Merged file is valid');
}

done_testing();
