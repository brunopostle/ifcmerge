#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

my $fixtures = 't/fixtures';
die "Fixtures directory not found at $fixtures" unless -d $fixtures;

my $ifcmerge = './ifcmerge';
die "ifcmerge script not found at $ifcmerge" unless -f $ifcmerge;

my $test_dir = tempdir(CLEANUP => 1);

sub run_merge {
    my ($base, $local, $remote, $merged) = @_;
    my $merged_path = "$test_dir/$merged";
    my $cmd = "$ifcmerge $fixtures/$base $fixtures/$local $fixtures/$remote $merged_path 2>&1";
    my $output = `$cmd`;
    my $exit_code = $? >> 8;
    return {
        exit_code  => $exit_code,
        output     => $output,
        merged_file => $merged_path,
        success    => ($exit_code == 0)
    };
}

sub merged_content {
    my ($result) = @_;
    return '' unless -f $result->{merged_file};
    open my $fh, '<', $result->{merged_file} or return '';
    my $content = do { local $/; <$fh> };
    close $fh;
    return $content;
}

# ============================================================================
# Test 1: Float-only resave in local, remote unchanged
#
# local re-saves with new ifcopenshell which normalises float strings:
#   0.  -> 0.0,  1.E-05 -> 1.0E-5,  0.0174532925199433 -> 0.01745329251994329
# No intentional change was made - should not be detected as a modification.
# ============================================================================
{
    my $result = run_merge(
        'float_base.ifc',
        'float_resave_only.ifc',
        'float_base.ifc',
        'float_test1.ifc'
    );
    ok($result->{success}, 'Test 1: Float-only resave in local does not cause conflict');
}

# ============================================================================
# Test 2: Float-only resave in remote, local unchanged
# ============================================================================
{
    my $result = run_merge(
        'float_base.ifc',
        'float_base.ifc',
        'float_resave_only.ifc',
        'float_test2.ifc'
    );
    ok($result->{success}, 'Test 2: Float-only resave in remote does not cause conflict');
}

# ============================================================================
# Test 3: Both sides resave with normalised floats (same normalisation)
# ============================================================================
{
    my $result = run_merge(
        'float_base.ifc',
        'float_resave_only.ifc',
        'float_resave_only.ifc',
        'float_test3.ifc'
    );
    ok($result->{success}, 'Test 3: Both sides resave with same normalised floats - no conflict');
}

# ============================================================================
# Test 4: Float resave in local, genuine name change in remote
#
# The normalised floats in local must not interfere with the genuine name
# change in remote - they affect different entities.
# ============================================================================
{
    my $result = run_merge(
        'float_base.ifc',
        'float_resave_only.ifc',
        'float_name_changed.ifc',
        'float_test4.ifc'
    );
    ok($result->{success}, 'Test 4: Float resave in local + name change in remote merges cleanly');
    like(merged_content($result), qr/Renamed Project/,
         'Test 4: Merged file contains the remote name change');
}

# ============================================================================
# Test 5: Genuine float change in local, float resave in remote
#
# local intentionally moves the origin from (0,0,0) to (1,0,0).
# remote re-saves with normalised floats but makes no intentional change.
# Should succeed: local's change applied, remote's resave not a conflict.
# The merged output must preserve local's original string, not a normalised form.
# ============================================================================
{
    my $result = run_merge(
        'float_base.ifc',
        'float_coord_changed.ifc',
        'float_resave_only.ifc',
        'float_test5.ifc'
    );
    ok($result->{success}, 'Test 5: Genuine float change in local, resave in remote - no conflict');
    like(merged_content($result), qr/IFCCARTESIANPOINT\(\(1\./,
         'Test 5: Merged file preserves original string from local genuine change');
}

# ============================================================================
# Test 6: Genuine float change in remote, float resave in local (reversed)
# ============================================================================
{
    my $result = run_merge(
        'float_base.ifc',
        'float_resave_only.ifc',
        'float_coord_changed.ifc',
        'float_test6.ifc'
    );
    ok($result->{success}, 'Test 6: Float resave in local, genuine float change in remote - no conflict');
    like(merged_content($result), qr/IFCCARTESIANPOINT\(\(1\./,
         'Test 6: Merged file preserves original string from remote genuine change');
}

# ============================================================================
# Test 7: Genuine float conflict - both sides change the same coordinate
# to different values. Must still be detected as a real conflict.
# ============================================================================
{
    my $result = run_merge(
        'float_base.ifc',
        'float_coord_changed.ifc',
        'float_coord_changed_alt.ifc',
        'float_test7.ifc'
    );
    ok(!$result->{success}, 'Test 7: Genuine float conflict is still detected');
    like($result->{output}, qr/conflict/i, 'Test 7: Conflict error reported');
}

done_testing();
