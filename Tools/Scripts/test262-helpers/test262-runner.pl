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

use YAML qw(Load);
use Try::Tiny;
use Parallel::ForkManager;

my $tempdir = tempdir();

my $test262Dir = abs_path("$FindBin::Bin/../../../JSTests/test262");
my $harnessDir = "$test262Dir/harness";

my @default_harnesses = (
    "$harnessDir/sta.js",
    "$harnessDir/assert.js",
    "$harnessDir/doneprintHandle.js",
    'agent.js'
);

my $custom_harness_api = 'agent.js';

my $default_content = getHarness(<@default_harnesses>);

my $max_process = 64;
my $pm = Parallel::ForkManager->new($max_process);
my @files;
my ($resfh, $resfilename) = getTempFile();

main();

sub main {
    # find(
    #     { wanted => \&wanted, bydepth => 1 },
    #     qq($test262Dir/test)
    # );
    # good for negative tests: '/test/language/identifiers');
    find(
        { wanted => \&wanted, bydepth => 1 },
        qq($test262Dir/test/language/expressions/async-function)
    );
    sub wanted {
        /\.js$/s && push(@files, $File::Find::name);
    }

    FILES:
    foreach my $file (@files) {
        $pm->start and next FILES; # do the fork
        srand(time ^ $$); # Creates a new seed for each fork
        processFile($file);

        $pm->finish; # do the exit in the child process
    };

    $pm->wait_all_children;
}

sub processFile {
    my $filename = shift;

    my $contents = getContents($filename);
    my $data = parseData($contents, $filename);
    my @scenarios = getScenarios(@{ $data->{flags} });

    foreach my $scenario (@scenarios) {
        my ($tfh, $tfname, $sname) = @{ $scenario };

        compileTest($contents, $data, $tfh);

        my $result = runTest($tfname, $filename, $sname, $data);

        processResult($filename, $data, $sname, $result);

        close $tfh;
    }
}

sub getScenarios {
    my @flags = @_;
    my @scenarios;

    if (grep $_ eq 'noStrict', @flags) {
        push @scenarios, [ addScenario(), "non strict" ];
    } elsif (grep $_ eq 'onlyStrict', @flags) {
        push @scenarios, [ addScenario("\"use strict;\"\n"), "strict mode" ];
    } else {
        # Add 2 default scenarios
        push @scenarios, [ addScenario("\"use strict;\"\n"), "strict mode" ];
        push @scenarios, [ addScenario(), "non strict" ];
    };

    return @scenarios;
}

sub addScenario {
    my $prepend = shift;

    my ($tfh, $tfname) = getTempFile();

    print $tfh $prepend if defined $prepend;
    print $tfh $default_content;

    return ($tfh, $tfname);
}

sub compileTest {
    my ($contents, $parsed, $tfh) = @_;

    my $includesContent;

    if (exists $parsed->{includes}) {
        my $includes = $parsed->{includes};
        $includesContent = getHarness(map { "$harnessDir/$_" } @{ $includes });
        print $tfh $includesContent;
    }

    # Append the test file contents to the temporary file
    print $tfh $contents;
}

sub runTest {
    my ($tempfile, $filename, $scenario, $data) = @_;

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

    my $result = qx/jsc $args $tempfile/;

    chomp $result;

    return $result if ($?);
}

sub processResult {
    my ($path, $data, $scenario, $result) = @_;

    my $pass = 0;

    # Report a relative path
    my $file = abs2rel( $path, $test262Dir );

    # Check if it's negative test
    if ($result) {
        print qq(FAIL $file\n$result\n\n);
    } else {
        $pass = 1;
    }

    print $resfh $file;
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

    try {
        $parsed = Load($found);
    } catch {
        print "Error parsing YAML data on file $filename.\n";
        print "@_\n";
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
