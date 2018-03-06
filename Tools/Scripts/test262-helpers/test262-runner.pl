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
# use FindBin;

######
# # Use the following code run this script directly from Perl.
# # Otherwise, just use carton.
use FindBin;
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
use DDP;

my $tempdir = tempdir();

my @default_harnesses = (
    'sta.js',
    'assert.js'
);

my $default_content = getHarness(<@default_harnesses>);

main();

sub main {
    # find({ wanted => \&wanted, bydepth => 1 }, '../../../JSTests/test262/test/');
    find({ wanted => \&wanted, bydepth => 1 }, '../../../JSTests/test262/test/built-ins/WeakMap/prototype');
}

sub wanted {
    /\.js$/s && processFile($File::Find::name);
}

sub processFile {
    my $filename = shift;

    my $contents = getContents($filename);
    my $parsed = parseData($contents, $filename);
    my ($tfh, $tfname) = getTempFile();

    # Append the test file contents to the temporary file
    print $tfh $contents;

    runTest($tfname, $filename);

    close $tfh;
}

sub runTest {
    my ($tempfile, $filename) = @_;

    system("jsc", $tempfile);

    if ($? != 0) {
        print "$filename: $?\n";
    };
}

sub getTempFile {
    my ($tfh, $tfname) = tempfile(DIR => $tempdir);

    print $tfh $default_content;

    return ($tfh, $tfname);
}

sub getContents {
    my $filename = shift;

    open(my $fh, '<', "$FindBin::Bin/$filename") or die $!;
    my $contents = join('', <$fh>);
    close $fh;

    return $contents;
}

sub parseData {
    my ($contents, $filename) = @_;
    
    my $parsed = {};
    my $found = '';
    if ($contents =~ /\/\*(---\n[\S\s]*)\n---\*\//m) {
        $found = $1;
        #$parsed = Load($1);
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
        
        open(my $harness_file, '<',
            "$FindBin::Bin/../../../JSTests/test262/harness/$file")
            or die "$!, '$file'";

        $content .= join('', <$harness_file>);

        close $harness_file;
    };

    return $content;
}
