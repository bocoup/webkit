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
package Test262::Runner;

use File::Find;
use File::Temp qw(tempfile tempdir);
use File::Spec::Functions qw(abs2rel);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use FindBin;
use Env qw(DYLD_FRAMEWORK_PATH);

######
# # Use the following code run this script directly from Perl.
# # Otherwise, just use carton.
use Config;
use Encode;

BEGIN {
    $ENV{DBIC_OVERWRITE_HELPER_METHODS_OK} = 1;

    unshift @INC, "$FindBin::Bin/Test262";
    unshift @INC, "$FindBin::Bin/Test262/lib";
    unshift @INC, "$FindBin::Bin/Test262/local/lib/perl5";
    unshift @INC, "$FindBin::Bin/Test262/local/lib/perl5/$Config{archname}";

    $ENV{LOAD_ROUTES} = 1;
}
######

use YAML qw(Load LoadFile Dump DumpFile Bless);
use Parallel::ForkManager;
use Getopt::Long qw(GetOptions);
use Pod::Usage;

# Commandline args
my $cliProcesses;
my @cliTestDirs;
my $verbose;
my $JSC;
my $test262Dir;
my $harnessDir;
my %filterFeatures;
my $ignoreConfig;
my $config;
my %configSkipHash;
my $expect;
my $saveNewExpectations;
my $failingOnly;

my $expectationsFile = abs_path("$FindBin::Bin/Test262/test262-expectations.yaml");
my $configFile = abs_path("$FindBin::Bin/Test262/test262-config.yaml");
my $resultsFile = abs_path("$FindBin::Bin/Test262/test262-results.yaml");

processCLI();

my $tempdir = tempdir();

my @default_harnesses = (
    "$harnessDir/sta.js",
    "$harnessDir/assert.js",
    "$harnessDir/doneprintHandle.js",
    "$FindBin::Bin/Test262/agent.js"
);

my @files;
my ($resfh, $resfilename) = getTempFile();

my ($deffh, $deffile) = getTempFile();
print $deffh getHarness(<@default_harnesses>);

my $startTime = time();

main();

sub processCLI {
    my $help = 0;
    my $debug;
    my $ignoreExpectations;
    my @ffeatures;

    # If adding a new commandline argument, you must update the POD
    # documentation at the end of the file.
    GetOptions(
        'j|jsc=s' => \$JSC,
        't|t262=s' => \$test262Dir,
        'o|test-only=s@' => \@cliTestDirs,
        'p|child-processes=i' => \$cliProcesses,
        'h|help' => \$help,
        'd|debug' => \$debug,
        'v|verbose' => \$verbose,
        'f|features=s@' => \@ffeatures,
        'c|config=s' => \$configFile,
        'i|ignore-config' => \$ignoreConfig,
        's|save-expectations' => \$saveNewExpectations,
        'x|ignore-expectations' => \$ignoreExpectations,
        'failing-files' => \$failingOnly,
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

        # For custom JSC paths, Sets only if not yet defined
        if (not defined $DYLD_FRAMEWORK_PATH) {
            $DYLD_FRAMEWORK_PATH = dirname($JSC);
        }
    } else {
        $JSC = getBuildPath($debug);

        print("Using the following jsc path: $JSC\n");
    }

    if (not defined $test262Dir) {
        $test262Dir = abs_path("$FindBin::Bin/Test262/../../../JSTests/test262");
    } else {
        $test262Dir = abs_path($test262Dir);
    }
    $harnessDir = "$test262Dir/harness";

    if (! $ignoreConfig) {
        if ($configFile and not -e $configFile) {
            die "Config file $configFile does not exist!";
        }

        $config = LoadFile($configFile) or die $!;
        if ($config->{skip} && $config->{skip}->{files}) {
            %configSkipHash = map { $_ => 1 } @{$config->{skip}->{files}};
        }
    }

    if (! $ignoreExpectations) {
        # If expectations file doesn't exist yet, just run tests, UNLESS
        # --failures-only option supplied.
        if ( $failingOnly && ! -e $expectationsFile ) {
            print "Error: Cannot run failing tests if test262-expectation.yaml file does not exist.\n";
            die;
        }
        elsif (-e $expectationsFile) {
            $expect = LoadFile($expectationsFile) or die $!;
        }
    }

    if (@ffeatures) {
        %filterFeatures = map { $_ => 1 } @ffeatures;
    }

    $cliProcesses ||= getProcesses();

    print "\n-------------------------Settings------------------------\n"
        . "Test262 Dir: $test262Dir\n"
        . "JSC: $JSC\n"
        . "DYLD_FRAMEWORK_PATH: $DYLD_FRAMEWORK_PATH\n"
        . "Child Processes: $cliProcesses\n";

    print "Features to include: " . join(', ', @ffeatures) . "\n" if @ffeatures;
    print "Paths:  " . join(', ', @cliTestDirs) . "\n" if @cliTestDirs;
    print "Config file: $configFile\n" if $config;
    print "Expectations file: $expectationsFile\n" if $expect;

    print "Verbose mode\n" if $verbose;

    print "--------------------------------------------------------\n\n";
}

sub main {
    push(@cliTestDirs, 'test') if not @cliTestDirs;

    my $max_process = $cliProcesses;
    my $pm = Parallel::ForkManager->new($max_process);

    # If we only want to re-run failure, only run tests in expectation file
    if ($failingOnly) {
        @files = map { qq($test262Dir/$_) } keys %{$expect};
    }

    # Otherwise, get all files from directory
    else {
        foreach my $testsDir (@cliTestDirs) {
            find(
                { wanted => \&wanted, bydepth => 1 },
                qq($test262Dir/$testsDir)
                );
            sub wanted {
                /(?<!_FIXTURE)\.[jJ][sS]$/s && push(@files, $File::Find::name);
            }
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
    my @res = LoadFile($resfh);
    close $resfh;

    # Save raw results in to file for later processing
    DumpFile($resultsFile, \@res);

    my %failed;
    my $failcount = 0;
    my $newfailcount = 0;
    my $newpasscount = 0;
    my $skipfilecount = 0;

    # Create expectation file and calculate results
    foreach my $test (@res) {

        my $expectedFailure = 0;
        if ($expect && $expect->{$test->{test}}) {
            $expectedFailure = $expect->{$test->{test}}->{$test->{mode}}
        }

        if ($test->{result} eq 'FAIL') {
            $failcount++;

            # Record this round of failures
            if ( $failed{$test->{test}} ) {
                $failed{$test->{test}}->{$test->{mode}} =  $test->{error};
            }
            else {
                $failed{$test->{test}} = {
                    $test->{mode} => $test->{error}
                };
            }

            # If an unexpected failure
            $newfailcount++ if !$expectedFailure || ($expectedFailure ne $test->{error});

        }
        elsif ($test->{result} eq 'PASS') {
            # If this is an newly passing test
            $newpasscount++ if $expectedFailure;
        }
        elsif ($test->{result} eq 'SKIP') {
            $skipfilecount++;
        }
    }

    if ($saveNewExpectations) {
        DumpFile($expectationsFile, \%failed);
    }

    my $endTime = time();
    my $totalTime = $endTime - $startTime;
    my $total = scalar @res - $skipfilecount;
    print "\n" . $total . " tests ran\n";

    if ( !$expect ) {
        print $failcount . " tests failed\n";
    }
    else {
        print $failcount . " expected tests failed\n";
        print $newfailcount . " tests newly fail\n";
        print $newpasscount . " tests newly pass\n";
    }

    print $skipfilecount . " test files skipped\n";
    print "Done in $totalTime seconds!\n";
    if ($saveNewExpectations) {
        print "Saved results in $expectationsFile\n";
    }
    else {
        print "Run with --save-expectations to saved results in $expectationsFile\n";
    }
}

sub getProcesses {
    my $cores;
    my $uname = qx(which uname >> /dev/null && uname);
    chomp $uname;

    if ($uname eq 'Darwin') {
        # sysctl should be available
        $cores = qx/sysctl -n hw.ncpu/;
    } elsif ($uname eq 'Linux') {
        $cores = qx(which getconf >> /dev/null && getconf _NPROCESSORS_ONLN);
        if (!$cores) {
            $cores = qx(which lscpu >> /dev/null && lscpu -p | egrep -v '^#' | wc -l);
        }
    }

    chomp $cores;

    if (!$cores) {
        $cores = 1;
    }

    return $cores * 8;
}

sub parseError {
    my $error = shift;

    if ($error =~ /^Exception: ([\w\d]+: .*)/m) {
        return $1;
    }
    else {
        # Unusual error format. Save the first line instead.
        my @errors = split("\n", $error);
        return $errors[0];
    }
}

sub getBuildPath {
    my $debug = shift;

    # Try to find JSC for user, if not supplied
    my $cmd = abs_path("$FindBin::Bin/Test262/../webkit-build-directory");
    if (! -e $cmd) {
        die 'Error: cannot find webkit-build-directory, specify with JSC with --jsc <path>.';
    }

    if ($debug) {
        $cmd .= ' --debug';
    } else {
        $cmd .= ' --release';
    }
    $cmd .= ' --executablePath';
    my $jscDir = qx($cmd);
    chomp $jscDir;

    my $jsc;
    $jsc = $jscDir . '/jsc';

    $jsc = $jscDir . '/JavaScriptCore.framework/Resources/jsc' if (! -e $jsc);
    $jsc = $jscDir . '/bin/jsc' if (! -e $jsc);
    if (! -e $jsc) {
        die 'Error: cannot find jsc, specify with --jsc <path>.';
    }

    # Sets the Env DYLD_FRAMEWORK_PATH
    $DYLD_FRAMEWORK_PATH = dirname($jsc);

    return $jsc;
}

sub processFile {
    my $filename = shift;
    my $contents = getContents($filename);
    my $data = parseData($contents, $filename);

    # Check test against filters in config file
    my $file = abs2rel( $filename, $test262Dir );
    if (shouldSkip($file, $data)) {
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

    if (exists $config->{skip}) {
        # Filter by file
        if( $configSkipHash{$filename} ) {
            return 1;
        }

        # Filter by paths
        my @skipPaths;
        @skipPaths = @{ $config->{skip}->{paths} } if defined $config->{skip}->{paths};
        return 1 if (grep {$filename =~ $_} @skipPaths);

        my @skipFeatures;
        @skipFeatures = @{ $config->{skip}->{features} } if defined $config->{skip}->{features};

        my $skip = 0;
        my $keep = 0;
        my @features = @{ $data->{features} } if $data->{features};
        # Filter by features, loop over file features to for less iterations
        foreach my $feature (@features) {
            $skip = (grep {$_ eq $feature} @skipFeatures) ? 1 : 0;

            # keep the test if the config skips the feature but it was also request
            # through the CLI --features
            return 1 if $skip && !$filterFeatures{$feature};

            $keep = 1 if $filterFeatures{$feature};
        }

        # filter tests that do not contain the --features features
        return 1 if (%filterFeatures and not $keep);
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
    my %resultdata;
    $resultdata{test} = $file;
    $resultdata{mode} = $scenario;

    my $currentfailure = parseError($result) if $result;
    my $expectedfailure = $expect
        && $expect->{$file}
        && $expect->{$file}->{$scenario};

    if ($scenario ne 'skip' && $currentfailure) {

        # We have a new failure if we have loaded an expectation file
        # AND (there is no expected failure OR the failure has changed).
        my $isnewfailure = $expect
            && (!$expectedfailure || $expectedfailure ne $currentfailure);

        # Print the failure if we haven't loaded an expectation file
        # or the failure is new.
        my $printfailure = !$expect || $isnewfailure;

        print "! NEW " if $isnewfailure;
        print "FAIL $file ($scenario)\n" if $printfailure;
        if ($verbose) {
            print $result;
            print "\nFeatures: " . join(', ', @{ $data->{features} }) if $data->{features};
            print "\n\n";
        }

        $resultdata{result} = 'FAIL';
        $resultdata{error} = $currentfailure;
    }
    elsif ($scenario ne 'skip' && !$currentfailure) {
        if ($expectedfailure) {
            print "NEW PASS $file ($scenario)\n";
            print "\n" if $verbose;
        }

        $resultdata{result} = 'PASS';
    }
    else {
        $resultdata{result} = 'SKIP';
    }

    $resultdata{features} = $data->{features} if $data->{features};

    DumpFile($resfh, \%resultdata);
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

This program will run all Test262 tests. If you edit, make sure your changes are Perl 5.8.8 compatible.

=head1 SYNOPSIS

Run using native Perl:

=over 8

test262-runner -j $jsc-dir

=back

Run using carton (recommended for testing on Perl 5.8.8):

=over 8

carton exec 'test262-runner -j $jsc-dir'

=back

=head1 OPTIONS

=over 8

=item B<--help, -h>

Print a brief help message and exits.

=item B<--child-processes, -p>

Specify number of child processes.

=item B<--t262, -t>

Specify root test262 directory.

=item B<--jsc, -j>

Specify JSC location. If not provided, script will attempt to look up JSC.

=item B<--debug, -d>

Use debug build of JSC. Can only use if --jsc <path> is not provided. Release build of JSC is used by default.

=item B<--verbose, -v>

Verbose output for test results. Includes error message for test.

=item B<--config, -c>

Specify a config file. If not provided, script will load local test262-config.yaml

=item B<--ignore-config, -i>

Ignores config file if supplied or findable in directory. Will still filter based on commandline arguments.

=item B<--features, -f>

Filter test on list of features (only runs tests in feature list).

=item B<--test-only, -o>

Specify one or more specific test262 directory of test to run, relative to the root test262 directory. For example, --test-only 'test/built-ins/Number/prototype'

=item B<--save-expectations, -s>

Overwrites the test262-expectations.yaml file with the current list of test262 files.

=item B<--ignore-expectations, -x>

Ignores the test262-expectations.yaml file and outputs all failures, instead of only unexpected failures.

=item B<--failing-files, -x>

Runs all test files that expect to fail according to the expectation file. This option will run the rests in both strict and non-strict modes, even if the test only fails in one of the two modes.

=back

=cut
