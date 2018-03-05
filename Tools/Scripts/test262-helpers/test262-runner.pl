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

# # Use the following code run this script directly from Perl.
# # Otherwise, just use carton.
# 
# use FindBin;
# use Config;
# use Encode;
#
# BEGIN {
#     $ENV{DBIC_OVERWRITE_HELPER_METHODS_OK} = 1;
#
#     unshift @INC, ".";
#     unshift @INC, "$FindBin::Bin/lib";
#     unshift @INC, "$FindBin::Bin/local/lib/perl5";
#     unshift @INC, "$FindBin::Bin/local/lib/perl5/$Config{archname}";
#
#     $ENV{LOAD_ROUTES} = 1;
# }

use YAML qw(Load);
use File::Find;
use FindBin;

use DDP;

main();

sub main {
#     my $data = <<'HEADERDATA';
#     description: foobar
#     info: barbaz
#     features: [async-abruption, cancelation]
# HEADERDATA

#     my $parsed_data = Load( $data );
#     p $parsed_data;
    find({ wanted => \&wanted, bydepth => 1 }, '../../../JSTests/test262/test/');
}

sub wanted {
    /\.js$/s && processFile($File::Find::name);
}

sub processFile {
    my $filename = shift;

    # print $filename, "\n";

    open(my $fh, '<', "$FindBin::Bin/$filename") or die;

    my $contents = join("\n", <$fh>);

    if ($contents =~ /\/\*---([\S\s]*)---\*\//m) {
        my $parsed = parseData($1);
    }
}

sub parseData {
    my $data = shift;

    my $parsed_data = Load( $data );
    p $parsed_data;
}
