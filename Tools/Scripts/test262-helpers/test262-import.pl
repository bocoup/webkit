#!/usr/bin/env perl

# Copyright (C) 2018 Bocoup LLC. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above
#    copyright notice, this list of conditions and the following
#    disclaimer.
# 2. Redistributions in binary form must reproduce the above
#    copyright notice, this list of conditions and the following
#    disclaimer in the documentation and/or other materials
#    provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER "AS IS" AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
# OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
# TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
# THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

use strict;
use warnings;

use File::Find;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use FindBin;

######
# # Use the following code run this script directly from Perl.
# # Otherwise, just use carton.
use Config;
use Encode;

BEGIN {
    $ENV{DBIC_OVERWRITE_HELPER_METHODS_OK} = 1;

    unshift @INC, ".";
    unshift @INC, "$FindBin::Bin/lib";
    unshift @INC, "$FindBin::Bin/local/lib/perl5";
    unshift @INC, "$FindBin::Bin/local/lib/perl5/$Config{archname}";

    $ENV{LOAD_ROUTES} = 1;
}
######

use YAML qw(Load LoadFile);
use Getopt::Long qw(GetOptions);
use Pod::Usage;

# Commandline args
my $test262Dir = abs_path("$FindBin::Bin/../../../JSTests/test262");
my $sourceDir;
my $revisionFile = abs_path("$FindBin::Bin/../../../JSTests/test262/test262-Revision.txt");
my $summaryFile = abs_path("$FindBin::Bin/../../../JSTests/test262/latest-changes-summary.txt");

processCLI();

main();

sub processCLI {
    my $help = 0;

    GetOptions(
        's|src=s' => \$sourceDir,
        'h|help' => \$help,
    );

    my $exitstatus = $sourceDir ? 1 : 0;

    if ($help) {
        pod2usage(-exitstatus => 0, -verbose => 1);
    }

    if (not $sourceDir) {
        print "Please specify the Test262 repository source folder.\n\n";
        pod2usage(-exitstatus => 1, -verbose => 1);
    };

    if (not -d $sourceDir
        or not -d "$sourceDir/.git"
        or not -d "$sourceDir/test"
        or not -d "$sourceDir/harness") {
        print "$sourceDir does not exist or is not a valid Test262 folder.\n\n";
        pod2usage(-exitstatus => 2, -verbose => 1);
    };

    if (abs_path($sourceDir) eq $test262Dir) {
        print "$sourceDir cannot be the same as the current Test262 folder.\n\n";
        pod2usage(-exitstatus => 3, -verbose => 1);
    }

    print "Settings:\n"
        . "Source: $sourceDir\n";

    print "--------------------------------------------------------\n\n";
}

sub main {
    my $startTime = time();

    # Get last imported revision
    my ($revision, $tracking) = getRevision();
    my ($newRevision, $newTracking, $newBranch) = getNewRevision();
    my ($summary, $stats) = compareRevisions($revision, $newRevision);

    transfer();
    saveRevision($newRevision, $newTracking, $stats);
    saveSummary($summary);

    my $endTime = time();
    my $totalTime = $endTime - $startTime;
    print "\nDone in $totalTime seconds!\n";
}

sub transfer {
    # Remove previous Test262 folders
    print qq/rm -rf $test262Dir\/harness\n/ if -e "$test262Dir/harness";
    qx/rm -rf $test262Dir\/harness/ if -e "$test262Dir/harness";
    print qq/rm -rf $test262Dir\/test\n/ if -e "$test262Dir/test";
    qx/rm -rf $test262Dir\/test/ if -e "$test262Dir/test";

    # Copy from source
    print qq/cp -r $sourceDir\/harness $test262Dir\n/;
    qx/cp -r $sourceDir\/harness $test262Dir/;
    print qq/cp -r $sourceDir\/test $test262Dir\n/;
    qx/cp -r $sourceDir\/test $test262Dir/;
}

sub getRevision {
    open(my $revfh, '<', $revisionFile) or die $!;

    my $revision;
    my $tracking;
    my $contents = join("\n", <$revfh>);

    # Some cheap yaml parsing, the YAML module is a possible alternative
    if ($contents =~ /test262 revision\: (\w*)/) {
        $revision = $1;
    } else {
        die 'No revision found in the current JSTests/test262 folder.';
    }

    if ($contents =~ /test262 remote url\: (.*)/) {
        $tracking = $1;
    } else {
        die 'No remote url found in the current JSTests/test262 folder.';
    }

    print "Current Test262 revision: $revision\n";
    print "Tracking from the following remote: $tracking\n";

    close($revfh);

    return $revision, $tracking;
}

sub getNewRevision {
    my $tracking = qx/git -C $sourceDir ls-remote --get-url/;
    chomp $tracking;
    my $branch = qx/git -C $sourceDir rev-parse --abbrev-ref HEAD/;
    chomp $branch;
    my $revision = qx/git -C $sourceDir rev-parse HEAD/;
    chomp $revision;

    print "New tracking: $tracking\n";
    print "From branch: $branch\n";
    print "New revision: $revision\n";

    if (!$revision or !$tracking or !$branch) {
        die 'Something is wrong in the source git.';
    }

    return $revision, $tracking, $branch;
}

sub compareRevisions {
    my ($old, $new) = @_;

    my $summary = qx/git -C $sourceDir diff --summary $old/;
    chomp $summary;

    my $stats = qx/git -C $sourceDir diff --shortstat $old/;
    chomp $stats;

    # Might use a patch file as well for diff
    # my $patch = qx/git -C $sourceDir diff $old/;

    print "$stats\n";

    return $summary, $stats;
}

sub saveRevision {
    my ($revision, $tracking, $stats) = @_;

    open(my $fh, '>', $revisionFile) or die $!;

    print $fh "test262 remote url: $tracking\n";
    print $fh "test262 revision: $revision\n";
    print $fh "test262 stats: $stats\n";

    close $fh;
}

sub saveSummary {
    my ($summary) = @_;

    open(my $fh, '>', $summaryFile) or die $!;

    print $fh $summary;

    close $fh;
}

__END__

=head1 DESCRIPTION

This program will import Test262 tests from a repository folder.

=head1 SYNOPSIS

Run using native Perl:

=over 8

./test262-import.pl -s $source

=back

=head1 OPTIONS

=over 8

=item B<--help, -h>

Print a brief help message.

=item B<--t262, -t>

Specify the folder for Test262's repository.

=back
=cut
