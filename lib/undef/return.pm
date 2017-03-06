package undef::return;

{ use v5.18.2; }
use warnings;
use strict;

our $VERSION = "0.001";

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION);

1;
=head1 NAME

undef::return - Disallow returning undef within this scope

=head1 SYNOPSIS

    no undef::return;

    use undef::return;

=head1 DESCRIPTION

...

=cut

