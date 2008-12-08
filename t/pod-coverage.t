use strict;
use warnings;

use Test::More;

plan skip_all => 'This test is only run for the module author'
    unless -d '.svn' || $ENV{IS_MAINTAINER};

eval 'use Test::Pod::Coverage 1.04; use Pod::Coverage::Moose;';
plan skip_all => 'Test::Pod::Coverage 1.04 and Pod::Coverage::Moose required for testing POD coverage'
    if $@;

my @mods = sort grep { include($_) } Test::Pod::Coverage::all_modules();

plan tests => scalar @mods;


for my $mod (@mods)
{
    my @trustme = qr/^BUILD(?:ARGS)?$/;

    pod_coverage_ok( $mod, { coverage_class => 'Pod::Coverage::Moose',
                             trustme => \@trustme,
                           },
                     "pod coverage for $mod" );
}

sub include
{
    my $mod = shift;

#    return 0 if $mod =~ /::Fragment::/;
#    return 0 if $mod =~ /::Test/;
#    return 0 if $mod =~ /::Validate/;
#    return 0 if $mod =~ /::FakeDBI/;

    return 1;
}
