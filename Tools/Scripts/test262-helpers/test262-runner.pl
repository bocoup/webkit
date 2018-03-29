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
use 5.8.8;

use File::Find;
use File::Temp qw(tempfile tempdir);
use File::Spec::Functions qw(abs2rel);
use Cwd 'abs_path';
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
use Parallel::ForkManager;
use Getopt::Long qw(GetOptions);
use Pod::Usage;

# Commandline args
my $cliProcesses;
my @cliTestDirs;
my $JSC;

processCLI();

my $tempdir = tempdir();

my $test262Dir = abs_path("$FindBin::Bin/../../../JSTests/test262");
my $harnessDir = "$test262Dir/harness";

my @default_harnesses = (
    "$harnessDir/sta.js",
    "$harnessDir/assert.js",
    "$harnessDir/doneprintHandle.js",
    "$FindBin::Bin/agent.js"
);

my $config = LoadFile("$FindBin::Bin/test262-config.yaml")
    or die $!;

my $tests_log = "$FindBin::Bin/tests.log";

my @files;
my ($resfh, $resfilename) = getTempFile();

my ($deffh, $deffile) = getTempFile();
print $deffh getHarness(<@default_harnesses>);

my $startTime = time();

main();

sub processCLI {
    my $help = 0;
    my $debug;

    GetOptions(
        'j|jsc=s' => \$JSC,
        't|t262=s@' => \@cliTestDirs,
        'p|child-processes=i' => \$cliProcesses,
        'h|help' => \$help,
        'd|debug' => \$debug,
    );

    if ($help) {
        pod2usage(-exitstatus => 0, -verbose => 2);
    }

    if ($JSC) {
        $JSC = abs_path($JSC);
        # Make sure the path and file jsc exist
        if (! ($JSC && -e $JSC)) {
            die "Error: --jsc path does not exist.";
        }
    }
    else {
        # Try to find JSC for user, if not supplied
        my $cmd = abs_path("$FindBin::Bin/../webkit-build-directory");
        if (! -e $cmd) {
            die "Error: cannot find webkit-build-directory, specify with JSC with --jsc <path>.";
        }

        if ($debug) {
            $cmd .= " --debug";
        } else {
            $cmd .= " --release";
        }
        $cmd .= " --executablePath";
        my $JSCdir = qx($cmd);
        chomp $JSCdir;

        $JSC = $JSCdir . "/jsc";
        $JSC = $JSCdir . "/JavaScriptCore.framework/Resources/jsc" if (! -e $JSC);
        $JSC = $JSCdir . "/bin/jsc" if (! -e $JSC);
        if (! -e $JSC) {
            die "Error: cannot find jsc, specify with --jsc <path>.";
        }

        print("Using the following jsc path: $JSC\n");
    }
}


sub main {
    my @testsDirs = @cliTestDirs ? @cliTestDirs : ('test');

    my $max_process = $cliProcesses || 64;
    my $pm = Parallel::ForkManager->new($max_process);

    foreach my $testsDir (@testsDirs) {
        find(
            { wanted => \&wanted, bydepth => 1 },
            qq($test262Dir/$testsDir)
        );
        sub wanted {
            /(?<!_FIXTURE)\.[jJ][sS]$/s && push(@files, $File::Find::name);
        }
    }

    FILES:
    foreach my $file (@files) {
        $pm->start and next FILES; # do the fork
        srand(time ^ $$); # Creates a new seed for each fork
        processFile($file);

        $pm->finish; # do the exit in the child process
    };

    $pm->wait_all_children;

    close $deffh;

    seek($resfh, 0, 0);
    my @res = <$resfh>;

    open(my $logfh, '>', $tests_log)
        or die $!;

    print $logfh (sort @res);

    my $endTime = time();
    my $totalTime = $endTime - $startTime;
    print "Done in $totalTime seconds! Log saved in $tests_log\n";

    close $resfh;
    close $logfh;
}

sub processFile {
    my $filename = shift;
    my $skip = 0;

    my $contents = getContents($filename);
    # TODO: should skip from path?

    my $data = parseData($contents, $filename);
    # TODO: should skip from features?

    if (shouldSkip($filename, $data)) {
        processResult($filename, $data, "skip");
        return;
    }

    my @scenarios = getScenarios(@{ $data->{flags} });

    my $includes = $data->{includes};
    my ($includesfh, $includesfile);
    ($includesfh, $includesfile) = compileTest($includes) if defined $includes;

    foreach my $scenario (@scenarios) {
        my $result = runTest($includesfile, $filename, $scenario, $data);

        processResult($filename, $data, $scenario, $result);
    }

    close $includesfh if defined $includesfh;
}

sub shouldSkip {
    my ($filename, $data) = @_;

    my @skipPaths = @{ $config->{skip}->{paths} };
    my @skipFeatures = @{ $config->{skip}->{features} };

    # Filter by paths
    return 1 if (grep {$filename =~ $_} @skipPaths);

    if (defined $data->{features}) {
        my @features = @{ $data->{features} };
        # Filter by features, loop over file features to for less iterations
        foreach my $feature (@features) {
            return 1 if (grep {$_ eq $feature} @skipFeatures);
        }
    }
 
    return 0;
}

sub getScenarios {
    my @flags = @_;
    my @scenarios;
    my $nonStrict = 'default';
    my $strictMode = 'strict mode';
    my $moduleCode = 'module code';

    if (grep $_ eq 'noStrict', @flags) {
        push @scenarios, $nonStrict;
    } elsif (grep $_ eq 'onlyStrict', @flags) {
        push @scenarios, $strictMode;
    } elsif (grep $_ eq 'module', @flags) {
        push @scenarios, 'module';
    } else {
        # Add 2 default scenarios
        push @scenarios, $strictMode;
        push @scenarios, $nonStrict;
    };

    return @scenarios;
}

sub compileTest {
    my $includes = shift;
    my ($tfh, $tfname) = getTempFile();

    my $includesContent = getHarness(map { "$harnessDir/$_" } @{ $includes });
    print $tfh $includesContent;

    return ($tfh, $tfname);
}

sub runTest {
    my ($includesfile, $filename, $scenario, $data) = @_;
    $includesfile ||= '';

    my $args = '';

    if (exists $data->{negative}) {
        my $type = $data->{negative}->{type};
        $args .=  " --exception=$type ";
    }

    if (exists $data->{flags}) {
        my @flags = $data->{flags};
        if (grep $_ eq 'async', @flags) {
            $args .= ' --test262-async ';
        }
    }

    my $prefixFile = '';

    if ($scenario eq 'module') {
        $prefixFile='--module-file=';
    } elsif ($scenario eq 'strict mode') {
        $prefixFile='--strict-file=';
    }

    my $result = qx/$JSC $args $deffile $includesfile $prefixFile$filename/;

    chomp $result;

    return $result if ($?);
}

sub processResult {
    my ($path, $data, $scenario, $result) = @_;

    # Report a relative path
    my $file = abs2rel( $path, $test262Dir );
    my $msg;

    if ($scenario ne 'skip') {
        # TODO: use verbose mode for more information or compact information otherwise
        if ($result) {
            print "FAIL $file ($scenario)\n$result\n\n";
        }
        $msg .= "($scenario): PASS\n" if not $result;
        $msg .= "($scenario): FAIL\n" if $result;
    } else {
        $msg .= ": SKIP\n";
    }

    print $resfh "$file$msg";
}

sub getTempFile {
    my ($tfh, $tfname) = tempfile(DIR => $tempdir);

    return ($tfh, $tfname);
}

sub getContents {
    my $filename = shift;

    open(my $fh, '<', $filename) or die $!;
    my $contents = join('', <$fh>);
    close $fh;

    return $contents;
}

sub parseData {
    my ($contents, $filename) = @_;

    my $parsed;
    my $found = '';
    if ($contents =~ /\/\*(---\n[\S\s]*)\n---\*\//m) {
        $found = $1;
    };

    eval {
        $parsed = Load($found);
    };
    if ($@) {
        print "\nError parsing YAML data on file $filename.\n";
        print "$@\n";
    };
    return $parsed;
}

sub getHarness {
    my @files = @_;
    my $content;
    for (@files) {
        my $file = $_;

        open(my $harness_file, '<', $file)
            or die "$!, '$file'";

        $content .= join('', <$harness_file>);

        close $harness_file;
    };

    return $content;
}

__END__

=head1 DESCRIPTION

This program will run all test262 tests. If you edit, make sure your changes are Perl 5.8.8 compatible.

=head1 SYNOPSIS

Run using native Perl:

=over 8

./test262-runner.pl -j $jsc-dir

=back

Run using carton (recommended for testing on Perl 5.8.8):

=over 8

carton exec './test262-runner.pl -j $jsc-dir'

=back

=head1 OPTIONS

=over 8

=item B<--help, -h>

Print a brief help message and exits.

=item B<--child-processes, -p>

Specify number of child processes.

=item B<--t262, -t>

Specify a specific test262 directory of test to run, relative to the root test262 directory. For example, 'test/built-ins/Number/prototype'

=item B<--jsc, -j>

Specify JSC location. If not provided, script will attempt to look up JSC.

=item B<--debug, -d>

Use debug build of JSC. Can only use if --jsc <path> is not provided. Release build of JSC is used by default.

=back

=cut
